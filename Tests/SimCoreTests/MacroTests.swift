import XCTest
@testable import SimCore

final class MacroCompilerTests: XCTestCase {
    private let fixes: Set<String> = ["CAPE", "KERAV"]

    private func compile(_ text: String, phase: MacroPhase = .arrival, name: String = "APPR") -> Result<CompiledMacro, MacroError> {
        MacroCompiler.compile(Macro(name: name, phase: phase, text: text), knownFixes: fixes)
    }

    func testStepsTriggersAndGrouping() throws {
        let m = try compile("s210\nat cape: d30, s180; when alt<40: i4r\nwhen spd <= 180: h270l").get()
        XCTAssertEqual(m.steps.count, 4)
        XCTAssertNil(m.steps[0].trigger)
        XCTAssertEqual(m.steps[0].commands, [.speed(knots: 210)])
        XCTAssertEqual(m.steps[1].trigger, .atFix("CAPE"))
        XCTAssertEqual(m.steps[1].commands, [.descend(feet: 3000), .speed(knots: 180)])
        XCTAssertEqual(m.steps[2].trigger, .altitude(.less, 4000))
        XCTAssertEqual(m.steps[2].commands, [.approach(runway: "04R")])
        XCTAssertEqual(m.steps[3].trigger, .speed(.lessOrEqual, 180))
        XCTAssertEqual(m.steps[3].commands, [.heading(degrees: 270, turn: .left)])
    }

    func testAltitudeInFeetAndRoutes() throws {
        let m = try compile("when alt>=5000: p cape kerav\n# comment\n\nx kerav 50").get()
        XCTAssertEqual(m.steps.count, 2)
        XCTAssertEqual(m.steps[0].trigger, .altitude(.greaterOrEqual, 5000))
        XCTAssertEqual(m.steps[0].commands, [.route(fixes: ["CAPE", "KERAV"])])
        XCTAssertEqual(m.steps[1].commands, [.cross(fix: "KERAV", altitudeFt: 5000)])
    }

    func testErrors() {
        func error(_ r: Result<CompiledMacro, MacroError>) -> MacroError? {
            if case .failure(let e) = r { return e }
            return nil
        }
        XCTAssertEqual(error(compile("at NOWHERE: s180"))?.step, 1)
        XCTAssertNotNil(error(compile("s180\nwhen hdg<90: s200")))
        XCTAssertNotNil(error(compile("s180\nat cape:")))
        XCTAssertNotNil(error(compile("s180 zz")))
        XCTAssertNotNil(error(compile("")))
        XCTAssertNotNil(error(compile("s180", name: "TOO LONG NAME!")))
        XCTAssertNotNil(error(compile("lu", phase: .arrival)))
        XCTAssertNotNil(error(compile("s180", phase: .ground)))
        XCTAssertNotNil(error(compile("i4r", phase: .departure)))
        XCTAssertNotNil(error(compile("mac appr")))
        XCTAssertNil(error(compile("lu\nto", phase: .ground)))
    }

    func testTagText() throws {
        let m = try compile("s210\nat cape: s180").get()
        var run = MacroRun(macro: m, stepStartTick: 0)
        XCTAssertEqual(run.tagText, "M APPR 1/2")
        run.stepIndex = 1
        XCTAssertEqual(run.tagText, "M APPR 2/2 @CAPE")
    }
}

final class MacroCommandBarTests: XCTestCase {
    private let ac = [Aircraft(callsign: "TST1", eastNM: 0, northNM: 0, headingDeg: 90, altitudeFt: 8000, speedKt: 250)]

