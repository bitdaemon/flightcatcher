import XCTest
@testable import SimCore

final class CommandBarTests: XCTestCase {
    private func fleet() -> [Aircraft] {
        [Aircraft(callsign: "EIN123", eastNM: 0, northNM: 0, headingDeg: 275, altitudeFt: 7000, speedKt: 220),
         Aircraft(callsign: "RYR45", eastNM: 5, northNM: 0, headingDeg: 275, altitudeFt: 9000, speedKt: 250)]
    }

    func testCallsignFragmentAndCommand() {
        let r = CommandBar.evaluate(input: "ein d50", aircraft: fleet(), selected: nil)
        XCTAssertEqual(r.status, .ready)
        XCTAssertEqual(r.issued, IssuedCommand(callsign: "EIN123", command: .descend(feet: 5000)))
    }

    func testRadioNameMatches() {
        let r = CommandBar.evaluate(input: "sham h270", aircraft: fleet(), selected: nil)
        XCTAssertEqual(r.issued, IssuedCommand(callsign: "EIN123", command: .heading(degrees: 270)))
    }

    func testSelectedAircraftAllowsBareCode() {
        let r = CommandBar.evaluate(input: "s180", aircraft: fleet(), selected: "RYR45")
        XCTAssertEqual(r.issued, IssuedCommand(callsign: "RYR45", command: .speed(knots: 180)))
    }

    func testBareCodeWithoutSelectionIsAnError() {
        let r = CommandBar.evaluate(input: "d50", aircraft: fleet(), selected: nil)
        XCTAssertEqual(r.status, .error)
        XCTAssertNil(r.issued)
    }

    func testAmbiguousFragmentNeverExecutes() {
        let two = fleet() + [Aircraft(callsign: "EIN456", eastNM: 0, northNM: 0, headingDeg: 0, altitudeFt: 6000, speedKt: 200)]
        let r = CommandBar.evaluate(input: "ein d50", aircraft: two, selected: nil)
        XCTAssertNotEqual(r.status, .ready)
        XCTAssertNil(r.issued)
        XCTAssertTrue(r.message.contains("Ambiguous"))
    }

    func testRefusesWrongDirectionLevels() {
        XCTAssertEqual(CommandBar.evaluate(input: "ein d90", aircraft: fleet(), selected: nil).status, .error)
        XCTAssertEqual(CommandBar.evaluate(input: "ein c50", aircraft: fleet(), selected: nil).status, .error)
        XCTAssertEqual(CommandBar.evaluate(input: "ein s50", aircraft: fleet(), selected: nil).status, .error)
    }

    func testHeadingZeroMeansThreeSixty() {
        let r = CommandBar.evaluate(input: "ein h0", aircraft: fleet(), selected: nil)
        XCTAssertEqual(r.issued?.command, .heading(degrees: 360))
    }

    func testTabCompletesAndCycles() {
        let two = fleet() + [Aircraft(callsign: "EIN456", eastNM: 0, northNM: 0, headingDeg: 0, altitudeFt: 6000, speedKt: 200)]
        var state = TabState()
        let first = CommandBar.tabComplete(input: "ein", aircraft: two, state: &state)
        XCTAssertEqual(first, "EIN123 ")
        let second = CommandBar.tabComplete(input: first!, aircraft: two, state: &state)
        XCTAssertEqual(second, "EIN456 ")
        let third = CommandBar.tabComplete(input: second!, aircraft: two, state: &state)
        XCTAssertEqual(third, "EIN123 ")
    }

    func testTabKeepsTheCodeTypedAfterTheFragment() {
        var state = TabState()
        let out = CommandBar.tabComplete(input: "ein d50", aircraft: fleet(), state: &state)
        XCTAssertEqual(out, "EIN123 d50")
    }

    func testTabOnLoneCodeDoesNothing() {
        var state = TabState()
        XCTAssertNil(CommandBar.tabComplete(input: "d50", aircraft: fleet(), state: &state))
    }
}

final class SelectionTests: XCTestCase {
    private func fleet() -> [Aircraft] {
        [Aircraft(callsign: "EIN123", eastNM: 0, northNM: 0, headingDeg: 275, altitudeFt: 7000, speedKt: 220),
         Aircraft(callsign: "EIN456", eastNM: 0, northNM: 0, headingDeg: 275, altitudeFt: 8000, speedKt: 240),
         Aircraft(callsign: "RYR45", eastNM: 5, northNM: 0, headingDeg: 275, altitudeFt: 9000, speedKt: 250)]
    }

    func testUniqueFragmentSelectsOnEnter() {
        let r = CommandBar.evaluate(input: "ryr", aircraft: fleet(), selected: nil)
        XCTAssertEqual(r.selects, "RYR45")
        XCTAssertNil(r.issued)
    }

