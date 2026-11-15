import XCTest
@testable import SimCore

final class CommandFlowTests: XCTestCase {
    private func ein(altitude: Double = 7000, speed: Double = 220, heading: Double = 275) -> Aircraft {
        Aircraft(callsign: "EIN123", eastNM: 0, northNM: 0, headingDeg: heading, altitudeFt: altitude, speedKt: speed)
    }

    func testSpokenForms() {
        XCTAssertEqual(Phraseology.spokenLevel(feet: 7000, transitionAltitudeFt: 5000), "flight level seven zero")
        XCTAssertEqual(Phraseology.spokenLevel(feet: 2500, transitionAltitudeFt: 5000), "two thousand five hundred feet")
        XCTAssertEqual(Phraseology.spokenLevel(feet: 5000, transitionAltitudeFt: 5000), "five thousand feet")
        XCTAssertEqual(Phraseology.spokenLevel(feet: 10000, transitionAltitudeFt: 5000), "flight level one hundred")
        XCTAssertEqual(Phraseology.spokenLevel(feet: 12000, transitionAltitudeFt: 5000), "flight level one two zero")
        XCTAssertEqual(Phraseology.spokenLevel(feet: 800, transitionAltitudeFt: 5000), "eight hundred feet")
        XCTAssertEqual(Phraseology.spokenCallsign(ein()), "Shamrock one two three")
    }

    func testDescendReadbackAndEffect() {
        let sim = Simulation(seed: 1)
        sim.spawn(ein())
        let result = sim.issue(IssuedCommand(callsign: "EIN123", command: .descend(feet: 5000)))
        guard case .accepted(let delay) = result else { return XCTFail("expected accepted") }
        XCTAssertTrue((3...6).contains(delay))
        XCTAssertEqual(sim.radioLog.count, 1)
        XCTAssertEqual(sim.radioLog[0].speaker, .controller)

        sim.run(seconds: 90) // delay plus 2000 ft at 1800 fpm
        XCTAssertEqual(sim.aircraft[0].altitudeFt, 5000, accuracy: 1e-9)
        XCTAssertEqual(sim.radioLog.count, 2)
        XCTAssertEqual(sim.radioLog[1].speaker, .pilot)
        XCTAssertTrue(sim.radioLog[1].text.contains("five thousand feet"))
    }

    func testSpeedPhraseDependsOnDirection() {
        XCTAssertTrue(Phraseology.instruction(.speed(knots: 180), for: ein(), transitionAltitudeFt: 5000).hasPrefix("reduce"))
        XCTAssertTrue(Phraseology.instruction(.speed(knots: 250), for: ein(), transitionAltitudeFt: 5000).hasPrefix("increase"))
    }

    func testIssueRefusesInvalidCommand() {
        let sim = Simulation(seed: 1)
        sim.spawn(ein())
        guard case .refused = sim.issue(IssuedCommand(callsign: "EIN123", command: .climb(feet: 5000))) else {
            return XCTFail("expected refusal")
        }
        XCTAssertTrue(sim.radioLog.isEmpty)
    }

    func testTurnsTheShorterWay() {
        var a = ein(heading: 350)
        a.apply(.heading(degrees: 10))
        a.advance(seconds: 5) // 3 deg/s: 15 degrees to the right
        XCTAssertEqual(a.headingDeg, 5, accuracy: 1e-9)
    }

    func testSameInputsGiveSameRun() {
        func run() -> UInt64 {
            let sim = Simulation(seed: 9)
            sim.spawn(ein())
            _ = sim.issue(IssuedCommand(callsign: "EIN123", command: .heading(degrees: 180)))
            sim.run(seconds: 300)
            return sim.stateDigest
        }
        XCTAssertEqual(run(), run())
    }
}

final class TurnDirectionTests: XCTestCase {
    private func aircraft(heading: Double) -> Aircraft {
        Aircraft(callsign: "EIN123", eastNM: 0, northNM: 0, headingDeg: heading, altitudeFt: 7000, speedKt: 220)
    }

    func testParsesTurnSuffix() {
        let fleet = [aircraft(heading: 90)]
        XCTAssertEqual(CommandBar.evaluate(input: "ein h270l", aircraft: fleet, selected: nil).issued?.command,
                       .heading(degrees: 270, turn: .left))
        XCTAssertEqual(CommandBar.evaluate(input: "ein h270R", aircraft: fleet, selected: nil).issued?.command,
                       .heading(degrees: 270, turn: .right))
        XCTAssertEqual(CommandBar.evaluate(input: "ein h270", aircraft: fleet, selected: nil).issued?.command,
                       .heading(degrees: 270, turn: nil))
        XCTAssertEqual(CommandBar.evaluate(input: "h270l", aircraft: fleet, selected: "EIN123").issued?.command,
                       .heading(degrees: 270, turn: .left))
    }

    func testSuffixOnOtherCodesIsRejected() {
        let fleet = [aircraft(heading: 90)]
        XCTAssertEqual(CommandBar.evaluate(input: "ein d50l", aircraft: fleet, selected: nil).status, .error)
    }

    func testForcedLeftAndRightTurnsTakeOppositeRoutes() {
        var left = aircraft(heading: 90)
        left.apply(.heading(degrees: 270, turn: .left))
        left.advance(seconds: 5)
        XCTAssertEqual(left.headingDeg, 75, accuracy: 1e-9)

        var right = aircraft(heading: 90)
        right.apply(.heading(degrees: 270, turn: .right))
        right.advance(seconds: 5)
        XCTAssertEqual(right.headingDeg, 105, accuracy: 1e-9)
    }

    func testForcedTurnTheLongWayRound() {
        var a = aircraft(heading: 10)
        a.apply(.heading(degrees: 350, turn: .right)) // 340 degrees to the right, not 20 to the left
        a.advance(seconds: 5)
        XCTAssertEqual(a.headingDeg, 25, accuracy: 1e-9)
    }

    func testNoDirectionTakesTheShorterWayAndForcedTurnClearsOnArrival() {
        var shorter = aircraft(heading: 10)
        shorter.apply(.heading(degrees: 350))
        shorter.advance(seconds: 5)
        XCTAssertEqual(shorter.headingDeg, 355, accuracy: 1e-9)

        var forced = aircraft(heading: 350)
        forced.apply(.heading(degrees: 10, turn: .right))
        forced.advance(seconds: 7)
        XCTAssertEqual(forced.headingDeg, 10, accuracy: 1e-9)
        XCTAssertNil(forced.targetTurn)
    }

    func testPhraseology() {
        let a = aircraft(heading: 90)
        XCTAssertEqual(Phraseology.instruction(.heading(degrees: 270, turn: .left), for: a, transitionAltitudeFt: 5000),
                       "turn left heading two seven zero")
        XCTAssertEqual(Phraseology.instruction(.heading(degrees: 270), for: a, transitionAltitudeFt: 5000),
                       "fly heading two seven zero")
    }
}

final class NumberStyleTests: XCTestCase {
    func testIcaoStyleIsAvailableAsASwitch() {
        Phraseology.numberStyle = .icao
        defer { Phraseology.numberStyle = .plain }
        XCTAssertEqual(Phraseology.spokenDigits("3459"), "tree fower fife niner")
        XCTAssertEqual(Phraseology.spokenLevel(feet: 5000, transitionAltitudeFt: 5000), "fife thousand feet")
    }

    func testPlainStyleIsTheDefault() {
        XCTAssertEqual(Phraseology.numberStyle, .plain)
        XCTAssertEqual(Phraseology.spokenDigits("3459"), "three four five niner")
    }
}
