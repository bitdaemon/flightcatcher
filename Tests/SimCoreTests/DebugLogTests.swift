import XCTest
@testable import SimCore

final class DebugLogTests: XCTestCase {
    private func run(debug: Bool, seed: UInt64) throws -> (UInt64, Int) {
        let airport = try AirportPackage.loadBundled("kbos")
        let s = Simulation(seed: seed, airport: airport, initialWind: .calm, windDrifts: false)
        s.debugEnabled = debug
        s.traffic = TrafficSettings(enabled: true, arrivalsPerHour: 30, departuresPerHour: 10)
        s.events = EventSettings(pilotGoAroundPercent: 10, windshearPercent: 5, emergencyPercent: 5)
        let callsign = s.spawnTest(TestSpawn(eastNM: 10, northNM: 0, headingDeg: 270, altitudeFt: 5000, speedKt: 220))
        _ = s.issue(IssuedCommand(callsign: callsign, command: .heading(degrees: 180, turn: nil)))
        for _ in 0..<900 { s.tick() }
        return (s.stateDigest, s.debugLog.count)
    }

    func testLoggingDoesNotChangeTheSimulation() throws {
        let off = try run(debug: false, seed: 11)
        let on = try run(debug: true, seed: 11)
        XCTAssertEqual(off.0, on.0)
        XCTAssertEqual(off.1, 0)
        XCTAssertGreaterThan(on.1, 0)
    }

    func testCommandsAndApproachAreLogged() throws {
        let airport = try AirportPackage.loadBundled("kbos")
        let s = Simulation(seed: 3, airport: airport, initialWind: .calm, windDrifts: false)
        s.debugEnabled = true
        let star = try XCTUnwrap(airport.procedures.first { $0.kind == .star && $0.legs.count >= 2 })
        s.spawn(callsign: "TST1", procedure: star.id, altitudeFt: 6000, speedKt: 220)
        let runway = try XCTUnwrap(s.runwayStatuses.first { $0.isOpen }?.id)
        _ = s.issue(IssuedCommand(callsign: "TST1", command: .approach(runway: runway)))
        _ = s.issue(IssuedCommand(callsign: "NOPE", command: .heading(degrees: 90, turn: nil)))
        for _ in 0..<40 { s.tick() }
        let text = s.debugLog.map(\.text).joined(separator: "\n")
        XCTAssertTrue(text.contains("accepted"), text)
        XCTAssertTrue(text.contains("REFUSED"), text)
        XCTAssertTrue(text.contains("applied"), text)
        XCTAssertTrue(text.contains("approach") , text)
    }
}
