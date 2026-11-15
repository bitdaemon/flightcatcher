import XCTest
@testable import SimCore

/// Airports with no SID or no STAR in the FAA data (radar-vector departures and arrivals). Boston with its SIDs or
/// STARs removed stands in for them.
final class NoProcedureTests: XCTestCase {
    private func sim(removing kind: ProcedureKind, seed: UInt64 = 3) throws -> Simulation {
        var airport = try TestSupport.airport("kbos")
        airport.procedures.removeAll { $0.kind == kind }
        return Simulation(seed: seed, transitionAltitudeFt: airport.transitionAltitudeFt, airport: airport,
                          initialWind: .calm, windDrifts: false)
    }

    func testDepartureWithoutSIDClimbsOnRunwayHeading() throws {
        let s = try sim(removing: .sid)
        s.traffic = TrafficSettings(enabled: true, arrivalsPerHour: 0, departuresPerHour: 3600)
        s.run(seconds: 5)
        s.traffic = TrafficSettings(enabled: false)
        let first = try XCTUnwrap(s.aircraft.first { $0.departure != nil })
        XCTAssertEqual(first.departure?.sid, "")
        XCTAssertNil(first.procedureId)
        XCTAssertTrue(first.route.isEmpty)
        let runway = try XCTUnwrap(s.airport?.runways.first { $0.id == first.departure?.runway })

        let r = s.issue(IssuedCommand(callsign: first.callsign, command: .takeoff))
        guard case .accepted = r else { return XCTFail("take-off refused: \(r)") }
        s.run(seconds: 240)
        let climbing = try XCTUnwrap(s.aircraft.first { $0.callsign == first.callsign })
        XCTAssertNil(climbing.groundPhase)
        XCTAssertEqual(Aircraft.signedTurn(from: climbing.headingDeg, to: runway.trueBearingDeg), 0, accuracy: 1)
        XCTAssertEqual(climbing.altitudeFt, Double(first.departure!.initialAltitudeFt), accuracy: 60)
        XCTAssertTrue(s.radioLog.contains { $0.speaker == .pilot && $0.text.contains("runway heading") })
        XCTAssertTrue(s.radioLog.contains { $0.speaker == .controller && $0.text.contains("fly runway heading, climb to")
                                            && $0.text.contains("cleared for take-off") })
        XCTAssertTrue(climbing.onRunwayHeading)
        XCTAssertEqual(climbing.navLabel, "RWYHDG")

        // The first vector ends runway heading.
        guard case .accepted = s.issue(IssuedCommand(callsign: first.callsign, command: .heading(degrees: 90))) else {
            return XCTFail("heading refused")
        }
        s.run(seconds: 10)
        let vectored = try XCTUnwrap(s.aircraft.first { $0.callsign == first.callsign })
        XCTAssertFalse(vectored.onRunwayHeading)
        XCTAssertEqual(vectored.navLabel, "HDG")
    }

    func testDepartureWithSIDIsNeverOnRunwayHeading() throws {
        var airport = try TestSupport.airport("kbos")
        airport.runways.removeAll { $0.id != "04R" }
        let s = Simulation(seed: 3, transitionAltitudeFt: airport.transitionAltitudeFt, airport: airport,
                           initialWind: .calm, windDrifts: false)
        s.traffic = TrafficSettings(enabled: true, arrivalsPerHour: 0, departuresPerHour: 3600)
        s.run(seconds: 3)
        let dep = try XCTUnwrap(s.aircraft.first { $0.departure != nil })
        XCTAssertFalse(dep.departure!.sid.isEmpty)
        XCTAssertFalse(dep.onRunwayHeading)
        guard case .accepted = s.issue(IssuedCommand(callsign: dep.callsign, command: .takeoff)) else {
            return XCTFail("take-off refused")
        }
        let call = try XCTUnwrap(s.radioLog.last { $0.speaker == .controller }?.text)
        XCTAssertTrue(call.contains(Phraseology.spokenProcedure(dep.departure!.sid) + " departure, climb and maintain"), call)
        XCTAssertTrue(call.hasSuffix("cleared for take-off"), call)
    }

    func testWindChoosesTheRunwayAndSIDsFollowIt() throws {
        let s = try sim(removing: .star)
        s.traffic = TrafficSettings(enabled: true, arrivalsPerHour: 0, departuresPerHour: 3600)
        s.run(seconds: 5)
        let deps = s.aircraft.filter { $0.departure != nil }
        XCTAssertFalse(deps.isEmpty)
        for dep in deps {
            let runway = try XCTUnwrap(dep.departure?.runway)
            let hasSids = s.airport!.procedures.contains { $0.kind == .sid && $0.runways.contains(runway) && $0.legs.count >= 2 }
            if hasSids {
                XCTAssertTrue(s.airport!.procedures.contains { $0.id == dep.departure?.sid && $0.kind == .sid }, runway)
            } else {
                XCTAssertEqual(dep.departure?.sid, "", runway)
                XCTAssertTrue(dep.route.isEmpty, runway)
            }
        }
    }

    func testArrivalWithoutSTARIsHandedInAtTheEdgeDirectToAnInitialFix() throws {
        let s = try sim(removing: .star)
        let fixes = Set(s.feederFixes().map(\.id))
        XCTAssertFalse(fixes.isEmpty)
        s.traffic = TrafficSettings(enabled: true, arrivalsPerHour: 3600, departuresPerHour: 0)
        s.run(seconds: 1)
        s.traffic = TrafficSettings(enabled: false)
        let arrival = try XCTUnwrap(s.aircraft.first { $0.departure == nil })
        XCTAssertEqual(hypot(arrival.eastNM, arrival.northNM), s.areaRadiusNM, accuracy: 1.5)
        XCTAssertTrue(arrival.procedureId?.hasPrefix("DCT ") == true)
        XCTAssertEqual(arrival.route.count, 1)
        XCTAssertTrue(fixes.contains(arrival.route[0].id))
        XCTAssertLessThanOrEqual(arrival.altitudeFt, 11000)
        XCTAssertTrue(s.radioLog.contains { $0.speaker == .pilot && $0.text.contains("Approach") })
    }

    func testStartTrafficWithoutSTARs() throws {
        let s = try sim(removing: .star)
        let placed = s.placeStartTraffic(counts: 3...3)
        XCTAssertGreaterThan(placed, 0)
        for ac in s.aircraft {
            XCTAssertLessThan(hypot(ac.eastNM, ac.northNM), s.areaRadiusNM)
            XCTAssertTrue(ac.procedureId?.hasPrefix("DCT ") == true)
            // Inbound: further out than the fix it is flying to, so it never flies away from the airport to reach it.
            let fix = try XCTUnwrap(ac.route.first)
            XCTAssertGreaterThan(hypot(ac.eastNM, ac.northNM), hypot(fix.eastNM, fix.northNM) + 4.9, ac.callsign)
        }
    }
}
