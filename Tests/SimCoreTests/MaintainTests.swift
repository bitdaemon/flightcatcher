import XCTest
@testable import SimCore

final class MaintainTests: XCTestCase {
    private func plane() -> Aircraft {
        Aircraft(callsign: "EIN1", eastNM: 0, northNM: 0, headingDeg: 0, altitudeFt: 10000, speedKt: 250)
    }

    func testMaintainFreezesHeadingAltitudeAndSpeed() {
        var a = plane()
        a.apply(.expedite(.heading(degrees: 90)))
        a.apply(.descend(feet: 5000))
        a.apply(.speed(knots: 180))
        a.advance(seconds: 5, wind: .calm)
        let heading = a.headingDeg, altitude = a.altitudeFt, speed = a.speedKt
        a.apply(.maintain)
        XCTAssertFalse(a.expeditingHeading)
        for _ in 0..<60 { a.advance(seconds: 1, wind: .calm) }
        XCTAssertEqual(a.headingDeg, heading, accuracy: 0.01)
        XCTAssertEqual(a.altitudeFt, altitude, accuracy: 0.01)
        XCTAssertEqual(a.speedKt, speed, accuracy: 0.01)
    }

    func testMaintainClearsRouteAndCrossing() {
        var a = plane()
        a.setRoute([RoutePoint(id: "AAA", eastNM: 10, northNM: 10)])
        a.apply(.cross(fix: "AAA", altitudeFt: 8000))
        a.apply(.maintain)
        XCTAssertTrue(a.route.isEmpty)
        XCTAssertNil(a.crossing)
    }

    func testMBarWordIsAMaintainCommand() {
        let result = CommandBar.evaluate(input: "m", aircraft: [plane()], selected: "EIN1")
        XCTAssertEqual(result.issued?.command, .maintain)
    }
}
