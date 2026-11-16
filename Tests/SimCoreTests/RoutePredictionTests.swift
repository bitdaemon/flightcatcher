import XCTest
@testable import SimCore

/// The conflict prediction follows route fixes, so aircraft whose routes turn apart are not flagged.
final class RoutePredictionTests: XCTestCase {
    private func headOn() -> (Aircraft, Aircraft) {
        (Aircraft(callsign: "AAA1", eastNM: 0, northNM: 0, headingDeg: 90, altitudeFt: 3000, speedKt: 240),
         Aircraft(callsign: "BBB2", eastNM: 8, northNM: 0, headingDeg: 270, altitudeFt: 3500, speedKt: 240))
    }

    func testStraightLinesHeadOnArePredicted() {
        let (a, b) = headOn()
        XCTAssertEqual(SeparationMonitor.evaluate([a, b]).first?.kind, .predicted)
    }

    func testRoutesThatTurnApartAreNotPredicted() {
        var (a, b) = headOn()
        // Each turns away at a fix 2 NM ahead: they never get closer than 4 NM.
        a.route = [RoutePoint(id: "TURNA", eastNM: 2, northNM: 0), RoutePoint(id: "NORTH", eastNM: 2, northNM: 30)]
        a.routeIndex = 0
        b.route = [RoutePoint(id: "TURNB", eastNM: 6, northNM: 0), RoutePoint(id: "SOUTH", eastNM: 6, northNM: -30)]
        b.routeIndex = 0
        XCTAssertTrue(SeparationMonitor.evaluate([a, b]).isEmpty)
    }

    func testRoutesThatConvergeArePredicted() {
        // Parallel headings, but both routes lead to the same fix.
        var a = Aircraft(callsign: "AAA1", eastNM: 0, northNM: 0, headingDeg: 0, altitudeFt: 4000, speedKt: 240)
        var b = Aircraft(callsign: "BBB2", eastNM: 10, northNM: 0, headingDeg: 0, altitudeFt: 4000, speedKt: 240)
        a.route = [RoutePoint(id: "MERGE", eastNM: 5, northNM: 5)]
        b.route = [RoutePoint(id: "MERGE", eastNM: 5, northNM: 5)]
        XCTAssertTrue(SeparationMonitor.evaluate([a, b], lookaheadSeconds: 0).isEmpty, "not lost now")
        XCTAssertEqual(SeparationMonitor.evaluate([a, b]).first?.kind, .predicted)
    }

    func testPositionAlongARouteTurnsAtTheFix() {
        var a = Aircraft(callsign: "AAA1", eastNM: 0, northNM: 0, headingDeg: 90, altitudeFt: 3000, speedKt: 360)
        a.route = [RoutePoint(id: "TURN", eastNM: 1, northNM: 0), RoutePoint(id: "UP", eastNM: 1, northNM: 10)]
        let p = SeparationMonitor.position(a, wind: .calm, after: 30) // 3 NM: 1 east, then 2 north
        XCTAssertEqual(p.east, 1, accuracy: 0.001)
        XCTAssertEqual(p.north, 2, accuracy: 0.001)
    }
}
