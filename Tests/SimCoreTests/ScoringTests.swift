import XCTest
@testable import SimCore

final class ScoringRuleTests: XCTestCase {
    func testEfficiencyBonus() {
        XCTAssertEqual(ScoreRules.efficiencyBonus(actualSeconds: 100, cleanSeconds: 100), 30)
        XCTAssertEqual(ScoreRules.efficiencyBonus(actualSeconds: 120, cleanSeconds: 100), 30)
        XCTAssertEqual(ScoreRules.efficiencyBonus(actualSeconds: 160, cleanSeconds: 100), 15)
        XCTAssertEqual(ScoreRules.efficiencyBonus(actualSeconds: 200, cleanSeconds: 100), 0)
        XCTAssertEqual(ScoreRules.efficiencyBonus(actualSeconds: 500, cleanSeconds: 100), 0)
        XCTAssertEqual(ScoreRules.efficiencyBonus(actualSeconds: 50, cleanSeconds: 0), 0)
    }

    func testOnlyControllerGoAroundsCost() {
        XCTAssertFalse(ScoreRules.isControllerGoAround(reason: "pilot's decision, not stable"))
        XCTAssertFalse(ScoreRules.isControllerGoAround(reason: "windshear on final"))
        XCTAssertTrue(ScoreRules.isControllerGoAround(reason: "unstable, 220 kt inside 2.5 NM"))
        XCTAssertTrue(ScoreRules.isControllerGoAround(reason: "runway 04R occupied"))
    }

    func testEventText() {
        let gain = ScoreEvent(id: 0, tick: 0, kind: .arrivalHandoff, points: 100, callsign: "AAL1", detail: "AAL1")
        let loss = ScoreEvent(id: 1, tick: 0, kind: .lossOfSeparation, points: -300, callsign: nil, detail: "A / B")
        XCTAssertEqual(gain.text, "+100 arrival handed to tower AAL1")
        XCTAssertEqual(loss.text, "\u{2212}300 loss of separation A / B")
    }

    func testGradeAndLossCap() {
        var card = ScoreCard()
        XCTAssertNil(card.grade)
        card.arrivalsHandled = 2
        card.add(ScoreEvent(id: 0, tick: 0, kind: .arrivalHandoff, points: 260, callsign: nil, detail: ""))
        XCTAssertEqual(card.grade, .a) // 260 of 300
        card.losses = 1
        XCTAssertEqual(card.grade, .c, "one loss caps the grade at C")
        card.losses = 3
        XCTAssertEqual(card.grade, .e)
    }

    func testMultiplier() {
        let none = EventSettings()
        XCTAssertEqual(ScoreMultiplier.value(averageRatePerHour: 23, variable: false, variation: .moderate,
                                             events: none, liveWeather: false, gusting: false), 1.0)
        XCTAssertEqual(ScoreMultiplier.value(averageRatePerHour: nil, variable: false, variation: .moderate,
                                             events: none, liveWeather: false, gusting: false), 1.0)
        XCTAssertEqual(ScoreMultiplier.value(averageRatePerHour: 5, variable: false, variation: .moderate,
                                             events: none, liveWeather: false, gusting: false), 0.5)
        XCTAssertEqual(ScoreMultiplier.value(averageRatePerHour: 100, variable: true, variation: .lively,
                                             events: none, liveWeather: false, gusting: false), 2.2)
        let all = EventSettings(pilotGoAroundPercent: 3, windshearPercent: 2, emergencyPercent: 2)
        XCTAssertEqual(ScoreMultiplier.value(averageRatePerHour: 23, variable: false, variation: .steady,
                                             events: all, liveWeather: true, gusting: true), 1.25)
    }
}

final class ScoringSimulationTests: XCTestCase {
    private func boston() throws -> Simulation {
        let airport = try TestSupport.airport("kbos")
        return Simulation(seed: 5, transitionAltitudeFt: airport.transitionAltitudeFt, airport: airport,
                          initialWind: .calm, windDrifts: false)
    }

    func testRefusedInstructionCostsFivePoints() {
        let s = Simulation(seed: 1)
        s.spawn(Aircraft(callsign: "TST1", eastNM: 10, northNM: 0, headingDeg: 270, altitudeFt: 3000, speedKt: 180))
        guard case .refused = s.issue(IssuedCommand(callsign: "TST1", command: .approach(runway: "27"))) else {
            return XCTFail("expected refusal")
        }
        XCTAssertEqual(s.score.count(.refused), 1)
        XCTAssertEqual(s.score.raw, -5)
        // An unknown callsign is a typing slip, not a refusal by a pilot.
        _ = s.issue(IssuedCommand(callsign: "NOPE", command: .heading(degrees: 90)))
        XCTAssertEqual(s.score.count(.refused), 1)
    }

    func testLossOfSeparationCostsAndKeepsCosting() {
        let s = Simulation(seed: 1)
        s.spawn(Aircraft(callsign: "A1", eastNM: 0, northNM: 0, headingDeg: 90, altitudeFt: 5000, speedKt: 250))
        s.spawn(Aircraft(callsign: "B1", eastNM: 1, northNM: 0, headingDeg: 90, altitudeFt: 5000, speedKt: 250))
        s.run(seconds: 21)
        XCTAssertEqual(s.score.losses, 1)
        XCTAssertEqual(s.score.count(.lossOfSeparation), 1)
        XCTAssertEqual(s.score.count(.lossContinues), 2, "after 10 s and 20 s")
        XCTAssertTrue(s.radioLog.contains { $0.text.hasPrefix("\u{2212}300 loss of separation") })
    }

