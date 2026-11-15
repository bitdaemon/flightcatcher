import XCTest
@testable import SimCore

/// Runways without an ILS (Boston 09) get a visual approach built from the runway itself.
final class VisualApproachTests: XCTestCase {
    private func sim(wind: Wind) throws -> Simulation {
        Simulation(seed: 3, airport: try TestSupport.airport("kbos"), initialWind: wind, windDrifts: false)
    }

    private func spawnOnFinal(_ s: Simulation, runway: String, nm: Double, altitude: Double, speed: Double) throws {
        let g = try XCTUnwrap(s.approachGeometry(runway: runway))
        let o = LocalProjection.offset(bearingDeg: g.courseDeg + 180, distanceNM: nm)
        s.spawn(Aircraft(callsign: "TST1", eastNM: g.thresholdEastNM + o.east, northNM: g.thresholdNorthNM + o.north,
                         headingDeg: g.courseDeg, altitudeFt: altitude, speedKt: speed))
    }

    func testRunwayWithoutIlsGetsVisualGeometry() throws {
        let s = try sim(wind: .calm)
        XCTAssertNil(s.ilsGeometry(runway: "09"))
        let g = try XCTUnwrap(s.approachGeometry(runway: "09"))
        XCTAssertTrue(g.isVisual)
        XCTAssertEqual(g.glidepathDeg, 3.0)
        XCTAssertEqual(g.courseDeg, 76.52, accuracy: 0.01)
        XCTAssertFalse(try XCTUnwrap(s.approachGeometry(runway: "27")).isVisual)
        XCTAssertNil(s.approachGeometry(runway: "99"))
    }

    func testApproachCommandBecomesVisualWithoutAnIls() throws {
        let s = try sim(wind: Wind(fromDeg: 90, speedKt: 8)) // 09 is the runway in use
        try spawnOnFinal(s, runway: "09", nm: 12, altitude: 3000, speed: 180)
        guard case .accepted = s.issue(IssuedCommand(callsign: "TST1", command: .approach(runway: "09"))) else {
            return XCTFail("clearance refused")
        }
        XCTAssertTrue(s.radioLog.contains { $0.speaker == .controller && $0.text.contains("cleared visual approach runway") })
        s.run(seconds: 10)
        XCTAssertEqual(s.aircraft.first?.approach?.ils.isVisual, true)
    }

    func testVisualApproachCapturesAndLands() throws {
        let s = try sim(wind: Wind(fromDeg: 90, speedKt: 8))
        try spawnOnFinal(s, runway: "09", nm: 12, altitude: 3000, speed: 180)
        _ = s.issue(IssuedCommand(callsign: "TST1", command: .visualApproach(runway: "09")))
        s.run(seconds: 700)
        XCTAssertTrue(s.aircraft.isEmpty, "aircraft did not land")
        XCTAssertTrue(s.radioLog.contains { $0.speaker == .system && $0.text.contains("landed runway 09") })
        XCTAssertFalse(s.radioLog.contains { $0.text.contains("Going around") })
    }

    func testClosedRunwayRefusesVisualApproach() throws {
        // Wind from 270 at 15 kt is a 15 kt tailwind on 09.
        let s = try sim(wind: Wind(fromDeg: 270, speedKt: 15))
        try spawnOnFinal(s, runway: "09", nm: 12, altitude: 3000, speed: 180)
        guard case .refused(let reason) = s.issue(IssuedCommand(callsign: "TST1", command: .approach(runway: "09"))) else {
            return XCTFail("closed runway accepted")
        }
        XCTAssertTrue(reason.contains("closed"), reason)
    }

    func testPhraseologyAndLabels() {
        XCTAssertEqual(Command.visualApproach(runway: "09").chipLabel, "VIS 09")
        XCTAssertEqual(Command.visualApproach(runway: "09").summary, "cleared visual approach runway 09")
        var a = Aircraft(callsign: "TST1", eastNM: 0, northNM: 0, headingDeg: 0, altitudeFt: 3000, speedKt: 180)
        a.applyType(AircraftCatalog.all[0])
        XCTAssertTrue(Phraseology.instruction(.visualApproach(runway: "09"), for: a, transitionAltitudeFt: 5000)
                        .hasPrefix("cleared visual approach runway"))
    }
}

final class MissedApproachAltitudeTests: XCTestCase {
    func testGoAroundClimbsAboveTheFieldNotToAFixedLevel() throws {
        let airport = try AirportPackage.loadBundled("kabq")
        let s = Simulation(seed: 3, airport: airport, initialWind: .calm, windDrifts: false)
        let runway = try XCTUnwrap(s.openRunways.sorted().first)
        let g = try XCTUnwrap(s.approachGeometry(runway: runway))
        let o = LocalProjection.offset(bearingDeg: g.courseDeg + 180, distanceNM: 8)
        s.spawn(Aircraft(callsign: "TST1", eastNM: g.thresholdEastNM + o.east, northNM: g.thresholdNorthNM + o.north,
                         headingDeg: g.courseDeg, altitudeFt: 12000, speedKt: 180))
        _ = s.issue(IssuedCommand(callsign: "TST1", command: .approach(runway: runway)))
        s.run(seconds: 150)
        XCTAssertTrue(s.radioLog.contains { $0.text.contains("Going around") }, "too high to capture should go around")
        let ac = try XCTUnwrap(s.aircraft.first)
        XCTAssertGreaterThan(ac.targetAltitudeFt, g.thresholdElevationFt + 1500)
    }
}

