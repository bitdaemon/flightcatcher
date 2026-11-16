import XCTest
@testable import SimCore

final class ResumeNavigationTests: XCTestCase {
    private func boston() throws -> Simulation {
        let airport = try TestSupport.airport("kbos")
        return Simulation(seed: 1, transitionAltitudeFt: airport.transitionAltitudeFt, airport: airport,
                          initialWind: .calm, windDrifts: false)
    }

    func testParsesOwnAndRn() {
        XCTAssertEqual(try CommandBar.parseChain("own", knownFixes: []).get(), [.resumeNavigation])
        XCTAssertEqual(try CommandBar.parseChain("rn", knownFixes: []).get(), [.resumeNavigation])
        XCTAssertEqual(Phraseology.instruction(.resumeNavigation, for: Aircraft(callsign: "X", eastNM: 0, northNM: 0,
                                                                                headingDeg: 0, altitudeFt: 5000, speedKt: 200),
                                               transitionAltitudeFt: 18000), "resume own navigation")
    }

    func testVectoredArrivalRejoinsItsStarAhead() throws {
        let s = try boston()
        let star = try XCTUnwrap(s.airport?.procedures.first { $0.kind == .star && $0.legs.count >= 4 })
        XCTAssertTrue(s.spawn(callsign: "TST1", procedure: star.id, startIndex: 1, altitudeFt: 9000, speedKt: 220))
        _ = s.issue(IssuedCommand(callsign: "TST1", command: .heading(degrees: 360)))
        s.run(seconds: 60)
        XCTAssertTrue(s.aircraft[0].route.isEmpty, "vectored off the STAR")
        guard case .accepted = s.issue(IssuedCommand(callsign: "TST1", command: .resumeNavigation)) else {
            return XCTFail("resume refused")
        }
        s.run(seconds: 8)
        let route = s.aircraft[0].route.map(\.id)
        XCTAssertFalse(route.isEmpty)
        XCTAssertEqual(route.last, star.legs.last?.fixId, "flies the rest of the STAR")
        XCTAssertTrue(Set(route).isSubset(of: Set(star.legs.map(\.fixId))))
        XCTAssertFalse(route.contains(star.legs[0].fixId), "does not go back to a fix already behind it")
        XCTAssertTrue(s.radioLog.contains { $0.text.contains("resumes own navigation, next \(route[0])") })
    }

    func testDepartureWithoutSidResumesToItsExit() throws {
        let s = try boston()
        let exit = try XCTUnwrap(s.airport?.fixes.first?.id)
        var ac = Aircraft(callsign: "DEP1", eastNM: 0, northNM: 0, headingDeg: 90, altitudeFt: 6000, speedKt: 250)
        var d = DepartureInfo(runway: "04R", sid: "", initialAltitudeFt: 5000, fieldElevationFt: 20, rotateSpeedKt: 150)
        d.exitFix = exit
        ac.departure = d
        s.spawn(ac)
        XCTAssertEqual(s.resumeRoute(for: s.aircraft[0]).map(\.id), [exit])
    }

    func testNothingToResumeIsRefused() throws {
        let s = try boston()
        s.spawn(Aircraft(callsign: "VFR1", eastNM: 5, northNM: 5, headingDeg: 90, altitudeFt: 4000, speedKt: 120))
        XCTAssertEqual(s.issue(IssuedCommand(callsign: "VFR1", command: .resumeNavigation)),
                       .refused("VFR1 has no route to resume"))
    }
}