    func testRunAndCancel() {
        let r = CommandBar.evaluate(input: "tst1 mac appr", aircraft: ac, selected: nil)
        XCTAssertEqual(r.status, .ready)
        XCTAssertEqual(r.macro, .run(callsign: "TST1", name: "APPR"))
        let c = CommandBar.evaluate(input: "mac-", aircraft: ac, selected: "TST1")
        XCTAssertEqual(c.macro, .cancel(callsign: "TST1"))
        XCTAssertEqual(CommandBar.evaluate(input: "tst1 mac", aircraft: ac, selected: nil).status, .incomplete)
        // "m" is still maintain.
        XCTAssertEqual(CommandBar.evaluate(input: "tst1 m", aircraft: ac, selected: nil).issued?.command, .maintain)
    }
}

final class MacroRuntimeTests: XCTestCase {
    private func sim() throws -> Simulation {
        let s = Simulation(seed: 5, airport: try TestSupport.airport("kbos"), initialWind: .calm, windDrifts: false)
        s.spawn(Aircraft(callsign: "TST1", eastNM: 25, northNM: 25, headingDeg: 90, altitudeFt: 8000, speedKt: 250))
        return s
    }

    private func macro(_ text: String, phase: MacroPhase = .arrival, fixes: Set<String> = []) throws -> CompiledMacro {
        try MacroCompiler.compile(Macro(name: "TEST", phase: phase, text: text), knownFixes: fixes).get()
    }

    private var tst1: (Simulation) -> Aircraft? { { $0.aircraft.first { $0.callsign == "TST1" } } }

    func testStepsRunInOrderWhenTriggered() throws {
        let s = try sim()
        XCTAssertNil(s.assignMacro(try macro("d60, s220\nwhen alt<7000: s180"), to: "TST1"))
        XCTAssertEqual(s.macroRuns["TST1"]?.stepIndex, 1, "first step goes out at once")
        s.run(seconds: 20)
        XCTAssertNotNil(s.macroRuns["TST1"], "still waiting for the altitude")
        s.run(seconds: 120)
        XCTAssertNil(s.macroRuns["TST1"], "finished")
        XCTAssertEqual(tst1(s)?.targetSpeedKt ?? 0, 180, accuracy: 0.5)
    }

    func testManualInstructionCancels() throws {
        let s = try sim()
        s.assignMacro(try macro("d60\nwhen alt<7000: s180"), to: "TST1")
        _ = s.issue(IssuedCommand(callsign: "TST1", command: .heading(degrees: 180)))
        XCTAssertNil(s.macroRuns["TST1"])
        XCTAssertTrue(s.radioLog.contains { $0.text.contains("stopped: manual instruction") })
    }

    func testRefusedStepStopsWithFlag() throws {
        let s = try sim()
        s.assignMacro(try macro("d90"), to: "TST1") // not below 8000 ft
        XCTAssertNil(s.macroRuns["TST1"])
        let line = try XCTUnwrap(s.radioLog.last { $0.tag == .macro })
        XCTAssertEqual(line.callsign, "TST1")
    }

    func testTimeout() throws {
        let s = try sim()
        s.macroStepTimeoutSeconds = 10
        s.assignMacro(try macro("s220\nwhen alt<3000: s180"), to: "TST1")
        s.run(seconds: 15)
        XCTAssertNil(s.macroRuns["TST1"])
        XCTAssertTrue(s.radioLog.contains { $0.text.contains("waited over") })
    }

    func testPhaseMismatchRefused() throws {
        let s = try sim()
        XCTAssertNotNil(s.assignMacro(try macro("c90", phase: .departure), to: "TST1"))
        XCTAssertNil(s.macroRuns["TST1"])
    }

    func testNewMacroReplacesOld() throws {
        let s = try sim()
        s.assignMacro(try macro("s220\nwhen alt<3000: s180"), to: "TST1")
        s.assignMacro(try macro("s230\nwhen alt<3500: s190"), to: "TST1")
        XCTAssertEqual(s.macroRuns.count, 1)
        XCTAssertEqual(s.macroRuns["TST1"]?.macro.steps.first?.commands, [.speed(knots: 230)])
    }

