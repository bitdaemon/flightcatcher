import XCTest
@testable import SimCore

final class AirportPackageTests: XCTestCase {
    /// Packages converted from FAA CIFP by Tools/cifp_to_package.py must decode and be self-consistent.
    func testBundledFaaAirportsLoadAndValidate() throws {
        for name in ["kbos", "kjfk", "klax"] {
            let pkg = try AirportPackage.loadBundled(name)
            XCTAssertEqual(pkg.icao, name.uppercased())
            XCTAssertFalse(pkg.procedures.isEmpty, name)
            XCTAssertTrue(pkg.validate().isEmpty, "\(name): \(pkg.validate().prefix(5))")
        }
    }

    func testEveryBundledAirportDecodesAndValidates() throws {
        let names = AirportPackage.bundledNames()
        XCTAssertGreaterThan(names.count, 100)
        for name in names {
            let pkg = try AirportPackage.loadBundled(name)
            XCTAssertEqual(pkg.icao, name.uppercased())
            XCTAssertTrue(pkg.validate().isEmpty, "\(name): \(pkg.validate().prefix(3))")
            // SIDs and STARs are optional (radar vectors); every airport needs an ILS or RNAV approach.
            XCTAssertFalse(pkg.procedures.filter { $0.kind == .approach }.isEmpty, "\(name) has no approach")
            XCTAssertNotNil(pkg.city, "\(name) has no city")
        }
    }

    func testAirportIndexMatchesPackagesAndSearches() throws {
        let index = AirportIndex.loadBundled()
        XCTAssertEqual(Set(index.map { $0.icao.lowercased() }), Set(AirportPackage.bundledNames()))
        let boston = try XCTUnwrap(index.first { $0.icao == "KBOS" })
        XCTAssertTrue(boston.matches("bos"))
        XCTAssertTrue(boston.matches("kbos"))
        XCTAssertFalse(boston.matches("denver"))
    }

    func testBundledNamesListsAllAirports() {
        let names = AirportPackage.bundledNames()
        for expected in ["kbos", "kjfk", "klax"] {
            XCTAssertTrue(names.contains(expected), expected)
        }
        XCTAssertFalse(names.contains("airports-index"))
    }

    func testValidationCatchesBadReferences() {
        let pkg = AirportPackage(
            schemaVersion: 1, icao: "TEST", name: "Test", dataSource: "test",
            transitionAltitudeFt: 5000,
            runways: [],
            fixes: [Fix(id: "AAA", lat: 0, lon: 0), Fix(id: "AAA", lat: 1, lon: 1)],
            procedures: [Procedure(id: "P1", kind: .star, runways: ["28L"],
                                   legs: [Leg(fixId: "ZZZ", altitude: nil, maxSpeedKt: nil)])],
            holds: [Hold(fixId: "QQQ", inboundMagneticDeg: 278, turn: .left, maxSpeedKt: 220,
                         minAltitudeFt: 3000, maxLevelFt: 10000, outboundMinutes: 1)]
        )
        let problems = pkg.validate()
        XCTAssertTrue(problems.contains("duplicate fix AAA"))
        XCTAssertTrue(problems.contains("procedure P1 references unknown runway 28L"))
        XCTAssertTrue(problems.contains("procedure P1 references unknown fix ZZZ"))
        XCTAssertTrue(problems.contains("hold references unknown fix QQQ"))
    }
}
