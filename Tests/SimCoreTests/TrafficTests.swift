import XCTest
@testable import SimCore

final class TrafficTests: XCTestCase {
    private func sim(seed: UInt64 = 1) throws -> Simulation {
        let airport = try TestSupport.airport("kbos")
        return Simulation(seed: seed, transitionAltitudeFt: airport.transitionAltitudeFt, airport: airport,
                          initialWind: .calm, windDrifts: false)
    }

    func testCatalogIsConsistent() {
        XCTAssertEqual(Set(AircraftCatalog.all.map(\.code)).count, AircraftCatalog.all.count)
        for type in AircraftCatalog.all {
            XCTAssertLessThan(type.minSpeedKt, type.maxSpeedKt, type.code)
            XCTAssertTrue(Double(type.minSpeedKt) <= type.approachSpeedKt + 20, type.code)
            XCTAssertGreaterThan(type.share, 0, type.code)
        }
        for category in AircraftCategory.allCases { XCTAssertFalse(AircraftCatalog.types(in: category).isEmpty) }
    }

    func testTypeLimitsCommands() {
        var cessna = Aircraft(callsign: "EIABC", eastNM: 0, northNM: 0, headingDeg: 0, altitudeFt: 4000, speedKt: 90)
        cessna.applyType(AircraftCatalog.type(code: "C172")!)
        XCTAssertNotNil(Command.speed(knots: 250).refusal(for: cessna))
        XCTAssertNotNil(Command.climb(feet: 30000).refusal(for: cessna))
        XCTAssertNil(Command.speed(knots: 100).refusal(for: cessna))
        var jet = Aircraft(callsign: "RYR1", eastNM: 0, northNM: 0, headingDeg: 0, altitudeFt: 9000, speedKt: 250)
        jet.applyType(AircraftCatalog.type(code: "A320")!)
        XCTAssertNil(Command.speed(knots: 250).refusal(for: jet))
        XCTAssertEqual(jet.climbRateFpm, 2400)
    }

    func testSpawnerCreatesPlausibleArrivals() throws {
        let s = try sim()
        s.traffic = TrafficSettings(enabled: true, arrivalsPerHour: 60)
        s.run(seconds: 1800)
        XCTAssertTrue((12...50).contains(s.aircraft.count), "spawned \(s.aircraft.count)")
        XCTAssertEqual(Set(s.aircraft.map(\.callsign)).count, s.aircraft.count)
        for ac in s.aircraft where !ac.isOnGround {
            XCTAssertNotNil(ac.type)
            XCTAssertTrue(ac.speedKt >= Double(ac.type!.minSpeedKt) - 0.5 && ac.speedKt <= Double(ac.type!.maxSpeedKt) + 0.5)
        }
    }

    func testSameSeedGivesSameTraffic() throws {
        func run() throws -> [String] {
            let s = try sim(seed: 7)
            s.traffic = TrafficSettings(enabled: true, arrivalsPerHour: 40)
            s.run(seconds: 1200)
            return s.aircraft.map { "\($0.callsign) \($0.typeCode ?? "")" }
        }
        XCTAssertEqual(try run(), try run())
        let a = try sim(seed: 7), b = try sim(seed: 7)
        a.traffic = TrafficSettings(enabled: true, arrivalsPerHour: 40)
        b.traffic = TrafficSettings(enabled: true, arrivalsPerHour: 40)
        b.reseedTraffic(99)
        a.run(seconds: 1200); b.run(seconds: 1200)
        XCTAssertNotEqual(a.aircraft.map(\.callsign), b.aircraft.map(\.callsign))
    }

    func testCategoryAndTypeFilters() throws {
        let s = try sim()
        s.traffic = TrafficSettings(enabled: true, arrivalsPerHour: 60, enabledCategories: [.heavy], disabledTypes: ["A388"])
        s.run(seconds: 1800)
        XCTAssertFalse(s.aircraft.isEmpty)
        for ac in s.aircraft {
            XCTAssertEqual(ac.type?.category, .heavy)
            XCTAssertNotEqual(ac.typeCode, "A388")
        }
    }

