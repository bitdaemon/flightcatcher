import XCTest
@testable import SimCore

final class StartTrafficTests: XCTestCase {
    private func sim(seed: UInt64, airport: String = "kbos", trafficSeed: UInt64) throws -> Simulation {
        let s = Simulation(seed: seed, airport: try TestSupport.airport(airport),
                           initialWind: Wind(fromDeg: 270, speedKt: 8), windDrifts: false)
        s.reseedTraffic(trafficSeed)
        return s
    }

    func testCountVariesAndStaysInRange() throws {
        var counts = Set<Int>()
        for t in 1...40 {
            let s = try sim(seed: 1, trafficSeed: UInt64(t))
            let n = s.placeStartTraffic()
            XCTAssertEqual(s.aircraft.count, n)
            XCTAssertLessThanOrEqual(n, 7)
            counts.insert(n)
        }
        XCTAssertGreaterThan(counts.count, 1)
    }

    func testNoConflictAtStartAndNoOverlap() throws {
        for t in 1...60 {
            let s = try sim(seed: 1, trafficSeed: UInt64(t))
            s.placeStartTraffic()
            XCTAssertTrue(SeparationMonitor.evaluate(s.aircraft, wind: s.wind).isEmpty, "traffic seed \(t)")
            XCTAssertEqual(Set(s.aircraft.map(\.callsign)).count, s.aircraft.count)
            for a in s.aircraft { XCTAssertGreaterThanOrEqual(a.altitudeFt, Double(s.levelFloorFt)) }
        }
    }

    func testStartsDifferBetweenSeedsButRepeatForTheSameSeed() throws {
        func positions(_ t: UInt64) throws -> [String] {
            let s = try sim(seed: 1, trafficSeed: t)
            s.placeStartTraffic()
            return s.aircraft.map { "\($0.callsign)@\(Int($0.eastNM * 10)),\(Int($0.northNM * 10)),\(Int($0.altitudeFt))" }
        }
        XCTAssertEqual(try positions(5), try positions(5))
        XCTAssertNotEqual(try positions(5), try positions(6))
    }

    func testNoLossOfSeparationOnTheFirstTick() throws {
        for t in 1...10 {
            let s = try sim(seed: 1, trafficSeed: UInt64(t))
            s.placeStartTraffic()
            s.tick()
            XCTAssertEqual(s.lossOfSeparationCount, 0, "traffic seed \(t)")
        }
    }
}
