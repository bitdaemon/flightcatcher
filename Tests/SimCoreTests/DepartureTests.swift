import XCTest
@testable import SimCore

final class DepartureTests: XCTestCase {
    private func sim(seed: UInt64 = 3) throws -> Simulation {
        var airport = try TestSupport.airport("kbos")
        // These tests assume a single departure runway. Every open runway gets departures, so keep only 04R.
        airport.runways.removeAll { $0.id != "04R" }
        return Simulation(seed: seed, transitionAltitudeFt: airport.transitionAltitudeFt, airport: airport,
                          initialWind: .calm, windDrifts: false)
    }

    /// A simulation with up to three departures holding short of 04R and no further traffic.
    private func simWithDepartures() throws -> Simulation {
        let s = try sim()
        s.traffic = TrafficSettings(enabled: true, arrivalsPerHour: 0, departuresPerHour: 3600)
        s.run(seconds: 5)
        s.traffic = TrafficSettings(enabled: false)
        return s
    }

    private func departures(_ s: Simulation) -> [Aircraft] { s.aircraft.filter { $0.departure != nil } }

    func testDeparturesAppearAtTheHoldingPointAndNeverMoreThanThreePerRunway() throws {
        let s = try simWithDepartures()
        let waiting = departures(s)
        XCTAssertEqual(waiting.count, 3)
        for ac in waiting {
            XCTAssertEqual(ac.groundPhase, .holdingShort)
            XCTAssertEqual(ac.departure?.runway, "04R")
            XCTAssertEqual(ac.speedKt, 0)
            XCTAssertTrue(s.airport!.procedures.contains { $0.id == ac.departure?.sid && $0.kind == .sid })
        }
        XCTAssertEqual(Set(waiting.map(\.callsign)).count, 3)
        XCTAssertTrue(s.radioLog.contains { $0.speaker == .pilot && $0.text.contains("ready for departure") })
        XCTAssertTrue(s.conflicts.isEmpty, "aircraft on the ground are not traffic")
    }

    func testTakeoffClimbAndHandoff() throws {
        let s = try simWithDepartures()
        let first = try XCTUnwrap(departures(s).first)
        let callsign = first.callsign
        XCTAssertEqual(s.issue(IssuedCommand(callsign: callsign, command: .takeoff)).isAccepted, true)
        XCTAssertTrue(s.radioLog.contains { $0.speaker == .controller && $0.text.contains("wind calm") && $0.text.contains("cleared for take-off") })
        s.run(seconds: 15)
        XCTAssertEqual(s.aircraft.first { $0.callsign == callsign }?.groundPhase, .takeoffRoll)
        s.run(seconds: 285)
        let climbing = try XCTUnwrap(s.aircraft.first { $0.callsign == callsign })
        XCTAssertNil(climbing.groundPhase)
        XCTAssertEqual(climbing.altitudeFt, 3000, accuracy: 60)
        XCTAssertFalse(climbing.route.isEmpty, "it is flying its SID")
        XCTAssertTrue(s.radioLog.contains { $0.speaker == .pilot && $0.text.hasPrefix("Departure,") && $0.text.contains("departure") })

        guard case .refused(let reason) = s.issue(IssuedCommand(callsign: callsign, command: .handoff)) else {
            return XCTFail("a departure still at its initial level cannot be handed off")
        }
        XCTAssertTrue(reason.contains("handoff at"), reason)
        let d = try XCTUnwrap(climbing.departure)
        XCTAssertEqual(d.handoffAltitudeFt, 5000)
        XCTAssertGreaterThanOrEqual(d.expectedLevelFt, d.handoffAltitudeFt)
        XCTAssertEqual(s.issue(IssuedCommand(callsign: callsign, command: .climb(feet: 6000))).isAccepted, true)
        s.run(seconds: 150)
        guard case .refused(let planReason) = s.issue(IssuedCommand(callsign: callsign, command: .handoff)) else {
            return XCTFail("cleared only to 6000 ft, below its plan level")
        }
        XCTAssertTrue(planReason.contains("plan level"), planReason)
        XCTAssertEqual(s.issue(IssuedCommand(callsign: callsign, command: .climb(feet: d.expectedLevelFt))).isAccepted, true)
        s.run(seconds: 30)
        XCTAssertEqual(s.issue(IssuedCommand(callsign: callsign, command: .handoff)).isAccepted, true)
        s.run(seconds: 10)
        XCTAssertNil(s.aircraft.first { $0.callsign == callsign })
        XCTAssertTrue(s.radioLog.contains { $0.text.contains("\(callsign) handed off") })
        XCTAssertEqual(s.missedHandoffs, 0)
    }

