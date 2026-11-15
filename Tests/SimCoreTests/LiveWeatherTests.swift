import XCTest
@testable import SimCore

final class LiveWeatherTests: XCTestCase {
    private func json(_ raw: String) -> Data {
        Data("[{\"icaoId\":\"KBOS\",\"rawOb\":\"\(raw)\"}]".utf8)
    }

    func testParsesWindAndGusts() throws {
        let r = try XCTUnwrap(MetarParser.parse(json: json("METAR KBOS 131850Z AUTO 25012G24KT 9999 FEW030 08/04 Q1012")))
        XCTAssertEqual(r.fromDeg, 250)
        XCTAssertEqual(r.speedKt, 12)
        XCTAssertEqual(r.gustKt, 24)
    }

    func testVariableAndCalmKeepTheDirection() throws {
        XCTAssertNil(try XCTUnwrap(MetarParser.parse(json: json("METAR KBOS 131850Z VRB03KT 9999"))).fromDeg)
        let calm = try XCTUnwrap(MetarParser.parse(json: json("METAR KBOS 131850Z 00000KT 9999")))
        XCTAssertNil(calm.fromDeg)
        XCTAssertEqual(calm.speedKt, 0)
    }

    func testMetresPerSecondAreConverted() throws {
        let r = try XCTUnwrap(MetarParser.parse(json: json("METAR KBOS 131850Z 24006MPS 9999")))
        XCTAssertEqual(r.speedKt, 11.66, accuracy: 0.01)
    }

    func testFallsBackToTheJsonFields() throws {
        let data = Data("[{\"icaoId\":\"KBOS\",\"wdir\":\"VRB\",\"wspd\":4}]".utf8)
        let r = try XCTUnwrap(MetarParser.parse(json: data))
        XCTAssertNil(r.fromDeg)
        XCTAssertEqual(r.speedKt, 4)
        XCTAssertNil(MetarParser.parse(json: Data("[]".utf8)))
        XCTAssertNil(MetarParser.parse(json: Data("not json".utf8)))
    }

    func testGustsDecideWhetherARunwayCloses() throws {
        let airport = try TestSupport.airport("kbos")
        let s = Simulation(seed: 1, airport: airport, initialWind: Wind(fromDeg: 270, speedKt: 12, gustKt: 32), windDrifts: false)
        let closed = s.runwayStatuses.first { !$0.isOpen && $0.reason.contains("crosswind") }
        XCTAssertNotNil(closed)
        XCTAssertTrue(closed?.reason.contains("gusts") == true)
    }

    func testWindTextShowsGusts() {
        XCTAssertEqual(Wind(fromDeg: 270, speedKt: 12).text, "270/12")
        XCTAssertEqual(Wind(fromDeg: 270, speedKt: 12, gustKt: 22).text, "270/12G22")
        XCTAssertEqual(Wind(fromDeg: 270, speedKt: 12, gustKt: 5).gustKt, 12)
    }

    func testLiveWindEasesTowardTheObservation() throws {
        let airport = try TestSupport.airport("kbos")
        let s = Simulation(seed: 1, airport: airport, initialWind: Wind(fromDeg: 90, speedKt: 8), windDrifts: false)
        s.weatherMode = .live
        s.setLiveWeather(WeatherReport(icao: "KBOS", fromDeg: 270, speedKt: 14, gustKt: 24))
        s.run(seconds: 60)
        XCTAssertLessThanOrEqual(abs(Aircraft.signedTurn(from: 90, to: s.wind.fromDeg)), 10.001)
        s.run(seconds: 60 * 30)
        XCTAssertEqual(s.wind.fromDeg, 270, accuracy: 0.01)
        XCTAssertEqual(s.wind.speedKt, 14, accuracy: 0.01)
        XCTAssertEqual(s.wind.gustKt, 24, accuracy: 0.01)
    }

    func testImmediateAdoptionAndFixedMode() throws {
        let airport = try TestSupport.airport("kbos")
        let s = Simulation(seed: 1, airport: airport, initialWind: Wind(fromDeg: 90, speedKt: 8), windDrifts: false)
        s.weatherMode = .live
        s.setLiveWeather(WeatherReport(icao: "KBOS", fromDeg: 270, speedKt: 10), immediately: true)
        XCTAssertEqual(s.wind.fromDeg, 270, accuracy: 0.01)
        s.weatherMode = .fixed
        s.setLiveWeather(WeatherReport(icao: "KBOS", fromDeg: 100, speedKt: 10))
        s.run(seconds: 600)
        XCTAssertEqual(s.wind.fromDeg, 270, accuracy: 0.01)
    }
}
