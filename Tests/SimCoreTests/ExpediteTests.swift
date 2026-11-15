import XCTest
@testable import SimCore

final class ExpediteTests: XCTestCase {
    private func plane() -> Aircraft {
        Aircraft(callsign: "EIN1", eastNM: 0, northNM: 0, headingDeg: 0, altitudeFt: 10000, speedKt: 250)
    }

    func testExpeditedDescentIsFasterAndClears() {
        var normal = plane(), fast = plane()
        normal.apply(.descend(feet: 5000))
        fast.apply(.expedite(.descend(feet: 5000)))
        XCTAssertTrue(fast.expeditingAltitude)
        for _ in 0..<30 { normal.advance(seconds: 1, wind: .calm); fast.advance(seconds: 1, wind: .calm) }
        XCTAssertEqual(normal.altitudeFt, 10000 - 1800.0 / 60 * 30, accuracy: 0.01)
        XCTAssertEqual(fast.altitudeFt, 10000 - 1800.0 / 60 * 30 * 1.6, accuracy: 0.01)
        for _ in 0..<200 { fast.advance(seconds: 1, wind: .calm) }
        XCTAssertEqual(fast.altitudeFt, 5000)
        XCTAssertFalse(fast.expeditingAltitude)
    }

    func testExpeditedTurnAndSpeed() {
        var a = plane()
        a.apply(.expedite(.heading(degrees: 90)))
        a.apply(.expedite(.speed(knots: 150)))
        a.advance(seconds: 10, wind: .calm)
        XCTAssertEqual(a.headingDeg, 45, accuracy: 0.01)
        XCTAssertEqual(a.speedKt, 230, accuracy: 0.01)
        for _ in 0..<100 { a.advance(seconds: 1, wind: .calm) }
        XCTAssertFalse(a.expeditingHeading)
        XCTAssertFalse(a.expeditingSpeed)
    }

    func testPlainCommandCancelsExpedite() {
        var a = plane()
        a.apply(.expedite(.climb(feet: 20000)))
        a.apply(.climb(feet: 15000))
        XCTAssertFalse(a.expeditingAltitude)
    }

    func testPhraseologyAndChipLabel() {
        let a = plane()
        XCTAssertEqual(Phraseology.instruction(.expedite(.descend(feet: 5000)), for: a, transitionAltitudeFt: 5000),
                       "expedite descent to five thousand feet")
        XCTAssertEqual(Command.expedite(.heading(degrees: 270, turn: .left)).chipLabel, "HDG 270L!")
        XCTAssertNotNil(Command.expedite(.approach(runway: "28L")).refusal(for: a))
    }

    func testChainSlotReplacement() {
        var chain = CommandChain()
        chain.add(.heading(degrees: 270), for: "EIN1")
        chain.add(.expedite(.heading(degrees: 90)), for: "EIN1")
        XCTAssertEqual(chain.commands, [.expedite(.heading(degrees: 90))])
    }
}
