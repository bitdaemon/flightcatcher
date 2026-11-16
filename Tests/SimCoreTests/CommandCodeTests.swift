import XCTest
@testable import SimCore

final class CommandCodeTests: XCTestCase {
    func testCodes() {
        XCTAssertEqual(Command.descend(feet: 7000).code, "d70")
        XCTAssertEqual(Command.climb(feet: 12000).code, "c120")
        XCTAssertEqual(Command.heading(degrees: 270, turn: .left).code, "h270l")
        XCTAssertEqual(Command.heading(degrees: 90).code, "h090")
        XCTAssertEqual(Command.expedite(.descend(feet: 5000)).code, "d50!")
        XCTAssertEqual(Command.route(fixes: ["KERAV", "PIZSA"]).code, "p kerav pizsa")
        XCTAssertEqual(Command.joinApproach(procedure: "R27.AYBEE", runway: "27", via: "AYBEE").code, "j r27.aybee")
        XCTAssertEqual(Command.chainCode(callsign: "AAL123", commands: [.descend(feet: 7000), .speed(knots: 180)]),
                       "aal123 d70 s180")
    }

    /// What the radio shows must be something the command bar accepts and turns back into the same instruction.
    func testCodesParseBackToTheSameCommands() throws {
        let fixes: Set<String> = ["KERAV", "PIZSA"]
        let commands: [Command] = [
            .descend(feet: 7000), .climb(feet: 12000), .heading(degrees: 270, turn: .left), .heading(degrees: 90),
            .speed(knots: 180), .approach(runway: "28L"), .direct(fix: "KERAV"), .route(fixes: ["KERAV", "PIZSA"]),
            .cross(fix: "KERAV", altitudeFt: 5000), .expedite(.climb(feet: 9000)), .maintain, .resumeNavigation,
            .lineUp, .takeoff, .handoff,
        ]
        for command in commands {
            XCTAssertEqual(try CommandBar.parseChain(command.code, knownFixes: fixes).get(), [command], command.code)
        }
    }

    func testChainIsWrittenOnceOnItsFirstCall() {
        let s = Simulation(seed: 1)
        s.spawn(Aircraft(callsign: "AAL123", eastNM: 10, northNM: 0, headingDeg: 270, altitudeFt: 9000, speedKt: 250))
        let before = s.radioLog.last?.id ?? -1
        _ = s.issue(IssuedCommand(callsign: "AAL123", command: .descend(feet: 7000)))
        _ = s.issue(IssuedCommand(callsign: "AAL123", command: .speed(knots: 220)))
        s.labelChain(callsign: "AAL123", afterMessageID: before, code: "aal123 d70 s220")
        let calls = s.radioLog.filter { $0.speaker == .controller }
        XCTAssertEqual(calls.count, 2)
        XCTAssertEqual(calls[0].code, "aal123 d70 s220")
        XCTAssertNil(calls[1].code)
    }

    func testSingleInstructionCarriesItsOwnCode() {
        let s = Simulation(seed: 1)
        s.spawn(Aircraft(callsign: "AAL123", eastNM: 10, northNM: 0, headingDeg: 270, altitudeFt: 9000, speedKt: 250))
        _ = s.issue(IssuedCommand(callsign: "AAL123", command: .heading(degrees: 180, turn: .right)))
        XCTAssertEqual(s.radioLog.first { $0.speaker == .controller }?.code, "aal123 h180r")
    }
}
