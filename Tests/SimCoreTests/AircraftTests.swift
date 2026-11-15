import XCTest
@testable import SimCore

final class AircraftTests: XCTestCase {
    func testLabelFormat() {
        let a = Aircraft(callsign: "EIN123", eastNM: 0, northNM: 0, headingDeg: 275, altitudeFt: 7000, speedKt: 220)
        XCTAssertEqual(a.labelTop, "EIN123")
        XCTAssertEqual(a.labelBottom, "220 070")
        let b = Aircraft(callsign: "RYR1", eastNM: 0, northNM: 0, headingDeg: 0, altitudeFt: 2500, speedKt: 160)
        XCTAssertEqual(b.labelBottom, "160 025")
    }

    func testDueEastAt360KnotsMovesTenthOfANauticalMilePerSecond() {
        let sim = Simulation(seed: 1)
        sim.spawn(Aircraft(callsign: "TEST", eastNM: 0, northNM: 0, headingDeg: 90, altitudeFt: 5000, speedKt: 360))
        sim.run(seconds: 10)
        XCTAssertEqual(sim.aircraft[0].eastNM, 1.0, accuracy: 1e-9)
        XCTAssertEqual(sim.aircraft[0].northNM, 0.0, accuracy: 1e-9)
    }

    func testAircraftStateIsPartOfDeterminism() {
        func run() -> UInt64 {
            let sim = Simulation(seed: 5)
            sim.spawn(Aircraft(callsign: "A", eastNM: 10, northNM: 0, headingDeg: 275, altitudeFt: 7000, speedKt: 220))
            sim.run(seconds: 600)
            return sim.stateDigest
        }
        XCTAssertEqual(run(), run())
    }
}
