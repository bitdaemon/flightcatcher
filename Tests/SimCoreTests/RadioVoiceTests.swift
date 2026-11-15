import XCTest
@testable import SimCore

final class RadioVerifierTests: XCTestCase {
    private let readback = RadioUtterance(speaker: .pilot, callsignSpoken: "Copa seven one one",
                                          template: "Descend eight thousand feet, Copa seven one one")

    func testAcceptsAReordering() {
        XCTAssertTrue(RadioVerifier.accepts("Copa seven one one, descending eight thousand feet", for: readback))
        XCTAssertTrue(RadioVerifier.accepts("Descending eight thousand, Copa seven one one", for: readback))
    }

    func testRejectsAChangedNumber() {
        XCTAssertFalse(RadioVerifier.accepts("Descend nine thousand feet, Copa seven one one", for: readback))
        XCTAssertFalse(RadioVerifier.accepts("Descend eight thousand five hundred feet, Copa seven one one", for: readback))
        XCTAssertFalse(RadioVerifier.accepts("Descend 8000 feet, Copa seven one one", for: readback))
    }

    func testRejectsAMissingOrWrongCallsign() {
        XCTAssertFalse(RadioVerifier.accepts("Descend eight thousand feet", for: readback))
        XCTAssertFalse(RadioVerifier.accepts("Descend eight thousand feet, Copa seven one two", for: readback))
    }

    func testRejectsInventedFixesAndLongOrMultilineText() {
        let direct = RadioUtterance(speaker: .pilot, callsignSpoken: "Delta nine zero six",
                                    template: "Proceed direct BIBQU, then CIANE, Delta nine zero six")
        XCTAssertTrue(RadioVerifier.accepts("Direct BIBQU then CIANE, Delta nine zero six", for: direct))
        XCTAssertFalse(RadioVerifier.accepts("Direct BIBQU then TACOH, Delta nine zero six", for: direct))
        XCTAssertFalse(RadioVerifier.accepts("Direct BIBQU then CIANE, Delta nine zero six, thanks a lot and have a great day", for: direct))
        XCTAssertFalse(RadioVerifier.accepts("Direct BIBQU\nthen CIANE, Delta nine zero six", for: direct))
    }

    func testChooseFallsBackToTheTemplate() {
        XCTAssertEqual(RadioVerifier.choose(variant: nil, for: readback), readback.template)
        XCTAssertEqual(RadioVerifier.choose(variant: "Descend nine thousand feet, Copa seven one one", for: readback), readback.template)
        XCTAssertEqual(RadioVerifier.choose(variant: "Descending eight thousand, Copa seven one one", for: readback),
                       "Descending eight thousand, Copa seven one one")
    }
}
