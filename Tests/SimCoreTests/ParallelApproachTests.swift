import XCTest
@testable import SimCore

/// Aircraft established on approaches to parallel runways are separated by the parallel-approach rules.
final class ParallelApproachTests: XCTestCase {
    /// Two parallel finals heading north, `spacingNM` apart, and an aircraft on each, `alongOffset` NM apart along
    /// the course, at the same altitude.
    private func pair(spacingNM: Double, alongOffset: Double = 0, sameRunway: Bool = false,
                      phase: ApproachPhase = .glideslope) -> [Aircraft] {
        let left = ILSGeometry(runwayId: "36L", thresholdEastNM: 0, thresholdNorthNM: 0, courseDeg: 0,
                               glidepathDeg: 3, thresholdElevationFt: 0, thresholdCrossingHeightFt: 50)
        let right = ILSGeometry(runwayId: sameRunway ? "36L" : "36R", thresholdEastNM: spacingNM, thresholdNorthNM: 0,
                                courseDeg: 0, glidepathDeg: 3, thresholdElevationFt: 0, thresholdCrossingHeightFt: 50)
        var a = Aircraft(callsign: "AAA1", eastNM: 0, northNM: -6, headingDeg: 0, altitudeFt: 2000, speedKt: 160)
        var b = Aircraft(callsign: "BBB2", eastNM: spacingNM, northNM: -6 - alongOffset, headingDeg: 0, altitudeFt: 2000, speedKt: 160)
        a.clearForApproach(left, extraRoute: [])
        b.clearForApproach(right, extraRoute: [])
        a.approach?.phase = phase
        b.approach?.phase = phase
        return [a, b]
    }

    func testIndependentParallelsSideBySideAreFine() {
        XCTAssertTrue(SeparationMonitor.evaluate(pair(spacingNM: 1.0)).isEmpty)
    }

    func testDependentParallelsNeedOnePointFiveDiagonal() {
        XCTAssertEqual(SeparationMonitor.evaluate(pair(spacingNM: 0.3, alongOffset: 0.5)).first?.kind, .loss)
        XCTAssertTrue(SeparationMonitor.evaluate(pair(spacingNM: 0.3, alongOffset: 2.0)).isEmpty,
                      "2 NM diagonal is enough on dependent parallels, though less than 3 NM")
    }

    func testSameRunwayStillNeedsThreeMiles() {
        XCTAssertEqual(SeparationMonitor.evaluate(pair(spacingNM: 0, alongOffset: 2.0, sameRunway: true)).first?.kind, .loss)
    }

    func testNotYetEstablishedUsesTheNormalMinimum() {
        XCTAssertEqual(SeparationMonitor.evaluate(pair(spacingNM: 1.0, phase: .intercepting)).first?.kind, .loss)
    }
}
