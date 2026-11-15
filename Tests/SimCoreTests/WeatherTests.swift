import XCTest
@testable import SimCore

final class WeatherTests: XCTestCase {
    private func boston() throws -> AirportPackage { try TestSupport.airport("kbos") }

    func testWindComponents() {
        let w = Wind(fromDeg: 270, speedKt: 10)
        XCTAssertEqual(w.components(runwayBearingDeg: 270).head, 10, accuracy: 0.001)
        XCTAssertEqual(w.components(runwayBearingDeg: 270).cross, 0, accuracy: 0.001)
        XCTAssertEqual(w.components(runwayBearingDeg: 90).head, -10, accuracy: 0.001)   // tailwind
        XCTAssertEqual(w.components(runwayBearingDeg: 180).cross, 10, accuracy: 0.001)
    }

    func testWindText() {
        XCTAssertEqual(Wind(fromDeg: 270, speedKt: 12).text, "270/12")
        XCTAssertEqual(Wind(fromDeg: 5, speedKt: 8).text, "005/08")
        XCTAssertEqual(Wind.calm.text, "calm")
    }

    func testWindBlowsAircraftDownwind() {
        // Heading north at 100 kt, surface wind from the west at 20 kt: one hour later it is 20 NM east of track.
        var ac = Aircraft(callsign: "TST1", eastNM: 0, northNM: 0, headingDeg: 0, altitudeFt: 0, speedKt: 100)
        ac.advance(seconds: 3600, wind: Wind(fromDeg: 270, speedKt: 20))
        XCTAssertEqual(ac.eastNM, 20, accuracy: 0.05)
        XCTAssertEqual(ac.northNM, 100, accuracy: 0.05)
    }

    func testWindIsStrongerAloft() {
        let w = Wind(fromDeg: 270, speedKt: 10)
        XCTAssertEqual(w.vectorKt(atAltitudeFt: 0).east, 10, accuracy: 0.001)
        XCTAssertEqual(w.vectorKt(atAltitudeFt: 30000).east, 30, accuracy: 0.001)
    }

    func testTailwindClosesRunwaysAndRefusesApproach() throws {
        // From 090 degrees onto runway 27 (true bearing about 257): a 15 kt tailwind.
        let sim = Simulation(seed: 1, airport: try boston(), initialWind: Wind(fromDeg: 90, speedKt: 15), windDrifts: false)
        XCTAssertFalse(sim.openRunways.contains("27"))
        XCTAssertTrue(sim.openRunways.contains("09"))
        sim.spawn(callsign: "TST1", procedure: "ROBUC3.JFK.RW27", startIndex: 1, altitudeFt: 8000, speedKt: 220)
        let result = sim.issue(IssuedCommand(callsign: "TST1", command: .approach(runway: "27")))
        guard case .refused(let reason) = result else { return XCTFail("should be refused") }
        XCTAssertTrue(reason.contains("closed"), reason)
        XCTAssertTrue(sim.radioLog.contains { $0.text.contains("Unable") })
        let join = sim.issue(IssuedCommand(callsign: "TST1",
                                           command: .joinApproach(procedure: "I27", runway: "27", via: "AYBEE")))
        guard case .refused(let joinReason) = join else { return XCTFail("join should be refused too") }
        XCTAssertTrue(joinReason.contains("closed"), joinReason)
    }

    func testOnlyTheRunwayFacingTheWindIsInUse() throws {
        let west = Simulation(seed: 1, airport: try boston(), initialWind: Wind(fromDeg: 270, speedKt: 12), windDrifts: false)
        XCTAssertTrue(west.openRunways.isSuperset(of: ["27", "22L", "22R", "32", "33L", "33R"]))
        XCTAssertEqual(west.closedReason(runway: "09"), "tailwind 12 kt")
        // Both ends usable (a 4 kt tailwind is inside the limit): the one facing the wind is in use.
        XCTAssertEqual(west.closedReason(runway: "04L"), "runway 22R in use")
        let east = Simulation(seed: 1, airport: try boston(), initialWind: Wind(fromDeg: 90, speedKt: 15), windDrifts: false)
        XCTAssertTrue(east.openRunways.contains("09"))
        XCTAssertFalse(east.openRunways.contains("27"))
        let calm = Simulation(seed: 1, airport: try boston(), initialWind: .calm, windDrifts: false)
        XCTAssertTrue(calm.openRunways.isSuperset(of: ["04L", "04R", "09"]))
        XCTAssertFalse(calm.openRunways.contains("22L"))
        XCTAssertFalse(calm.openRunways.contains("27"))
    }