    func testOnlyOneAircraftOnTheRunway() throws {
        let s = try simWithDepartures()
        let two = Array(departures(s).prefix(2))
        XCTAssertEqual(s.issue(IssuedCommand(callsign: two[0].callsign, command: .lineUp)).isAccepted, true)
        s.run(seconds: 10)
        XCTAssertEqual(s.aircraft.first { $0.callsign == two[0].callsign }?.groundPhase, .linedUp)
        XCTAssertEqual(s.issue(IssuedCommand(callsign: two[1].callsign, command: .lineUp)),
                       .refused("runway 04R is occupied"))
        XCTAssertEqual(s.issue(IssuedCommand(callsign: two[1].callsign, command: .takeoff)),
                       .refused("runway 04R is occupied"))
    }

    func testNoTakeoffClearanceWithAnArrivalOnShortFinal() throws {
        let s = try simWithDepartures()
        let ils = try XCTUnwrap(s.ilsGeometry(runway: "04R"))
        let behind = LocalProjection.offset(bearingDeg: ils.courseDeg + 180, distanceNM: 3)
        var arrival = Aircraft(callsign: "RYR9", eastNM: ils.thresholdEastNM + behind.east,
                               northNM: ils.thresholdNorthNM + behind.north,
                               headingDeg: ils.courseDeg, altitudeFt: 1200, speedKt: 150)
        arrival.clearForApproach(ils, extraRoute: [])
        s.spawn(arrival)
        let departure = try XCTUnwrap(departures(s).first)
        guard case .refused(let reason) = s.issue(IssuedCommand(callsign: departure.callsign, command: .takeoff)) else {
            return XCTFail("take-off should be refused")
        }
        XCTAssertTrue(reason.contains("RYR9"), reason)
    }

    func testArrivalGoesAroundWhenTheRunwayIsOccupied() throws {
        let s = try simWithDepartures()
        let departure = try XCTUnwrap(departures(s).first)
        XCTAssertEqual(s.issue(IssuedCommand(callsign: departure.callsign, command: .lineUp)).isAccepted, true)
        s.run(seconds: 10)
        let ils = try XCTUnwrap(s.ilsGeometry(runway: "04R"))
        let behind = LocalProjection.offset(bearingDeg: ils.courseDeg + 180, distanceNM: 1.4)
        var arrival = Aircraft(callsign: "RYR9", eastNM: ils.thresholdEastNM + behind.east,
                               northNM: ils.thresholdNorthNM + behind.north,
                               headingDeg: ils.courseDeg, altitudeFt: 700, speedKt: 140)
        arrival.clearForApproach(ils, extraRoute: [])
        arrival.approach?.phase = .glideslope   // established, so only the occupied runway can stop it
        s.spawn(arrival)
        s.run(seconds: 3)
        XCTAssertTrue(s.radioLog.contains { $0.text.contains("go-around: runway 04R occupied") })
    }

    func testGroundAircraftRefuseOrdinaryCommands() throws {
        let s = try simWithDepartures()
        let holding = try XCTUnwrap(departures(s).first)
        XCTAssertNotNil(Command.climb(feet: 5000).refusal(for: holding))
        XCTAssertNotNil(Command.handoff.refusal(for: holding))
        XCTAssertNil(Command.lineUp.refusal(for: holding))
        XCTAssertNil(Command.takeoff.refusal(for: holding))
        var arrival = Aircraft(callsign: "RYR9", eastNM: 0, northNM: 0, headingDeg: 0, altitudeFt: 5000, speedKt: 200)
        arrival.applyType(AircraftCatalog.type(code: "A320")!)
        XCTAssertNotNil(Command.takeoff.refusal(for: arrival))
        XCTAssertNotNil(Command.handoff.refusal(for: arrival))
    }

