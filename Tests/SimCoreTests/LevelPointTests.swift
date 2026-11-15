import XCTest
@testable import SimCore

final class LevelPointTests: XCTestCase {
    func testStraightClimbPointIsAlongTheHeading() throws {
        // 2,000 ft/min, 3,000 ft to climb = 90 s; at 240 kt that is 6 NM due east.
        var ac = Aircraft(callsign: "TST1", eastNM: 0, northNM: 0, headingDeg: 90, altitudeFt: 5000, speedKt: 240)
        ac.climbRateFpm = 2000
        ac.targetHeadingDeg = 90
        let p = try XCTUnwrap(ac.levelPoint(reaching: 8000, expedited: false))
        XCTAssertEqual(p.eastNM, 6, accuracy: 0.01)
        XCTAssertEqual(p.northNM, 0, accuracy: 0.01)
        XCTAssertEqual(p.bearingDeg, 90, accuracy: 0.01)
    }

    func testNoPointWhenAlreadyAtTheLevel() {
        let ac = Aircraft(callsign: "TST2", eastNM: 0, northNM: 0, headingDeg: 0, altitudeFt: 5000, speedKt: 240)
        XCTAssertNil(ac.levelPoint(reaching: 5020, expedited: false))
    }

    func testExpediteShortensTheDistance() throws {
        var ac = Aircraft(callsign: "TST3", eastNM: 0, northNM: 0, headingDeg: 0, altitudeFt: 5000, speedKt: 240)
        ac.climbRateFpm = 2000
        ac.targetHeadingDeg = 0
        let normal = try XCTUnwrap(ac.levelPoint(reaching: 8000, expedited: false))
        let fast = try XCTUnwrap(ac.levelPoint(reaching: 8000, expedited: true))
        XCTAssertLessThan(fast.northNM, normal.northNM)
    }
}
