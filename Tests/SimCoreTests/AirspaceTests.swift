import XCTest
@testable import SimCore

final class AirspaceTests: XCTestCase {
    private func sim(seed: UInt64 = 1) throws -> Simulation {
        let airport = try TestSupport.airport("kbos")
        return Simulation(seed: seed, transitionAltitudeFt: airport.transitionAltitudeFt, airport: airport,
                          initialWind: .calm, windDrifts: false)
    }

    func testArrivalsAreHandedInAtTheAreaEdgeAndCallIn() throws {
        let s = try sim()
        s.areaRadiusNM = 35
        s.areaCeilingFt = 12000
        s.traffic = TrafficSettings(enabled: true, arrivalsPerHour: 60, departuresPerHour: 0)
        var seen = Set<String>()
        for _ in 0..<900 {
            s.tick()
            for ac in s.aircraft where !ac.isOnGround && !seen.contains(ac.callsign) {
                seen.insert(ac.callsign)
                XCTAssertLessThanOrEqual(hypot(ac.eastNM, ac.northNM), 35.6, "\(ac.callsign) appeared outside the area")
                XCTAssertLessThanOrEqual(ac.altitudeFt, 12000.5, "\(ac.callsign) appeared above the ceiling")
            }
        }
        XCTAssertFalse(seen.isEmpty)
        let checkIns = s.radioLog.filter { $0.speaker == .pilot && $0.text.hasPrefix(s.approachFacility + ",") }
        XCTAssertFalse(checkIns.isEmpty)
        XCTAssertTrue(s.approachFacility.hasSuffix("Approach"))
    }

    func testEntryPointOnAStraightRoute() throws {
        let s = try sim()
        s.areaRadiusNM = 40
        let points = [RoutePoint(id: "A", eastNM: 100, northNM: 0), RoutePoint(id: "B", eastNM: 20, northNM: 0),
                      RoutePoint(id: "C", eastNM: 5, northNM: 0)]
        let entry = try XCTUnwrap(s.areaEntry(points))
        XCTAssertEqual(entry.next, 1)
        XCTAssertEqual(entry.east, 40, accuracy: 1e-9)
        XCTAssertEqual(entry.north, 0, accuracy: 1e-9)
        XCTAssertNil(s.areaEntry([RoutePoint(id: "X", eastNM: 90, northNM: 0), RoutePoint(id: "Y", eastNM: 60, northNM: 0)]))
        XCTAssertEqual(s.areaEntry([RoutePoint(id: "P", eastNM: 10, northNM: 0), RoutePoint(id: "Q", eastNM: 5, northNM: 0)])?.next, 1)
    }

    func testStartTrafficIsInsideTheArea() throws {
        for t in 1...20 {
            let s = try sim()
            s.areaRadiusNM = 30
            s.reseedTraffic(UInt64(t))
            s.placeStartTraffic()
            for ac in s.aircraft { XCTAssertLessThanOrEqual(hypot(ac.eastNM, ac.northNM), 30.01, "seed \(t)") }
        }
    }
}
