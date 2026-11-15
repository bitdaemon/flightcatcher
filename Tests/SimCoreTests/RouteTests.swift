import XCTest
@testable import SimCore

final class RouteTests: XCTestCase {
    private let fixes: Set<String> = ["KERAV", "PIZSA", "LAMBA"]
    private func fleet() -> [Aircraft] {
        [Aircraft(callsign: "EIN123", eastNM: 0, northNM: 0, headingDeg: 275, altitudeFt: 7000, speedKt: 220)]
    }

    func testTypedRoute() {
        for input in ["ein p kerav pizsa lamba", "ein pkerav pizsa lamba"] {
            let r = CommandBar.evaluate(input: input, aircraft: fleet(), selected: nil, knownFixes: fixes)
            XCTAssertEqual(r.issued?.command, .route(fixes: ["KERAV", "PIZSA", "LAMBA"]), input)
        }
    }

    func testRouteThenOtherCodes() {
        let r = CommandBar.evaluate(input: "ein p kerav pizsa d50 s180", aircraft: fleet(), selected: nil, knownFixes: fixes)
        XCTAssertEqual(r.issuedAll.map(\.command), [.route(fixes: ["KERAV", "PIZSA"]), .descend(feet: 5000), .speed(knots: 180)])
    }

    func testSingleFixStaysDirect() {
        let r = CommandBar.evaluate(input: "ein p kerav", aircraft: fleet(), selected: nil, knownFixes: fixes)
        XCTAssertEqual(r.issued?.command, .direct(fix: "KERAV"))
    }

    func testLabelsAndSlot() {
        XCTAssertEqual(Command.route(fixes: ["A", "B"]).chipLabel, "DCT A›B")
        var chain = CommandChain()
        chain.add(.direct(fix: "A"), for: "EIN1")
        chain.add(.route(fixes: ["B", "C"]), for: "EIN1")
        XCTAssertEqual(chain.commands, [.route(fixes: ["B", "C"])])
    }

    func testShortRouteRefused() {
        XCTAssertNotNil(Command.route(fixes: ["A"]).refusal(for: fleet()[0]))
    }
}