    func testUnhandedDepartureIsCountedAsMissed() throws {
        let s = try simWithDepartures()
        let callsign = try XCTUnwrap(departures(s).first).callsign
        _ = s.issue(IssuedCommand(callsign: callsign, command: .takeoff))
        s.run(seconds: 120)
        _ = s.issue(IssuedCommand(callsign: callsign, command: .climb(feet: 20000)))
        s.run(seconds: 1500)
        XCTAssertEqual(s.missedHandoffs, 1)
        XCTAssertNil(s.aircraft.first { $0.callsign == callsign })
    }

    func testCommandBarWords() {
        var holding = Aircraft(callsign: "EIN123", eastNM: 0, northNM: 0, headingDeg: 275, altitudeFt: 203, speedKt: 0)
        holding.departure = DepartureInfo(runway: "04R", sid: "ABCDE1A", initialAltitudeFt: 3000, fieldElevationFt: 203, rotateSpeedKt: 148)
        holding.groundPhase = .holdingShort
        let lu = CommandBar.evaluate(input: "ein123 lu", aircraft: [holding], selected: nil)
        XCTAssertEqual(lu.status, .ready)
        XCTAssertEqual(lu.issued?.command, .lineUp)
        XCTAssertEqual(CommandBar.evaluate(input: "ein123 to", aircraft: [holding], selected: nil).issued?.command, .takeoff)
        XCTAssertEqual(CommandBar.evaluate(input: "ho", aircraft: [holding], selected: "EIN123").status, .error)
        XCTAssertEqual(CommandBar.evaluate(input: "ein123 d50", aircraft: [holding], selected: nil).status, .error)
    }

    func testPhraseology() {
        XCTAssertEqual(Phraseology.spokenProcedure("ABCDE1A"), "ABCDE one Alfa")
        XCTAssertEqual(Phraseology.spokenProcedure("BLZZR6.RW04R"), "BLZZR six")
        XCTAssertEqual(Phraseology.spokenWind(.calm), "wind calm")
        XCTAssertEqual(Phraseology.spokenWind(Wind(fromDeg: 260, speedKt: 12)), "wind two six zero degrees one two knots")
        XCTAssertEqual(Simulation.oppositeRunway("28L"), "10R")
        XCTAssertEqual(Simulation.oppositeRunway("04R"), "22L")
        XCTAssertEqual(Simulation.oppositeRunway("36"), "18")
        XCTAssertEqual(Simulation.oppositeRunway("18"), "36")
    }

    func testOldSettingsDecodeWithDefaultDepartures() throws {
        let old = #"{"enabled":true,"arrivalsPerHour":20}"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(TrafficSettings.self, from: old)
        XCTAssertEqual(decoded.departuresPerHour, 8)
    }
}

private extension IssueResult {
    var isAccepted: Bool { if case .accepted = self { return true } else { return false } }
}

final class HandoffTests: XCTestCase {
    private func sim() throws -> Simulation {
        let airport = try TestSupport.airport("kbos")
        return Simulation(seed: 5, transitionAltitudeFt: airport.transitionAltitudeFt, airport: airport,
                          initialWind: .calm, windDrifts: false)
    }

    /// An arrival established on the glideslope of 04R, 6 NM out.
    private func established(_ s: Simulation, phase: ApproachPhase = .glideslope) throws -> String {
        let ils = try XCTUnwrap(s.ilsGeometry(runway: "04R"))
        let behind = LocalProjection.offset(bearingDeg: ils.courseDeg + 180, distanceNM: 6)
        var ac = Aircraft(callsign: "RYR9", eastNM: ils.thresholdEastNM + behind.east,
                          northNM: ils.thresholdNorthNM + behind.north,
                          headingDeg: ils.courseDeg, altitudeFt: 2100, speedKt: 160)
        ac.clearForApproach(ils, extraRoute: [])
        ac.approach?.phase = phase
        s.spawn(ac)
        return ac.callsign
    }

    func testArrivalCannotBeHandedOffBeforeItIsEstablished() throws {
        let s = try sim()
        let callsign = try established(s, phase: .intercepting)
        guard case .refused(let reason) = s.issue(IssuedCommand(callsign: callsign, command: .handoff)) else {
            return XCTFail("should be refused")
        }
        XCTAssertTrue(reason.contains("established"), reason)
    }

