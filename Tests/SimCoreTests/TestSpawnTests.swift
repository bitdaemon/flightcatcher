import XCTest
@testable import SimCore

final class TestSpawnTests: XCTestCase {
    private func boston() throws -> Simulation {
        Simulation(seed: 1, airport: try TestSupport.airport("kbos"), initialWind: Wind(fromDeg: 270, speedKt: 8), windDrifts: false)
    }

    func testPlacesAircraftWhereAsked() throws {
        let sim = try boston()
        let callsign = sim.spawnTest(TestSpawn(callsign: "asa1472", typeCode: "A320",
                                               eastNM: 12, northNM: -3, headingDeg: 450, altitudeFt: 3000, speedKt: 190))
        XCTAssertEqual(callsign, "ASA1472")
        let ac = try XCTUnwrap(sim.aircraft.first { $0.callsign == "ASA1472" })
        XCTAssertEqual(ac.eastNM, 12, accuracy: 0.001)
        XCTAssertEqual(ac.northNM, -3, accuracy: 0.001)
        XCTAssertEqual(ac.headingDeg, 90, accuracy: 0.001)
        XCTAssertEqual(ac.altitudeFt, 3000, accuracy: 0.001)
        XCTAssertEqual(ac.speedKt, 190, accuracy: 0.001)
        XCTAssertEqual(ac.typeCode, "A320")
        XCTAssertNil(ac.departure)
    }

    func testBlankOrTakenCallsignGetsTestName() throws {
        let sim = try boston()
        let spec = TestSpawn(callsign: "", eastNM: 10, northNM: 0, headingDeg: 90, altitudeFt: 3000, speedKt: 190)
        XCTAssertEqual(sim.spawnTest(spec), "TST1")
        XCTAssertEqual(sim.spawnTest(spec), "TST2")
        var again = spec
        again.callsign = "TST1"
        XCTAssertEqual(sim.spawnTest(again), "TST3")
    }

    func testUnknownTypeFallsBackAndRunwayReferenceIsOffsetFromCentre() throws {
        let sim = try boston()
        let callsign = sim.spawnTest(TestSpawn(typeCode: "ZZZZ", eastNM: 0, northNM: 0, headingDeg: 0, altitudeFt: 0, speedKt: 10))
        let ac = try XCTUnwrap(sim.aircraft.first { $0.callsign == callsign })
        XCTAssertEqual(ac.typeCode, "B738")
        XCTAssertEqual(ac.speedKt, 60, accuracy: 0.001)   // clamped to a sensible minimum
        let threshold = sim.referencePoint(runway: "27")
        XCTAssertGreaterThan(hypot(threshold.east, threshold.north), 0.1)
        let centre = sim.referencePoint(runway: nil)
        XCTAssertEqual(centre.east, 0, accuracy: 0.0001)
        XCTAssertEqual(centre.north, 0, accuracy: 0.0001)
    }

    func testSpawnDoesNotChangeTheTrafficSequence() throws {
        let a = try boston()
        let b = try boston()
        b.spawnTest(TestSpawn(eastNM: 30, northNM: 30, headingDeg: 0, altitudeFt: 9000, speedKt: 250))
        a.run(seconds: 600)
        b.run(seconds: 600)
        XCTAssertEqual(a.wind, b.wind)
    }
}

extension TestSpawnTests {
    func testDeleteRemovesTheAircraftAndItsQueuedCommands() throws {
        let sim = Simulation(seed: 1, airport: try TestSupport.airport("kbos"), initialWind: Wind(fromDeg: 270, speedKt: 8), windDrifts: false)
        let callsign = sim.spawnTest(TestSpawn(eastNM: 10, northNM: 0, headingDeg: 90, altitudeFt: 5000, speedKt: 220))
        _ = sim.issue(IssuedCommand(callsign: callsign, command: .descend(feet: 4000)))
        XCTAssertTrue(sim.removeAircraft(callsign: callsign))
        XCTAssertFalse(sim.aircraft.contains { $0.callsign == callsign })
        XCTAssertNil(sim.commandHistory[callsign])
        XCTAssertFalse(sim.removeAircraft(callsign: callsign))
        sim.run(seconds: 30)   // the dropped command must not crash or resurrect anything
        XCTAssertFalse(sim.aircraft.contains { $0.callsign == callsign })
    }
}

