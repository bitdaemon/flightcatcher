import XCTest
@testable import SimCore

final class ExitFixTests: XCTestCase {
    private func boston(removingSids: Bool, seed: UInt64 = 3) throws -> Simulation {
        var airport = try TestSupport.airport("kbos")
        airport.runways.removeAll { $0.id != "04R" }
        if removingSids { airport.procedures.removeAll { $0.kind == .sid } }
        return Simulation(seed: seed, transitionAltitudeFt: airport.transitionAltitudeFt, airport: airport,
                          initialWind: .calm, windDrifts: false)
    }

    private func departures(_ s: Simulation) -> [Aircraft] {
        s.traffic = TrafficSettings(enabled: true, arrivalsPerHour: 0, departuresPerHour: 3600)
        s.run(seconds: 3)
        s.traffic = TrafficSettings(enabled: false)
        return s.aircraft.filter { $0.departure != nil }
    }

    func testSidDepartureExitsAtTheEndOfItsSid() throws {
        let s = try boston(removingSids: false)
        let deps = departures(s)
        XCTAssertFalse(deps.isEmpty)
        for ac in deps {
            let sid = try XCTUnwrap(s.airport?.procedures.first { $0.id == ac.departure?.sid })
            XCTAssertEqual(ac.departure?.exitFix, sid.legs.last?.fixId)
        }
    }

    func testDepartureWithoutSidGetsAFixNearTheAreaEdge() throws {
        let s = try boston(removingSids: true)
        let deps = departures(s)
        XCTAssertFalse(deps.isEmpty)
        for ac in deps {
            let exit = try XCTUnwrap(ac.departure?.exitFix, ac.callsign)
            let p = try XCTUnwrap(s.fixPosition(exit))
            let d = hypot(p.east, p.north)
            XCTAssertTrue(d >= s.areaRadiusNM * 0.6 && d <= s.areaRadiusNM * 1.3, "\(exit) at \(d) NM")
        }
    }

    func testPExitGoesDirectToTheExitFix() throws {
        let s = try boston(removingSids: true)
        let dep = try XCTUnwrap(departures(s).first)
        let exit = try XCTUnwrap(dep.departure?.exitFix)
        guard case .success(let parsed) = CommandBar.parseChain("p exit", knownFixes: []), let command = parsed.first else {
            return XCTFail("p exit should parse")
        }
        XCTAssertEqual(parsed, [.direct(fix: Command.exitFixToken)])
        // Airborne first, so the instruction is accepted.
        guard case .accepted = s.issue(IssuedCommand(callsign: dep.callsign, command: .takeoff)) else { return XCTFail("take-off") }
        s.run(seconds: 120)
        guard case .accepted = s.issue(IssuedCommand(callsign: dep.callsign, command: command)) else {
            return XCTFail("p exit refused")
        }
        s.run(seconds: 10)
        let ac = try XCTUnwrap(s.aircraft.first { $0.callsign == dep.callsign })
        XCTAssertEqual(ac.route.first?.id, exit)
        XCTAssertFalse(ac.onRunwayHeading)
        XCTAssertTrue(s.radioLog.contains { $0.speaker == .pilot && $0.text.contains("requesting direct \(exit)") })
    }

    /// An airborne departure, ready to hand off, flying `offsetDeg` away from the bearing to its exit fix.
    private func readyDeparture(_ s: Simulation, offsetDeg: Double) throws -> String {
        let exit = try XCTUnwrap(s.airport?.fixes.map(\.id).first { id in
            s.fixPosition(id).map { hypot($0.east, $0.north) > 20 } ?? false
        })
        let p = try XCTUnwrap(s.fixPosition(exit))
        let toExit = Aircraft.bearingDeg(eastNM: p.east, northNM: p.north)
        var ac = Aircraft(callsign: "DEP1", eastNM: 0, northNM: 0, headingDeg: toExit + offsetDeg, altitudeFt: 12000, speedKt: 250)
        var d = DepartureInfo(runway: "04R", sid: "", initialAltitudeFt: 5000, fieldElevationFt: 20, rotateSpeedKt: 150,
                              expectedLevelFt: 22000, handoffAltitudeFt: 10000)
        d.checkedIn = true
        d.vectored = true
        d.exitFix = exit
        ac.departure = d
        ac.targetAltitudeFt = 22000
        ac.targetHeadingDeg = ac.headingDeg
        s.spawn(ac)
        return ac.callsign
    }

    func testHandoffTowardsTheExitScores() throws {
        let s = try boston(removingSids: true)
        let callsign = try readyDeparture(s, offsetDeg: 10)
        guard case .accepted = s.issue(IssuedCommand(callsign: callsign, command: .handoff)) else { return XCTFail("handoff") }
        s.run(seconds: 8)
        XCTAssertEqual(s.score.count(.exitDirection), 1)
        XCTAssertEqual(s.score.count(.exitWrongWay), 0)
    }

    func testHandoffTheWrongWayCosts() throws {
        let s = try boston(removingSids: true)
        let callsign = try readyDeparture(s, offsetDeg: 150)
        guard case .accepted = s.issue(IssuedCommand(callsign: callsign, command: .handoff)) else { return XCTFail("handoff") }
        s.run(seconds: 8)
        XCTAssertEqual(s.score.count(.exitWrongWay), 1)
        XCTAssertEqual(s.score.count(.exitDirection), 0)
    }
}
