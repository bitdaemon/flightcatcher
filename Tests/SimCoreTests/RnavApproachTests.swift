import XCTest
@testable import SimCore

final class RnavApproachTests: XCTestCase {
    /// West wind, so runway 27 is in use.
    private func boston() throws -> Simulation {
        let airport = try TestSupport.airport("kbos")
        return Simulation(seed: 1, transitionAltitudeFt: airport.transitionAltitudeFt, airport: airport,
                          initialWind: Wind(fromDeg: 270, speedKt: 10), windDrifts: false)
    }

    func testTypeFromProcedureId() {
        XCTAssertEqual(ApproachType(procedureId: "I27.AYBEE"), .ils)
        XCTAssertEqual(ApproachType(procedureId: "R27.AYBEE"), .rnav)
        XCTAssertEqual(ApproachType(procedureId: "H33LX"), .rnp)
    }

    func testBostonHasRnavApproachesWithTypeAndPathAngle() throws {
        let airport = try TestSupport.airport("kbos")
        let r27 = try XCTUnwrap(airport.procedures.first { $0.id == "R27.AYBEE" })
        XCTAssertEqual(r27.kind, .approach)
        XCTAssertEqual(r27.finalApproachType, .rnav)
        XCTAssertEqual(r27.runways, ["27"])
        XCTAssertEqual(r27.glidepathDeg ?? 3.0, 3.0, accuracy: 0.2)
        XCTAssertEqual(airport.procedures.first { $0.id == "I27.AYBEE" }?.finalApproachType, .ils)
        XCTAssertNotNil(airport.approachJoins["R27.AYBEE"])
        XCTAssertTrue(airport.validate().isEmpty)
    }

    func testRnavGeometryIsTheRunwayCentrelineWithThePublishedAngle() throws {
        let sim = try boston()
        let proc = try XCTUnwrap(sim.airport?.procedures.first { $0.id == "R32" })
        let rwy = try XCTUnwrap(sim.airport?.runways.first { $0.id == "32" })
        let g = try XCTUnwrap(sim.approachGeometry(procedure: proc))
        XCTAssertEqual(g.runwayId, "32")
        XCTAssertEqual(g.courseDeg, rwy.trueBearingDeg, accuracy: 0.01)
        XCTAssertEqual(g.glidepathDeg, proc.glidepathDeg ?? 3.0, accuracy: 0.001)
        XCTAssertFalse(g.isVisual)
    }

    func testJoinRnavApproachIsAcceptedAndSpokenAsRnav() throws {
        let sim = try boston()
        // East of the field, where approaches to 27 come from, heading in.
        sim.spawn(Aircraft(callsign: "AAL123", eastNM: 20, northNM: 0, headingDeg: 270, altitudeFt: 6000, speedKt: 220))
        let r = sim.issue(IssuedCommand(callsign: "AAL123",
                                        command: .joinApproach(procedure: "R27.AYBEE", runway: "27", via: "AYBEE")))
        guard case .accepted = r else { return XCTFail("expected acceptance, got \(r)") }
        let text = try XCTUnwrap(sim.radioLog.last { $0.speaker == .controller }?.text)
        XCTAssertTrue(text.contains("cleared RNAV approach runway"), text)
        sim.run(seconds: 10)
        let ac = try XCTUnwrap(sim.aircraft.first { $0.callsign == "AAL123" })
        XCTAssertFalse(sim.radioLog.contains { $0.text.contains("go-around") || $0.text.contains("unable") },
                       sim.radioLog.suffix(4).map(\.text).joined(separator: " | "))
        XCTAssertTrue(ac.route.contains { $0.id == "AYBEE" } || ac.approach?.phase != .intercepting)
        XCTAssertEqual(ac.approach?.ils.runwayId, "27")
    }

    func testAirportWithoutIlsCanFlyAnRnavApproach() throws {
        var airport = try TestSupport.airport("kbos")
        airport.procedures.removeAll { $0.kind == .approach && $0.finalApproachType == .ils }
        for i in airport.runways.indices { airport.runways[i].ils = nil }
        XCTAssertTrue(airport.validate().isEmpty, "\(airport.validate().prefix(3))")
        let sim = Simulation(seed: 1, transitionAltitudeFt: airport.transitionAltitudeFt, airport: airport,
                             initialWind: Wind(fromDeg: 270, speedKt: 10), windDrifts: false)
        sim.spawn(Aircraft(callsign: "TST1", eastNM: 15, northNM: 5, headingDeg: 270, altitudeFt: 6000, speedKt: 220))
        let r = sim.issue(IssuedCommand(callsign: "TST1", command: .joinApproach(procedure: "R27.AYBEE", runway: "27", via: "AYBEE")))
        guard case .accepted = r else { return XCTFail("expected acceptance, got \(r)") }
    }
}
