import XCTest
@testable import SimCore

final class CommandHistoryTests: XCTestCase {
    private func sim() -> Simulation {
        let s = Simulation(seed: 3)
        s.spawn(Aircraft(callsign: "EIN1", eastNM: 0, northNM: 0, headingDeg: 90, altitudeFt: 9000, speedKt: 250))
        s.spawn(Aircraft(callsign: "RYR2", eastNM: 20, northNM: 0, headingDeg: 90, altitudeFt: 9000, speedKt: 250))
        return s
    }

    func testRecordsPerAircraftInOrderWithLabels() {
        let s = sim()
        _ = s.issue(IssuedCommand(callsign: "EIN1", command: .descend(feet: 5000)))
        _ = s.issue(IssuedCommand(callsign: "EIN1", command: .expedite(.heading(degrees: 270, turn: .left))))
        _ = s.issue(IssuedCommand(callsign: "RYR2", command: .speed(knots: 180)))
        XCTAssertEqual(s.commandHistory["EIN1"]?.map(\.label), ["ALT 5000", "HDG 270L!"])
        XCTAssertEqual(s.commandHistory["RYR2"]?.map(\.label), ["SPD 180"])
    }

    func testPendingUntilThePilotComplies() {
        let s = sim()
        _ = s.issue(IssuedCommand(callsign: "EIN1", command: .descend(feet: 5000)))
        let record = s.commandHistory["EIN1"]![0]
        XCTAssertTrue(record.isPending(at: s.tickCount))
        s.run(seconds: 10)
        XCTAssertFalse(record.isPending(at: s.tickCount))
    }

    func testRefusedCommandsAreNotRecorded() {
        let s = sim()
        _ = s.issue(IssuedCommand(callsign: "EIN1", command: .descend(feet: 12000))) // above the aircraft
        XCTAssertNil(s.commandHistory["EIN1"])
    }

    func testHistoryIsLimited() {
        let s = sim()
        for i in 0..<(Simulation.historyLimit + 5) {
            _ = s.issue(IssuedCommand(callsign: "EIN1", command: .heading(degrees: 10 + i)))
        }
        let list = s.commandHistory["EIN1"]!
        XCTAssertEqual(list.count, Simulation.historyLimit)
        XCTAssertEqual(list.last?.label, "HDG \(Phraseology.pad3(10 + Simulation.historyLimit + 4))")
    }
}