    func testAmbiguousFragmentDoesNotSelect() {
        let r = CommandBar.evaluate(input: "ein", aircraft: fleet(), selected: nil)
        XCTAssertNil(r.selects)
    }

    func testFragmentWithCodeDoesNotJustSelect() {
        let r = CommandBar.evaluate(input: "ryr d50", aircraft: fleet(), selected: nil)
        XCTAssertNil(r.selects)
        XCTAssertNotNil(r.issued)
    }

    func testExactCallsignBeatsLongerMatches() {
        let more = fleet() + [Aircraft(callsign: "EIN1234", eastNM: 0, northNM: 0, headingDeg: 0, altitudeFt: 6000, speedKt: 200)]
        let r = CommandBar.evaluate(input: "ein123", aircraft: more, selected: nil)
        XCTAssertEqual(r.selects, "EIN123")
    }

    func testChainedCommandsAreAllIssuedInOrder() {
        let r = CommandBar.evaluate(input: "ein123 d50 s180 h270l", aircraft: fleet(), selected: nil)
        XCTAssertEqual(r.status, .ready)
        XCTAssertEqual(r.issuedAll.map(\.command),
                       [.descend(feet: 5000), .speed(knots: 180), .heading(degrees: 270, turn: .left)])
        XCTAssertEqual(r.issued, r.issuedAll.first)
    }

    func testChainWithSelectedAircraftAndNoCallsign() {
        let r = CommandBar.evaluate(input: "d50 s180", aircraft: fleet(), selected: "EIN123")
        XCTAssertEqual(r.status, .ready)
        XCTAssertEqual(r.issuedAll.count, 2)
    }

    func testOneBadCodeInChainBlocksTheWholeLine() {
        let r = CommandBar.evaluate(input: "ein123 d50 x9", aircraft: fleet(), selected: nil)
        XCTAssertEqual(r.status, .error)
        XCTAssertTrue(r.issuedAll.isEmpty)
    }

    func testIlsCodeIssuesApproachClearance() {
        let r = CommandBar.evaluate(input: "ein123 i28l", aircraft: fleet(), selected: nil)
        XCTAssertEqual(r.status, .ready)
        XCTAssertEqual(r.issued?.command, .approach(runway: "28L"))
        let r2 = CommandBar.evaluate(input: "i28r", aircraft: fleet(), selected: "EIN123")
        XCTAssertEqual(r2.issued?.command, .approach(runway: "28R"))
    }

    func testIlsCanFollowHeadingInChain() {
        let r = CommandBar.evaluate(input: "ein123 h270 i28l", aircraft: fleet(), selected: nil)
        XCTAssertEqual(r.issuedAll.map(\.command), [.heading(degrees: 270), .approach(runway: "28L")])
    }

    func testBadRunwayIsAnError() {
        XCTAssertEqual(CommandBar.evaluate(input: "ein123 i99", aircraft: fleet(), selected: nil).status, .error)
    }

    func testDirectToKnownFixAttachedOrSeparate() {
        let fixes: Set<String> = ["KERAV", "DW704"]
        let a = CommandBar.evaluate(input: "ein123 pkerav", aircraft: fleet(), selected: nil, knownFixes: fixes)
        XCTAssertEqual(a.status, .ready)
        XCTAssertEqual(a.issued?.command, .direct(fix: "KERAV"))
        let b = CommandBar.evaluate(input: "ein123 p dw704 s180", aircraft: fleet(), selected: nil, knownFixes: fixes)
        XCTAssertEqual(b.issuedAll.map(\.command), [.direct(fix: "DW704"), .speed(knots: 180)])
        let c = CommandBar.evaluate(input: "p kerav", aircraft: fleet(), selected: "EIN123", knownFixes: fixes)
        XCTAssertEqual(c.issued?.command, .direct(fix: "KERAV"))
    }

    func testDirectToUnknownFixIsAnError() {
        let r = CommandBar.evaluate(input: "ein123 pxxxxx", aircraft: fleet(), selected: nil, knownFixes: ["KERAV"])
        XCTAssertEqual(r.status, .error)
        XCTAssertTrue(r.message.contains("XXXXX"))
    }

    func testExpediteSuffix() {
        for (input, expected) in [("ein123 d50!", Command.descend(feet: 5000)),
                                  ("ein123 h270l!", .heading(degrees: 270, turn: .left)),
                                  ("ein123 s180!", .speed(knots: 180))] {
            let r = CommandBar.evaluate(input: input, aircraft: fleet(), selected: nil)
            XCTAssertEqual(r.issued, IssuedCommand(callsign: "EIN123", command: .expedite(expected)), input)
        }
    }

    func testExpediteRefusedForApproach() {
        let r = CommandBar.evaluate(input: "ein i28l!", aircraft: fleet(), selected: nil)
        XCTAssertNil(r.issued)
    }
}
