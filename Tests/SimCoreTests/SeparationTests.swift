import XCTest
@testable import SimCore

final class SeparationTests: XCTestCase {
    private func ac(_ cs: String, e: Double, n: Double, hdg: Double, alt: Double, spd: Double = 240) -> Aircraft {
        Aircraft(callsign: cs, eastNM: e, northNM: n, headingDeg: hdg, altitudeFt: alt, speedKt: spd)
    }

    func testFarApartIsNoConflict() {
        XCTAssertTrue(SeparationMonitor.evaluate([ac("A1", e: 0, n: 0, hdg: 90, alt: 5000),
                                                  ac("B1", e: 0, n: 30, hdg: 90, alt: 5000)]).isEmpty)
    }

    func testCloseAtSameLevelIsLoss() {
        let c = SeparationMonitor.evaluate([ac("B1", e: 2, n: 0, hdg: 90, alt: 5000),
                                            ac("A1", e: 0, n: 0, hdg: 90, alt: 5500)])
        XCTAssertEqual(c.count, 1)
        XCTAssertEqual(c[0].kind, .loss)
        XCTAssertEqual(c[0].first, "A1")   // alphabetical identity
        XCTAssertEqual(c[0].id, "A1/B1")
    }

    func testVerticalSeparationPreventsLoss() {
        XCTAssertTrue(SeparationMonitor.evaluate([ac("A1", e: 0, n: 0, hdg: 90, alt: 5000),
                                                  ac("B1", e: 1, n: 0, hdg: 90, alt: 7000)]).isEmpty)
    }

    func testHeadOnConvergencePredictsLoss() {
        // 20 NM apart, closing at 480 kt: lateral minimum is reached in about 127 s, so outside 120 s.
        let outside = SeparationMonitor.evaluate([ac("A1", e: -10, n: 0, hdg: 90, alt: 5000),
                                                  ac("B1", e: 10, n: 0, hdg: 270, alt: 5000)])
        XCTAssertTrue(outside.isEmpty)
        // 14 NM apart: reaches 3 NM after about 82 s.
        let inside = SeparationMonitor.evaluate([ac("A1", e: -7, n: 0, hdg: 90, alt: 5000),
                                                 ac("B1", e: 7, n: 0, hdg: 270, alt: 5000)])
        XCTAssertEqual(inside.first?.kind, .predicted)
        XCTAssertTrue((75...90).contains(inside.first?.secondsToLoss ?? 0))
    }

    func testClimbingThroughTheLevelStillPredicts() {
        var climber = ac("A1", e: -7, n: 0, hdg: 90, alt: 4000)
        climber.targetAltitudeFt = 9000
        let c = SeparationMonitor.evaluate([climber, ac("B1", e: 7, n: 0, hdg: 270, alt: 6000)])
        XCTAssertEqual(c.first?.kind, .predicted)
    }

    func testSimulationLogsOncePerOccurrence() {
        let sim = Simulation(seed: 1)
        sim.spawn(ac("A1", e: 0, n: 0, hdg: 90, alt: 5000))
        sim.spawn(ac("B1", e: 1, n: 0, hdg: 90, alt: 5000))
        sim.run(seconds: 10)
        XCTAssertEqual(sim.lossOfSeparationCount, 1)
        XCTAssertEqual(sim.radioLog.filter { $0.text.contains("LOSS OF SEPARATION") }.count, 1)
        XCTAssertEqual(sim.conflicts.first?.kind, .loss)
    }
}
