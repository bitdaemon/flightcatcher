import XCTest
@testable import SimCore

final class GeoTests: XCTestCase {
    func testOneDegreeOfLatitudeIsSixtyNM() {
        let p = LocalProjection(originLat: 53.0, originLon: -6.0)
        let r = p.nm(lat: 54.0, lon: -6.0)
        XCTAssertEqual(r.north, 60, accuracy: 1e-9)
        XCTAssertEqual(r.east, 0, accuracy: 1e-9)
    }

    func testOffsetDueEastAndNorth() {
        let e = LocalProjection.offset(bearingDeg: 90, distanceNM: 1)
        XCTAssertEqual(e.east, 1, accuracy: 1e-9)
        XCTAssertEqual(e.north, 0, accuracy: 1e-9)
        let n = LocalProjection.offset(bearingDeg: 0, distanceNM: 2)
        XCTAssertEqual(n.north, 2, accuracy: 1e-9)
    }
}
