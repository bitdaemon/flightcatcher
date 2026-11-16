import XCTest
@testable import SimCore

/// "j01l": pick an approach by runway, best first for the aircraft; "j01l.2" the second choice.
final class RunwayJoinTests: XCTestCase {
    private let approaches: [String: ApproachJoin] = [
        "R27.NEAR": ApproachJoin(procedure: "R27.NEAR", runway: "27", via: "NEAR"),
        "R27.FAR": ApproachJoin(procedure: "R27.FAR", runway: "27", via: "FAR"),
        "R27.ONRTE": ApproachJoin(procedure: "R27.ONRTE", runway: "27", via: "ONRTE"),
        "I09.EAST": ApproachJoin(procedure: "I09.EAST", runway: "09", via: "EAST"),
    ]
    private let fixes: [String: (east: Double, north: Double)] = [
        "NEAR": (5, 0), "FAR": (25, 0), "ONRTE": (15, 10), "EAST": (-10, 0),
    ]

    private func aircraft(onRoute: Bool) -> Aircraft {
        var ac = Aircraft(callsign: "AAL1", eastNM: 0, northNM: 0, headingDeg: 90, altitudeFt: 6000, speedKt: 220)
        if onRoute { ac.route = [RoutePoint(id: "ONRTE", eastNM: 15, northNM: 10)] }
        return ac
    }

    private func evaluate(_ input: String, onRoute: Bool = false, open: Set<String>? = nil) -> CommandBarResult {
        CommandBar.evaluate(input: input, aircraft: [aircraft(onRoute: onRoute)], selected: nil,
                            approaches: approaches, fixPositions: fixes, openRunways: open)
    }

    func testRanking() {
        let ranked = CommandBar.runwayChoices(for: aircraft(onRoute: false), runway: "27", approaches: approaches,
                                              fixPositions: fixes).map(\.join.procedure)
        XCTAssertEqual(ranked, ["R27.NEAR", "R27.ONRTE", "R27.FAR"])
        let routed = CommandBar.runwayChoices(for: aircraft(onRoute: true), runway: "27", approaches: approaches,
                                              fixPositions: fixes).map(\.join.procedure)
        XCTAssertEqual(routed.first, "R27.ONRTE", "an approach starting on the route comes first")
    }

    func testJRunwayPicksTheBestAndNumbersPickTheRest() {
        XCTAssertEqual(evaluate("aal1 j27").issued?.command,
                       .joinApproach(procedure: "R27.NEAR", runway: "27", via: "NEAR"))
        XCTAssertEqual(evaluate("aal1 j 27.3").issued?.command,
                       .joinApproach(procedure: "R27.FAR", runway: "27", via: "FAR"))
        XCTAssertEqual(evaluate("aal1 j27", onRoute: true).issued?.command,
                       .joinApproach(procedure: "R27.ONRTE", runway: "27", via: "ONRTE"))
    }

    func testPreviewListsTheChoices() {
        let message = evaluate("aal1 j27").message
        XCTAssertTrue(message.contains("[27: .1 R27.NEAR 5, .2 R27.ONRTE 18, .3 R27.FAR 25]"), message)
    }

    func testRunwayNotInUse() {
        let result = evaluate("aal1 j09", open: ["27"])
        XCTAssertNotEqual(result.status, .ready)
        XCTAssertTrue(result.message.contains("runway 09 is not in use"), result.message)
    }

    func testProcedureIdsStillWork() {
        XCTAssertEqual(evaluate("aal1 j r27.far").issued?.command,
                       .joinApproach(procedure: "R27.FAR", runway: "27", via: "FAR"))
    }
}
