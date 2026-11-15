import XCTest
@testable import SimCore

final class CrossingTests: XCTestCase {
    private let fixes: Set<String> = ["KERAV", "PIZSA"]

    func testTypedCrossing() {
        for input in ["ein x kerav 50", "ein xkerav 50"] {
            let r = CommandBar.evaluate(input: input, aircraft: [Aircraft(callsign: "EIN123", eastNM: 0, northNM: 0, headingDeg: 90, altitudeFt: 9000, speedKt: 220)],
                                        selected: nil, knownFixes: fixes)
            XCTAssertEqual(r.issued?.command, .cross(fix: "KERAV", altitudeFt: 5000), input)
        }
    }

    func testRouteThenCrossInOneLine() {
        let r = CommandBar.evaluate(input: "ein p kerav pizsa x pizsa 50 s180",
                                    aircraft: [Aircraft(callsign: "EIN123", eastNM: 0, northNM: 0, headingDeg: 90, altitudeFt: 9000, speedKt: 220)],
                                    selected: nil, knownFixes: fixes)
        XCTAssertEqual(r.issuedAll.map(\.command),
                       [.route(fixes: ["KERAV", "PIZSA"]), .cross(fix: "PIZSA", altitudeFt: 5000), .speed(knots: 180)])
    }

    func testMissingLevelIsIncomplete() {
        let r = CommandBar.evaluate(input: "x kerav", aircraft: [Aircraft(callsign: "EIN123", eastNM: 0, northNM: 0, headingDeg: 90, altitudeFt: 9000, speedKt: 220)],
                                    selected: "EIN123", knownFixes: fixes)
        XCTAssertEqual(r.status, .incomplete)
    }

    /// 30 NM at 300 kt is 360 s; a 4000 ft descent at 1800 fpm needs 133 s. The aircraft must hold, then descend, and be at the level over the fix.
    func testHoldsThenDescendsToBeAtLevelOverTheFix() {
        var a = Aircraft(callsign: "T", eastNM: 0, northNM: 0, headingDeg: 90, altitudeFt: 9000, speedKt: 300)
        a.setRoute([RoutePoint(id: "KERAV", eastNM: 30, northNM: 0)])
        a.apply(.cross(fix: "KERAV", altitudeFt: 5000))
        for _ in 0..<100 { a.advance(seconds: 1) }
        XCTAssertEqual(a.altitudeFt, 9000, accuracy: 0.01)
        for _ in 0..<160 { a.advance(seconds: 1) }
        XCTAssertLessThan(a.altitudeFt, 9000)
        var overFixAltitude: Double?
        for _ in 0..<200 {
            a.advance(seconds: 1)
            if a.route.isEmpty && overFixAltitude == nil { overFixAltitude = a.altitudeFt }
        }
        XCTAssertEqual(overFixAltitude ?? 0, 5000, accuracy: 150)
    }

    func testRouteEndIsReportedAndCrossingUnableWhenTooClose() {
        var a = Aircraft(callsign: "T", eastNM: 0, northNM: 0, headingDeg: 90, altitudeFt: 9000, speedKt: 300)
        a.setRoute([RoutePoint(id: "KERAV", eastNM: 3, northNM: 0)])
        a.apply(.cross(fix: "KERAV", altitudeFt: 3000))
        var events: [AircraftEvent] = []
        for _ in 0..<60 { a.advance(seconds: 1); events += a.drainEvents() }
        XCTAssertTrue(events.contains(.crossingUnable(fix: "KERAV", altitudeFt: 3000)))
        XCTAssertTrue(events.contains { if case .routeEnded(let fix, _) = $0 { return fix == "KERAV" } else { return false } })
    }

    func testHeadingClearsCrossing() {
        var a = Aircraft(callsign: "T", eastNM: 0, northNM: 0, headingDeg: 90, altitudeFt: 9000, speedKt: 300)
        a.apply(.cross(fix: "KERAV", altitudeFt: 5000))
        a.apply(.heading(degrees: 180))
        XCTAssertNil(a.crossing)
    }

    func testChipAndPhraseology() {
        let a = Aircraft(callsign: "EIN123", eastNM: 0, northNM: 0, headingDeg: 90, altitudeFt: 9000, speedKt: 220)
        XCTAssertEqual(Command.cross(fix: "KERAV", altitudeFt: 5000).chipLabel, "X KERAV 5000")
        XCTAssertEqual(Phraseology.instruction(.cross(fix: "KERAV", altitudeFt: 5000), for: a, transitionAltitudeFt: 5000),
                       "cross KERAV at five thousand feet")
        var chain = CommandChain()
        chain.add(.cross(fix: "A", altitudeFt: 5000), for: "EIN1")
        chain.add(.cross(fix: "B", altitudeFt: 4000), for: "EIN1")
        chain.add(.cross(fix: "A", altitudeFt: 6000), for: "EIN1")
        XCTAssertEqual(chain.commands, [.cross(fix: "A", altitudeFt: 6000), .cross(fix: "B", altitudeFt: 4000)])
    }
}