final class LevelFloorTests: XCTestCase {
    func testFloorRoundsFieldElevationPlusTwoThousandUp() {
        XCTAssertEqual(CommandLimits.floorFt(fieldElevationFt: 0), 2000)
        XCTAssertEqual(CommandLimits.floorFt(fieldElevationFt: 242), 3000)
        XCTAssertEqual(CommandLimits.floorFt(fieldElevationFt: 5355), 8000)
    }

    func testHighAirportRefusesLowLevels() throws {
        let airport = try AirportPackage.loadBundled("kabq")
        let s = Simulation(seed: 1, airport: airport, initialWind: .calm, windDrifts: false)
        XCTAssertEqual(s.levelFloorFt, 8000)
        s.spawn(Aircraft(callsign: "TST1", eastNM: 20, northNM: 0, headingDeg: 270, altitudeFt: 12000, speedKt: 250))
        let ac = try XCTUnwrap(s.aircraft.first)
        XCTAssertNotNil(Command.descend(feet: 3000).refusal(for: ac))
        XCTAssertNotNil(Command.descend(feet: 7000).refusal(for: ac))
        XCTAssertNil(Command.descend(feet: 8000).refusal(for: ac))
        XCTAssertNotNil(Command.cross(fix: "X", altitudeFt: 5000).refusal(for: ac))
    }

    func testBostonFloorIsThreeThousand() throws {
        let airport = try TestSupport.airport("kbos")
        let s = Simulation(seed: 1, airport: airport, initialWind: .calm, windDrifts: false)
        XCTAssertEqual(s.levelFloorFt, 3000)
    }
}

final class HandoffGlidepathTests: XCTestCase {
    func testNoHandoffWhileWellAboveTheGlidepath() throws {
        let airport = try AirportPackage.loadBundled("kabq")
        let s = Simulation(seed: 3, airport: airport, initialWind: .calm, windDrifts: false)
        let runway = try XCTUnwrap(s.openRunways.sorted().first)
        let g = try XCTUnwrap(s.approachGeometry(runway: runway))
        let o = LocalProjection.offset(bearingDeg: g.courseDeg + 180, distanceNM: 8)
        var ac = Aircraft(callsign: "TST1", eastNM: g.thresholdEastNM + o.east, northNM: g.thresholdNorthNM + o.north,
                          headingDeg: g.courseDeg, altitudeFt: 12000, speedKt: 160)
        ac.approach = ApproachClearance(ils: g, phase: .localiser)
        XCTAssertNotNil(Command.handoff.refusal(for: ac))
        ac.altitudeFt = g.glidepathAltitudeFt(distanceNM: 8)
        XCTAssertNil(Command.handoff.refusal(for: ac))
    }
}

final class ApproachFloorTests: XCTestCase {
    func testClearedAircraftMayDescendToTheGlidepathRegion() throws {
        XCTAssertEqual(CommandLimits.approachFloorFt(fieldElevationFt: 5355), 6000)
        XCTAssertEqual(CommandLimits.approachFloorFt(fieldElevationFt: 242), 2000)
        let airport = try AirportPackage.loadBundled("kabq")
        let s = Simulation(seed: 1, airport: airport, initialWind: .calm, windDrifts: false)
        let runway = try XCTUnwrap(s.openRunways.sorted().first)
        let g = try XCTUnwrap(s.approachGeometry(runway: runway))
        s.spawn(Aircraft(callsign: "TST1", eastNM: 20, northNM: 0, headingDeg: 270, altitudeFt: 12000, speedKt: 250))
        var ac = try XCTUnwrap(s.aircraft.first)
        XCTAssertNotNil(Command.descend(feet: 6000).refusal(for: ac))
        ac.approach = ApproachClearance(ils: g, phase: .localiser)
        XCTAssertNil(Command.descend(feet: 6000).refusal(for: ac))
        XCTAssertNotNil(Command.descend(feet: 5000).refusal(for: ac))
    }
}

final class StartupSeparationTests: XCTestCase {
    func testClearSpawnRefusesToStackAircraft() throws {
        let airport = try AirportPackage.loadBundled("katl")
        let s = Simulation(seed: 1, airport: airport, initialWind: .calm, windDrifts: false)
        let star = try XCTUnwrap(airport.procedures.first { $0.kind == .star && s.isAvailable($0) && $0.legs.count >= 4 })
        XCTAssertTrue(s.spawn(callsign: "AAA1", procedure: star.id, startIndex: 1, altitudeFt: 9000, speedKt: 240, requireClear: true))
        XCTAssertFalse(s.spawn(callsign: "BBB2", procedure: star.id, startIndex: 1, altitudeFt: 9000, speedKt: 240, requireClear: true))
        XCTAssertTrue(s.spawn(callsign: "CCC3", procedure: star.id, startIndex: 1, altitudeFt: 13000, speedKt: 240, requireClear: true))
    }
}
