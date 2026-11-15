import XCTest
@testable import SimCore

final class NavigationTests: XCTestCase {
    /// Boston with a calm wind: 04R is in use and has an ILS.
    private func boston(seed: UInt64 = 1) throws -> Simulation {
        Simulation(seed: seed, airport: try TestSupport.airport("kbos"), initialWind: .calm, windDrifts: false)
    }

    /// The first STAR the wind allows, with enough legs to fly.
    private func star(in sim: Simulation) throws -> Procedure {
        try XCTUnwrap(sim.airport?.procedures.first { $0.kind == .star && $0.legs.count >= 3 && sim.isAvailable($0) })
    }

    /// Place an aircraft on the extended centreline of a runway, flying toward it.
    private func spawnOnFinal(_ sim: Simulation, runway: String, nm: Double, altitude: Double, speed: Double) -> Bool {
        guard let ils = sim.ilsGeometry(runway: runway) else { return false }
        let o = LocalProjection.offset(bearingDeg: ils.courseDeg + 180, distanceNM: nm)
        sim.spawn(Aircraft(callsign: "TST1",
                           eastNM: ils.thresholdEastNM + o.east, northNM: ils.thresholdNorthNM + o.north,
                           headingDeg: ils.courseDeg, altitudeFt: altitude, speedKt: speed))
        return true
    }

    // MARK: Data

    func testBostonProceduresAreComplete() throws {
        let airport = try TestSupport.airport("kbos")
        XCTAssertTrue(airport.validate().isEmpty, "\(airport.validate())")
        XCTAssertFalse(airport.procedures.filter { $0.kind == .star }.isEmpty)
        XCTAssertFalse(airport.procedures.filter { $0.kind == .approach }.isEmpty)
        XCTAssertFalse(airport.procedures.filter { $0.kind == .sid }.isEmpty)
        XCTAssertGreaterThan(airport.fixes.count, 60)
    }

    // MARK: ILS

    func testClearedILSCapturesAndLands() throws {
        let sim = try boston(seed: 3)
        XCTAssertTrue(spawnOnFinal(sim, runway: "04R", nm: 12, altitude: 3000, speed: 180))
        guard case .accepted = sim.issue(IssuedCommand(callsign: "TST1", command: .approach(runway: "04R"))) else {
            return XCTFail("clearance refused")
        }
        sim.run(seconds: 700)
        XCTAssertTrue(sim.aircraft.isEmpty, "aircraft did not land")
        XCTAssertTrue(sim.radioLog.contains { $0.speaker == .system && $0.text.contains("landed runway 04R") })
        XCTAssertFalse(sim.radioLog.contains { $0.text.contains("Going around") })
    }

    func testTooHighToCaptureTheGlidepathGoesAround() throws {
        let sim = try boston(seed: 3)
        XCTAssertTrue(spawnOnFinal(sim, runway: "04R", nm: 5, altitude: 2500, speed: 250))
        _ = sim.issue(IssuedCommand(callsign: "TST1", command: .approach(runway: "04R")))
        sim.run(seconds: 120)
        XCTAssertTrue(sim.radioLog.contains { $0.speaker == .pilot && $0.text.contains("Going around") })
        XCTAssertEqual(sim.aircraft.count, 1)
        let g = try XCTUnwrap(sim.ilsGeometry(runway: "04R"))
        XCTAssertGreaterThan(sim.aircraft[0].targetAltitudeFt, g.thresholdElevationFt + 1500)
    }

    func testApproachWithoutAirportDataIsRefused() {
        let sim = Simulation(seed: 1)
        sim.spawn(Aircraft(callsign: "TST1", eastNM: 10, northNM: 0, headingDeg: 270, altitudeFt: 3000, speedKt: 180))
        guard case .refused = sim.issue(IssuedCommand(callsign: "TST1", command: .approach(runway: "27"))) else {
            return XCTFail("expected refusal")
        }
    }

    func testApproachClearanceIsSpokenAsPhraseology() throws {
        let sim = try boston()
        sim.spawn(Aircraft(callsign: "AAL123", eastNM: 10, northNM: 0, headingDeg: 270, altitudeFt: 3000, speedKt: 180))
        _ = sim.issue(IssuedCommand(callsign: "AAL123", command: .approach(runway: "04R")))
        let text = try XCTUnwrap(sim.radioLog.first?.text)
        XCTAssertTrue(text.hasPrefix("American one two three"), text)
        XCTAssertTrue(text.contains("cleared ILS approach runway"), text)
    }

    // MARK: Routes

    func testStarIsFlownToItsLastFix() throws {
        let sim = try boston()
        let star = try star(in: sim)
        XCTAssertTrue(sim.spawn(callsign: "TST1", procedure: star.id, altitudeFt: 8000, speedKt: 250))
        var finished = false
        for _ in 0..<6000 {
            sim.tick()
            if sim.aircraft[0].route.isEmpty { finished = true; break }
        }
        XCTAssertTrue(finished, "route never completed")
        let last = try XCTUnwrap(sim.routePoints(for: [Leg(fixId: star.legs.last!.fixId)]).first)
        let ac = sim.aircraft[0]
        XCTAssertLessThan(hypot(ac.eastNM - last.eastNM, ac.northNM - last.northNM), 1.5)
    }

    func testHeadingCommandLeavesTheRoute() throws {
        let sim = try boston()
        let star = try star(in: sim)
        sim.spawn(callsign: "TST1", procedure: star.id, altitudeFt: 8000, speedKt: 250)
        XCTAssertFalse(sim.aircraft[0].route.isEmpty)
        _ = sim.issue(IssuedCommand(callsign: "TST1", command: .heading(degrees: 180)))
        sim.run(seconds: 10)
        XCTAssertTrue(sim.aircraft[0].route.isEmpty)
        XCTAssertEqual(sim.aircraft[0].navLabel, "HDG")
    }

    // MARK: Direct and join approach

    func testDirectToUnknownFixIsRefused() throws {
        let sim = try boston()
        let star = try star(in: sim)
        sim.spawn(callsign: "TST1", procedure: star.id, startIndex: 1, altitudeFt: 8000, speedKt: 220)
        XCTAssertEqual(sim.issue(IssuedCommand(callsign: "TST1", command: .direct(fix: "NOPE"))), .refused("unknown fix NOPE"))
    }

    func testJoinUnknownApproachIsRefused() throws {
        let sim = try boston()
        let star = try star(in: sim)
        sim.spawn(callsign: "TST1", procedure: star.id, startIndex: 1, altitudeFt: 8000, speedKt: 220)
        let r = sim.issue(IssuedCommand(callsign: "TST1", command: .joinApproach(procedure: "NOPE", runway: "04R", via: "X")))
        XCTAssertEqual(r, .refused("unknown approach NOPE"))
    }
}
