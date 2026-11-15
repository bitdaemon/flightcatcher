import XCTest
@testable import SimCore

final class EventTests: XCTestCase {
    func testDefaultsAreOff() {
        let s = Simulation(seed: 1)
        XCTAssertEqual(s.events, EventSettings())
    }

    func testEventsOnlyPlannedWhenEnabled() throws {
        let airport = try AirportPackage.loadBundled("kbos")
        let star = try XCTUnwrap(airport.procedures.first { $0.kind == .star && $0.legs.count >= 2 })
        let off = Simulation(seed: 5, airport: airport)
        off.spawn(callsign: "TST1", procedure: star.id, altitudeFt: 9000, speedKt: 250)
        XCTAssertNil(off.aircraft.last?.plannedEvent)

        let on = Simulation(seed: 5, airport: airport)
        on.events = EventSettings(emergencyPercent: 100)
        on.spawn(callsign: "TST2", procedure: star.id, altitudeFt: 9000, speedKt: 250)
        guard case .emergency = on.aircraft.last?.plannedEvent else { return XCTFail("expected an emergency plan") }
    }

    func testEmergencyIsDeclaredOnTime() throws {
        let airport = try AirportPackage.loadBundled("kbos")
        let star = try XCTUnwrap(airport.procedures.first { $0.kind == .star && $0.legs.count >= 2 })
        let s = Simulation(seed: 7, airport: airport, initialWind: .calm, windDrifts: false)
        s.events = EventSettings(emergencyPercent: 100)
        s.spawn(callsign: "TST3", procedure: star.id, altitudeFt: 9000, speedKt: 250)
        for _ in 0..<320 { s.tick() }
        XCTAssertNotNil(s.aircraft.first { $0.callsign == "TST3" }?.emergency)
        XCTAssertTrue(s.radioLog.contains { $0.speaker == .pilot && $0.callsign == "TST3" && ($0.text.hasPrefix("MAYDAY") || $0.text.hasPrefix("PAN PAN")) })
    }

    func testEveryEmergencyHasWordsAndAnUrgency() {
        XCTAssertGreaterThanOrEqual(EmergencyKind.allCases.count, 8)
        for kind in EmergencyKind.allCases {
            XCTAssertFalse(kind.phrase.isEmpty, "\(kind)")
            XCTAssertFalse(kind.request.isEmpty, "\(kind)")
            XCTAssertTrue(["MAYDAY", "PAN PAN"].contains(kind.urgencyWord), "\(kind)")
        }
        XCTAssertEqual(EmergencyKind.engineFailure.urgencyWord, "MAYDAY")
        XCTAssertEqual(EmergencyKind.medical.urgencyWord, "PAN PAN")
        XCTAssertEqual(Set(EmergencyKind.allCases.map(\.phrase)).count, EmergencyKind.allCases.count)
    }
}
