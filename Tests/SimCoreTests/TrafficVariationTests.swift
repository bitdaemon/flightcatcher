import XCTest
@testable import SimCore

/// Arrival and departure rates that wander inside a low-high range.
final class TrafficVariationTests: XCTestCase {
    /// Traffic switched on but nothing can be generated (IFR off), so only the rates move. No airport needed.
    private func sim(_ variation: TrafficVariation, seed: UInt64 = 7) -> Simulation {
        let s = Simulation(seed: seed)
        s.traffic = TrafficSettings(enabled: true, arrivalsPerHour: 5, departuresPerHour: 2, ifr: false,
                                    arrivalsMaxPerHour: 30, departuresMaxPerHour: 12, variation: variation)
        return s
    }

    /// Samples once a minute: (arrival rate, departure rate, arrival target).
    private func samples(_ s: Simulation, minutes: Int) -> [(Double, Double, Double)] {
        (0..<minutes).map { _ in
            s.run(seconds: 60)
            return (s.arrivalRatePerHour, s.departureRatePerHour, s.arrivalTargetPerHour)
        }
    }

    func testFixedRangeKeepsTheOldFixedRate() {
        let s = Simulation(seed: 1)
        s.traffic = TrafficSettings(enabled: true, arrivalsPerHour: 20, departuresPerHour: 6, ifr: false)
        XCTAssertFalse(s.traffic.isVariable)
        for (a, d, _) in samples(s, minutes: 30) {
            XCTAssertEqual(a, 20)
            XCTAssertEqual(d, 6)
        }
    }

    func testRatesStayInsideTheirRangesAndActuallyMove() {
        let s = sim(.lively)
        let all = samples(s, minutes: 180)
        for (a, d, _) in all {
            XCTAssertTrue((5...30).contains(a), "arrivals \(a)")
            XCTAssertTrue((2...12).contains(d), "departures \(d)")
        }
        let arrivals = all.map(\.0)
        XCTAssertGreaterThan(arrivals.max()! - arrivals.min()!, 5, "a lively range should be used")
    }

    func testLivelyChangesMoreOftenThanSteady() {
        func targetChanges(_ v: TrafficVariation) -> Int {
            let targets = samples(sim(v), minutes: 180).map(\.2)
            return zip(targets, targets.dropFirst()).filter { abs($0 - $1) > 0.001 }.count
        }
        let steady = targetChanges(.steady), lively = targetChanges(.lively)
        XCTAssertLessThanOrEqual(steady, 10, "steady: a new target every 20 to 30 minutes")
        XCTAssertGreaterThanOrEqual(lively, 20, "lively: a new target every 3 to 8 minutes")
    }

    func testSameSeedGivesTheSameRates() {
        let a = samples(sim(.moderate, seed: 11), minutes: 90).map(\.0)
        let b = samples(sim(.moderate, seed: 11), minutes: 90).map(\.0)
        let c = samples(sim(.moderate, seed: 12), minutes: 90).map(\.0)
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }

    func testNarrowingTheRangePullsTheRateInside() {
        let s = sim(.steady)
        s.run(seconds: 600)
        s.traffic.arrivalsPerHour = 10
        s.traffic.arrivalsMaxPerHour = 12
        s.run(seconds: 1)
        XCTAssertTrue((10...12).contains(s.arrivalRatePerHour), "\(s.arrivalRatePerHour)")
        XCTAssertTrue((10...12).contains(s.arrivalTargetPerHour), "\(s.arrivalTargetPerHour)")
    }

    func testRatesText() {
        let s = Simulation(seed: 1)
        XCTAssertEqual(s.trafficRatesText, "")
        s.traffic = TrafficSettings(enabled: true, arrivalsPerHour: 20, departuresPerHour: 6, ifr: false)
        s.run(seconds: 1)
        XCTAssertEqual(s.trafficRatesText, "ARR 20/h  DEP 6/h")
    }

    func testPresetsSetARangeAndVariation() {
        var settings = TrafficSettings(enabled: true, departuresPerHour: 9, fixedSeed: 42)
        TrafficPreset.all.first { $0.name == "Rush" }!.apply(to: &settings)
        XCTAssertEqual(settings.arrivalRange, 30...50)
        XCTAssertEqual(settings.variation, .lively)
        XCTAssertEqual(settings.departureRange, 9...9, "presets leave departures alone")
        XCTAssertEqual(settings.fixedSeed, 42)
    }

    func testOldSettingsLoadAsAFixedRate() throws {
        let old = #"{"enabled":true,"arrivalsPerHour":22,"departuresPerHour":5}"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(TrafficSettings.self, from: old)
        XCTAssertEqual(decoded.arrivalRange, 22...22)
        XCTAssertEqual(decoded.departureRange, 5...5)
        XCTAssertEqual(decoded.variation, .moderate)
        XCTAssertFalse(decoded.isVariable)
    }

    func testSettingsRoundTrip() throws {
        let settings = TrafficSettings(enabled: true, arrivalsPerHour: 4, departuresPerHour: 3,
                                       arrivalsMaxPerHour: 18, departuresMaxPerHour: 9, variation: .steady)
        let back = try JSONDecoder().decode(TrafficSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(back, settings)
    }
}
