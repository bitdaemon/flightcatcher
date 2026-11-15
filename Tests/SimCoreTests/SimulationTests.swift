import XCTest
@testable import SimCore

final class SimulationTests: XCTestCase {
    func testTickAdvancesOneSecond() {
        let sim = Simulation(seed: 1)
        sim.run(seconds: 3600)
        XCTAssertEqual(sim.tickCount, 3600)
        XCTAssertEqual(sim.elapsedSeconds, 3600)
    }

    func testSameSeedGivesIdenticalRun() {
        let a = Simulation(seed: 42)
        let b = Simulation(seed: 42)
        a.run(seconds: 3600)
        b.run(seconds: 3600)
        XCTAssertEqual(a.stateDigest, b.stateDigest)
    }

    func testDifferentSeedGivesDifferentRun() {
        let a = Simulation(seed: 1)
        let b = Simulation(seed: 2)
        a.run(seconds: 600)
        b.run(seconds: 600)
        XCTAssertNotEqual(a.stateDigest, b.stateDigest)
    }

    func testRNGSequenceRepeatsForSameSeed() {
        var r1 = SeededRNG(seed: 7)
        var r2 = SeededRNG(seed: 7)
        for _ in 0..<100 { XCTAssertEqual(r1.next(), r2.next()) }
    }
}