    func testTailwindLimitIsFiveKnots() throws {
        // A 15 kt wind from 090 is a tailwind of about 15 kt on runway 27, so it closes and 09 is in use.
        let sim = Simulation(seed: 1, airport: try boston(), initialWind: Wind(fromDeg: 90, speedKt: 15), windDrifts: false)
        XCTAssertEqual(sim.closedReason(runway: "27"), "tailwind 15 kt")
    }

    func testProceduresFollowTheirRunways() throws {
        let closed = Simulation(seed: 1, airport: try boston(), initialWind: Wind(fromDeg: 90, speedKt: 15), windDrifts: false)
        let open = Simulation(seed: 1, airport: try boston(), initialWind: Wind(fromDeg: 270, speedKt: 15), windDrifts: false)
        let star = try XCTUnwrap(open.airport?.procedures.first { $0.id == "ROBUC3.JFK.RW27" })
        XCTAssertTrue(open.isAvailable(star))
        XCTAssertFalse(closed.isAvailable(star))
    }

    func testHeadwindKeepsApproachAvailable() throws {
        let sim = Simulation(seed: 1, airport: try boston(), initialWind: Wind(fromDeg: 280, speedKt: 12), windDrifts: false)
        XCTAssertTrue(sim.openRunways.contains("27"))
        XCTAssertFalse(sim.openRunways.contains("09"))
        sim.spawn(callsign: "TST1", procedure: "ROBUC3.JFK.RW27", startIndex: 1, altitudeFt: 8000, speedKt: 220)
        if case .refused(let reason) = sim.issue(IssuedCommand(callsign: "TST1", command: .approach(runway: "27"))) {
            XCTFail(reason)
        }
    }

    func testStrongCrosswindClosesARunway() throws {
        // From 170 degrees at 35 kt: about 35 kt across runway 09/27, while 22 faces the wind.
        let sim = Simulation(seed: 1, airport: try boston(), initialWind: Wind(fromDeg: 170, speedKt: 35), windDrifts: false)
        XCTAssertFalse(sim.openRunways.contains("09"))
        XCTAssertTrue(sim.openRunways.contains("22L"))
        XCTAssertTrue(sim.runwayStatuses.contains { $0.reason.contains("crosswind") })
    }

    func testRandomStartIsPlayableAndDriftNeverClosesEverything() throws {
        for seed in [1, 2, 3, 7, 42] as [UInt64] {
            let sim = Simulation(seed: seed, airport: try boston())
            XCTAssertFalse(sim.openRunways.isEmpty, "seed \(seed) start")
            for _ in 0..<(3 * 3600) {
                sim.tick()
                if sim.tickCount % 60 == 0 {
                    XCTAssertFalse(sim.openRunways.isEmpty, "seed \(seed) at \(sim.tickCount)")
                }
            }
        }
    }

    func testWeatherIsDeterministic() throws {
        let a = Simulation(seed: 11, airport: try boston())
        let b = Simulation(seed: 11, airport: try boston())
        a.run(seconds: 1800)
        b.run(seconds: 1800)
        XCTAssertEqual(a.wind, b.wind)
        XCTAssertEqual(a.stateDigest, b.stateDigest)
    }

    func testNoAirportMeansNoWind() {
        let sim = Simulation(seed: 1)
        sim.run(seconds: 600)
        XCTAssertEqual(sim.wind, .calm)
    }
}