    func testAtFixTrigger() throws {
        let s = Simulation(seed: 5, airport: try TestSupport.airport("kbos"), initialWind: .calm, windDrifts: false)
        let fix = try XCTUnwrap(s.fixIdentifiers.sorted().first { id in
            guard let p = s.routePoints(for: [Leg(fixId: id)]).first else { return false }
            return (p.eastNM * p.eastNM + p.northNM * p.northNM).squareRoot() < 30
        })
        let p = try XCTUnwrap(s.routePoints(for: [Leg(fixId: fix)]).first)
        // 6 NM west of the fix, flying east towards it.
        s.spawn(Aircraft(callsign: "TST1", eastNM: p.eastNM - 6, northNM: p.northNM, headingDeg: 90, altitudeFt: 8000, speedKt: 240))
        s.assignMacro(try macro("at \(fix): s180", fixes: s.fixIdentifiers), to: "TST1")
        s.run(seconds: 30)
        XCTAssertNotNil(s.macroRuns["TST1"], "not there yet")
        s.run(seconds: 90)
        XCTAssertNil(s.macroRuns["TST1"], "passed the fix, step sent")
        XCTAssertEqual(tst1(s)?.targetSpeedKt ?? 0, 180, accuracy: 0.5)
    }
}

final class MacroTriggerWithoutColonTests: XCTestCase {
    func testColonIsOptional() throws {
        let m = try MacroCompiler.compile(Macro(name: "A", phase: .arrival,
            text: "at cape d30 s180\nwhen alt<4000 i4r\nwhen alt < 4000 s170"), knownFixes: ["CAPE"]).get()
        XCTAssertEqual(m.steps[0].trigger, .atFix("CAPE"))
        XCTAssertEqual(m.steps[0].commands, [.descend(feet: 3000), .speed(knots: 180)])
        XCTAssertEqual(m.steps[1].trigger, .altitude(.less, 4000))
        XCTAssertEqual(m.steps[2].trigger, .altitude(.less, 4000))
        XCTAssertEqual(m.steps[2].commands, [.speed(knots: 170)])
    }

    func testTriggerAloneAsksForInstruction() {
        let r = MacroCompiler.compile(Macro(name: "A", phase: .arrival, text: "at CAPE"), knownFixes: ["CAPE"])
        guard case .failure(let e) = r else { return XCTFail("expected an error") }
        XCTAssertTrue(e.message.contains("after the trigger"))
    }
}

final class JoinApproachCommandTests: XCTestCase {
    private let joins = ["I27.AYBEE": ApproachJoin(procedure: "I27.AYBEE", runway: "27", via: "AYBEE")]
    private let ac = [Aircraft(callsign: "TST1", eastNM: 0, northNM: 0, headingDeg: 90, altitudeFt: 8000, speedKt: 250)]

    func testJoinWithAndWithoutSpace() {
        let expected = Command.joinApproach(procedure: "I27.AYBEE", runway: "27", via: "AYBEE")
        XCTAssertEqual(CommandBar.evaluate(input: "tst1 j i27.aybee", aircraft: ac, selected: nil, approaches: joins).issued?.command, expected)
        XCTAssertEqual(CommandBar.evaluate(input: "ji27.aybee s180", aircraft: ac, selected: "TST1", approaches: joins).issuedAll.map(\.command),
                       [expected, .speed(knots: 180)])
        XCTAssertEqual(CommandBar.evaluate(input: "tst1 j nope", aircraft: ac, selected: nil, approaches: joins).status, .error)
    }

    func testKbosTableAndMacro() throws {
        let airport = try TestSupport.airport("kbos")
        let table = airport.approachJoins
        XCTAssertEqual(table["I27.AYBEE"]?.via, "AYBEE")
        let m = try MacroCompiler.compile(Macro(name: "J", phase: .arrival, text: "j I27.AYBEE"),
                                          knownFixes: Set(airport.fixes.map(\.id)), approaches: table).get()
        XCTAssertEqual(m.steps[0].commands, [.joinApproach(procedure: "I27.AYBEE", runway: "27", via: "AYBEE")])
    }
}