    func testEndedSessionScoresNothingUntilResumed() {
        let s = Simulation(seed: 1)
        s.spawn(Aircraft(callsign: "A1", eastNM: 0, northNM: 0, headingDeg: 90, altitudeFt: 5000, speedKt: 250))
        s.spawn(Aircraft(callsign: "B1", eastNM: 1, northNM: 0, headingDeg: 90, altitudeFt: 5000, speedKt: 250))
        s.run(seconds: 5)
        let card = s.endSession()
        XCTAssertNotNil(card.endTick)
        let frozen = s.score.raw
        s.run(seconds: 30)
        XCTAssertEqual(s.score.raw, frozen)
        s.resumeSession()
        s.run(seconds: 10)
        XCTAssertLessThan(s.score.raw, frozen, "the loss goes on costing once resumed")
    }

    func testArrivalHandoffLandingAndEfficiency() throws {
        let s = try boston()
        let ils = try XCTUnwrap(s.ilsGeometry(runway: "04R"))
        let behind = LocalProjection.offset(bearingDeg: ils.courseDeg + 180, distanceNM: 6)
        var ac = Aircraft(callsign: "RYR9", eastNM: ils.thresholdEastNM + behind.east,
                          northNM: ils.thresholdNorthNM + behind.north,
                          headingDeg: ils.courseDeg, altitudeFt: 2100, speedKt: 160)
        ac.clearForApproach(ils, extraRoute: [])
        ac.approach?.phase = .glideslope
        s.spawn(ac)
        guard case .accepted = s.issue(IssuedCommand(callsign: "RYR9", command: .handoff)) else {
            return XCTFail("handoff refused")
        }
        s.run(seconds: 400)
        XCTAssertEqual(s.score.arrivalsHandled, 1)
        XCTAssertEqual(s.score.count(.arrivalHandoff), 1)
        XCTAssertEqual(s.score.count(.landed), 1)
        XCTAssertEqual(s.score.count(.efficiency), 1, "a straight-in arrival is efficient")
        XCTAssertEqual(s.score.arrivals.first?.callsign, "RYR9")
        XCTAssertEqual(s.score.arrivals.first?.instructions, 1)
        XCTAssertEqual(s.score.raw, 100 + 20 + 30)
        XCTAssertEqual(s.score.grade, .a)
        XCTAssertTrue(s.radioLog.contains { $0.text == "+100 arrival handed to tower RYR9" })
    }

    func testDepartureWaitingTooLongCosts() throws {
        var airport = try TestSupport.airport("kbos")
        airport.runways.removeAll { $0.id != "04R" }
        let s = Simulation(seed: 3, transitionAltitudeFt: airport.transitionAltitudeFt, airport: airport,
                           initialWind: .calm, windDrifts: false)
        s.traffic = TrafficSettings(enabled: true, arrivalsPerHour: 0, departuresPerHour: 3600)
        s.run(seconds: 3)
        s.traffic = TrafficSettings(enabled: false)
        let waiting = s.aircraft.filter { $0.groundPhase == .holdingShort }.count
        XCTAssertGreaterThan(waiting, 0)
        s.run(seconds: 180)
        XCTAssertEqual(s.score.count(.departureDelay), 0, "three minutes are free")
        s.run(seconds: 62)
        XCTAssertEqual(s.score.count(.departureDelay), waiting, "one point each after the fourth minute")
    }

    func testSamplesEveryMinuteAndMultiplierAtEnd() {
        let s = Simulation(seed: 1)
        s.traffic = TrafficSettings(enabled: true, arrivalsPerHour: 15, departuresPerHour: 8, ifr: false)
        s.run(seconds: 180)
        XCTAssertEqual(s.score.samples.map(\.minute), [1, 2, 3])
        let card = s.endSession()
        XCTAssertEqual(card.multiplier, 1.0)
    }
}

final class TowerSeparationTests: XCTestCase {
    private func pair(towerFirst: Bool, towerSecond: Bool) -> Simulation {
        let s = Simulation(seed: 1)
        var a = Aircraft(callsign: "JBU2780", eastNM: 0, northNM: 0, headingDeg: 90, altitudeFt: 3000, speedKt: 150)
        var b = Aircraft(callsign: "N228RQ", eastNM: 1, northNM: 0, headingDeg: 90, altitudeFt: 3000, speedKt: 150)
        a.handedToTower = towerFirst
        b.handedToTower = towerSecond
        s.spawn(a)
        s.spawn(b)
        return s
    }

    func testBothWithTheTowerIsNotYourLoss() {
        let s = pair(towerFirst: true, towerSecond: true)
        s.run(seconds: 25)
        XCTAssertEqual(s.lossOfSeparationCount, 0)
        XCTAssertEqual(s.score.losses, 0)
        XCTAssertEqual(s.score.raw, 0)
        XCTAssertTrue(s.radioLog.contains { $0.text.contains("both with the tower (not counted)") })
        XCTAssertEqual(s.conflicts.first?.kind, .loss, "still shown on the scope")
    }

    func testOneStillYoursCounts() {
        let s = pair(towerFirst: true, towerSecond: false)
        s.run(seconds: 11)
        XCTAssertEqual(s.score.losses, 1)
        XCTAssertEqual(s.score.count(.lossContinues), 1)
    }
}