    func testIfrOffSpawnsNothingAndOffByDefault() throws {
        let s = try sim()
        s.run(seconds: 600)
        XCTAssertTrue(s.aircraft.isEmpty)
        s.traffic = TrafficSettings(enabled: true, arrivalsPerHour: 60, ifr: false)
        s.run(seconds: 600)
        XCTAssertTrue(s.aircraft.isEmpty)
    }

    func testPresetKeepsSwitchAndSeed() {
        var settings = TrafficSettings(enabled: true, arrivalsPerHour: 5, fixedSeed: 42)
        TrafficPreset.all.first { $0.name == "Heavy mix" }!.apply(to: &settings)
        XCTAssertTrue(settings.enabled)
        XCTAssertEqual(settings.fixedSeed, 42)
        XCTAssertEqual(settings.enabledCategories, [.heavy, .narrowbody])
    }
}

final class TrafficSettingsTests: XCTestCase {
    func testVfrIsOffByDefaultAndOldSettingsStillLoad() throws {
        XCTAssertFalse(TrafficSettings().vfr)
        let old = #"{"enabled":true,"arrivalsPerHour":22,"ifr":true,"enabledCategories":["heavy"],"disabledTypes":[]}"#
        let decoded = try JSONDecoder().decode(TrafficSettings.self, from: Data(old.utf8))
        XCTAssertFalse(decoded.vfr)
        XCTAssertEqual(decoded.arrivalsPerHour, 22)
        XCTAssertEqual(decoded.enabledCategories, [.heavy])
    }

    func testCallsignsFollowAirportCountry() {
        func sample(_ code: String, country: String?, count: Int = 400) -> [String] {
            var rng = SeededRNG(seed: 11)
            var taken = Set<String>()
            let type = AircraftCatalog.type(code: code)!
            return (0..<count).map { _ in
                let c = TrafficPlanner.callsign(for: type, country: country, rng: &rng, taken: taken)
                taken.insert(c)
                return c
            }
        }
        func designators(_ list: [String]) -> Set<String> { Set(list.map { String($0.prefix(3)) }) }

        // US narrowbodies: US carriers, never Ryanair or easyJet.
        let usNarrow = designators(sample("A320", country: "US"))
        XCTAssertTrue(usNarrow.isSuperset(of: ["AAL", "DAL", "UAL", "SWA"]))
        XCTAssertFalse(usNarrow.contains("RYR") || usNarrow.contains("EZY") || usNarrow.contains("VLG"))
        // US heavies include foreign long-haul carriers.
        let usHeavy = designators(sample("B77W", country: "US"))
        XCTAssertTrue(usHeavy.isSuperset(of: ["BAW", "DLH", "UAE", "AAL", "FDX"]))
        // US regionals are SkyWest-style, flight numbers 3000 and up.
        let usRegional = sample("E190", country: "US")
        XCTAssertTrue(usRegional.allSatisfy { Int($0.dropFirst(3))! >= 3000 })
        XCTAssertTrue(designators(usRegional).contains("SKW"))
        // An Irish airport keeps Ryanair and Aer Lingus and sees US carriers on heavies only.
        let ieNarrow = designators(sample("A320", country: "IE"))
        XCTAssertTrue(ieNarrow.isSuperset(of: ["RYR", "EIN"]))
        XCTAssertFalse(ieNarrow.contains("SWA"))
        XCTAssertTrue(designators(sample("B788", country: "IE")).contains("AAL"))
        // Light aircraft: N-numbers in the US, EI- in Ireland; no I or O; at most six characters.
        for tail in sample("C172", country: "US") {
            XCTAssertTrue(tail.hasPrefix("N") && tail.count <= 6 && !tail.dropFirst().contains("I") && !tail.dropFirst().contains("O"), tail)
            XCTAssertNotEqual(tail.dropFirst().first, "0", tail)
        }
        XCTAssertTrue(sample("C172", country: "IE").allSatisfy { $0.hasPrefix("EI") && $0.count == 5 })
    }

    func testEveryAirlineHasARadioNameAndUniqueDesignator() {
        let codes = AirlineTable.all.map(\.code)
        XCTAssertEqual(Set(codes).count, codes.count)
        for airline in AirlineTable.all {
            XCTAssertEqual(airline.code.count, 3)
            XCTAssertEqual(RadioNames.table[airline.code], airline.radio)
        }
    }
}