    func testHandedOffArrivalStaysOnTheScopeUntilItLandsAndTakesNoMoreInstructions() throws {
        let s = try sim()
        let callsign = try established(s)
        _ = s.issue(IssuedCommand(callsign: callsign, command: .handoff))
        s.run(seconds: 10)
        let ac = try XCTUnwrap(s.aircraft.first { $0.callsign == callsign })
        XCTAssertTrue(ac.handedToTower)
        XCTAssertEqual(ac.navLabel, "TWR")
        XCTAssertTrue(ac.labelBottom.hasSuffix("TWR"))
        XCTAssertEqual(s.issue(IssuedCommand(callsign: callsign, command: .speed(knots: 150))),
                       .refused("\(callsign) is with the tower"))
        XCTAssertTrue(s.radioLog.contains { $0.speaker == .pilot && $0.text.hasPrefix("Contact tower") })
        s.run(seconds: 200)
        XCTAssertNil(s.aircraft.first { $0.callsign == callsign }, "gone only after landing")
        XCTAssertTrue(s.radioLog.contains { $0.text.contains("\(callsign) landed runway 04R") })
    }

    func testGoAroundReturnsTheAircraftToTheController() {
        var ac = Aircraft(callsign: "RYR9", eastNM: 0, northNM: 0, headingDeg: 275, altitudeFt: 1000, speedKt: 150)
        ac.handedToTower = true
        ac.abortApproach(reason: "runway occupied")
        XCTAssertFalse(ac.handedToTower)
    }
}

final class StripOrderTests: XCTestCase {
    private func plane(_ callsign: String, east: Double = 0, north: Double = 0) -> Aircraft {
        Aircraft(callsign: callsign, eastNM: east, northNM: north, headingDeg: 0, altitudeFt: 5000, speedKt: 200)
    }

    private func departure(_ callsign: String, phase: GroundPhase?, east: Double = 0) -> Aircraft {
        var ac = plane(callsign, east: east)
        ac.departure = DepartureInfo(runway: "04R", sid: "ABCDE1A", initialAltitudeFt: 3000, fieldElevationFt: 203, rotateSpeedKt: 150)
        ac.groundPhase = phase
        return ac
    }

    func testArrivalsAndDeparturesAreSeparatedAndOrdered() {
        let list = [plane("FAR1", east: 40), departure("DEP3", phase: .holdingShort), plane("NEAR1", east: 5),
                    departure("DEP1", phase: .takeoffRoll), plane("MID1", east: 20), departure("DEP2", phase: .linedUp),
                    departure("DEP4", phase: nil, east: 10), departure("DEP5", phase: nil, east: 25)]
        XCTAssertEqual(StripOrder.arrivals(list).map(\.callsign), ["NEAR1", "MID1", "FAR1"])
        XCTAssertEqual(StripOrder.departures(list).map(\.callsign), ["DEP1", "DEP2", "DEP3", "DEP5", "DEP4"])
    }

    func testHoldingQueueKeepsArrivalOrderAndHandedToTowerArrivalsStayArrivals() {
        var landing = plane("LAND1", east: 3)
        landing.handedToTower = true
        let list = [departure("ZZZ9", phase: .holdingShort), departure("AAA1", phase: .holdingShort), landing]
        XCTAssertEqual(StripOrder.departures(list).map(\.callsign), ["ZZZ9", "AAA1"])
        XCTAssertEqual(StripOrder.arrivals(list).map(\.callsign), ["LAND1"])
    }
}

final class DemoIdentityTests: XCTestCase {
    func testUsAirportGetsUsCallsigns() throws {
        let airport = try AirportPackage.loadBundled("kabq")
        XCTAssertEqual(airport.country, "US")
        let s = Simulation(seed: 2, transitionAltitudeFt: airport.transitionAltitudeFt, airport: airport,
                           initialWind: .calm, windDrifts: false)
        var seen = Set<String>()
        for _ in 0..<40 {
            let identity = s.randomArrivalIdentity()
            XCTAssertTrue(identity.type.canFlyIFR)
            seen.insert(String(identity.callsign.prefix(3)))
        }
        XCTAssertTrue(seen.isDisjoint(with: ["RYR", "EZY", "VLG"]), "\(seen)")
        XCTAssertTrue(!seen.isDisjoint(with: ["AAL", "DAL", "UAL", "SWA", "SKW"]), "\(seen)")
    }
}