extension TestSpawnTests {
    func testPilotSaysUnableWhenTheInterceptCannotWork() throws {
        let sim = Simulation(seed: 1, airport: try TestSupport.airport("kbos"), initialWind: Wind(fromDeg: 300, speedKt: 10), windDrifts: false)
        let airport = try XCTUnwrap(sim.airport)
        let runway = try XCTUnwrap(airport.runways.first { $0.id == "33L" })
        // Ten miles out on the extended centreline of 33L, flying directly away from it.
        let origin = sim.referencePoint(runway: "33L")
        let offset = LocalProjection.offset(bearingDeg: runway.trueBearingDeg + 180, distanceNM: 10)
        let callsign = sim.spawnTest(TestSpawn(eastNM: origin.east + offset.east, northNM: origin.north + offset.north,
                                               headingDeg: runway.trueBearingDeg + 180, altitudeFt: 3000, speedKt: 190))
        _ = sim.issue(IssuedCommand(callsign: callsign, command: .approach(runway: "33L")))
        sim.run(seconds: 15)
        XCTAssertFalse(sim.radioLog.contains { $0.speaker == .pilot && $0.text.contains("Unable to intercept") })
        sim.run(seconds: 60)
        let calls = sim.radioLog.filter { $0.speaker == .pilot && $0.text.contains("Unable to intercept") }
        XCTAssertEqual(calls.count, 1, "said once, not repeatedly")
        XCTAssertEqual(calls.first?.callsign, callsign)
        XCTAssertTrue(calls.first?.text.contains("we're heading") == true, calls.first?.text ?? "")
        XCTAssertTrue(calls.first?.text.contains("we'll need a vector") == true, calls.first?.text ?? "")
    }
}

extension TestSpawnTests {
    func testPilotAsksForLowerWhenAboveTheGlidepath() throws {
        let sim = Simulation(seed: 1, airport: try TestSupport.airport("kbos"), initialWind: Wind(fromDeg: 270, speedKt: 8), windDrifts: false)
        let ils = try XCTUnwrap(sim.ilsGeometry(runway: "27"))
        let origin = sim.referencePoint(runway: "27")
        let offset = LocalProjection.offset(bearingDeg: ils.courseDeg + 180, distanceNM: 10)
        // On the centreline 10 NM out and 6,000 ft: far above the glidepath (about 3,250 ft there).
        let callsign = sim.spawnTest(TestSpawn(eastNM: origin.east + offset.east, northNM: origin.north + offset.north,
                                               headingDeg: ils.courseDeg, altitudeFt: 6000, speedKt: 180))
        _ = sim.issue(IssuedCommand(callsign: callsign, command: .approach(runway: "27")))
        sim.run(seconds: 40)
        let calls = sim.radioLog.filter { $0.speaker == .pilot && $0.text.contains("above the glidepath") }
        XCTAssertEqual(calls.count, 1, "said once")
        XCTAssertEqual(calls.first?.callsign, callsign)
    }

    func testNoGlidepathCallWhenLowEnough() throws {
        let sim = Simulation(seed: 1, airport: try TestSupport.airport("kbos"), initialWind: Wind(fromDeg: 270, speedKt: 8), windDrifts: false)
        let ils = try XCTUnwrap(sim.ilsGeometry(runway: "27"))
        let origin = sim.referencePoint(runway: "27")
        let offset = LocalProjection.offset(bearingDeg: ils.courseDeg + 180, distanceNM: 12)
        let callsign = sim.spawnTest(TestSpawn(eastNM: origin.east + offset.east, northNM: origin.north + offset.north,
                                               headingDeg: ils.courseDeg, altitudeFt: 3000, speedKt: 180))
        _ = sim.issue(IssuedCommand(callsign: callsign, command: .approach(runway: "27")))
        sim.run(seconds: 60)
        XCTAssertFalse(sim.radioLog.contains { $0.text.contains("above the glidepath") })
    }
}

final class RadioTagTests: XCTestCase {
    func testClosedRunwayRefusalIsTaggedWithCallsign() throws {
        // Wind 270 at 8 kt: runway 09 has an 8 kt tailwind, over the 5 kt limit, so it is closed.
        let sim = Simulation(seed: 1, airport: try TestSupport.airport("kbos"), initialWind: Wind(fromDeg: 270, speedKt: 8), windDrifts: false)
        sim.spawnTest(TestSpawn(callsign: "TST1", typeCode: nil, eastNM: 10, northNM: 0, headingDeg: 270, altitudeFt: 4000, speedKt: 200))
        guard case .refused = sim.issue(IssuedCommand(callsign: "TST1", command: .approach(runway: "09"))) else {
            return XCTFail("expected refusal")
        }
        let refusal = try XCTUnwrap(sim.radioLog.last(where: { $0.tag == .refused }))
        XCTAssertEqual(refusal.callsign, "TST1")
    }

    func testTagSeverity() {
        XCTAssertEqual(RadioTag.mayday.severity, .critical)
        XCTAssertEqual(RadioTag.refused.severity, .warning)
    }
}
