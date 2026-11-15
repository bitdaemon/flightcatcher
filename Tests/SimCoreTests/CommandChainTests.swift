import XCTest
@testable import SimCore

final class CommandChainTests: XCTestCase {
    func testSameKindReplacesInPlace() {
        var chain = CommandChain()
        chain.add(.heading(degrees: 270), for: "EIN1")
        chain.add(.speed(knots: 180), for: "EIN1")
        chain.add(.heading(degrees: 90, turn: .left), for: "EIN1")
        XCTAssertEqual(chain.commands, [.heading(degrees: 90, turn: .left), .speed(knots: 180)])
    }

    func testClimbAndDescendShareTheAltitudeSlot() {
        var chain = CommandChain()
        chain.add(.descend(feet: 5000), for: "EIN1")
        chain.add(.climb(feet: 9000), for: "EIN1")
        XCTAssertEqual(chain.commands, [.climb(feet: 9000)])
    }

    func testDirectAndApproachAreSeparateAndKeepOrder() {
        var chain = CommandChain()
        chain.add(.direct(fix: "KERAV"), for: "EIN1")
        chain.add(.approach(runway: "28L"), for: "EIN1")
        chain.add(.direct(fix: "PIZSA"), for: "EIN1")
        XCTAssertEqual(chain.commands, [.direct(fix: "PIZSA"), .approach(runway: "28L")])
    }

    func testChoosingAnotherAircraftStartsANewChain() {
        var chain = CommandChain()
        chain.add(.speed(knots: 180), for: "EIN1")
        chain.add(.speed(knots: 200), for: "RYR2")
        XCTAssertEqual(chain.callsign, "RYR2")
        XCTAssertEqual(chain.commands, [.speed(knots: 200)])
    }

    func testRemoveAndClear() {
        var chain = CommandChain()
        chain.add(.speed(knots: 180), for: "EIN1")
        chain.add(.heading(degrees: 270), for: "EIN1")
        chain.remove(at: 0)
        XCTAssertEqual(chain.commands, [.heading(degrees: 270)])
        chain.remove(at: 5) // out of range: ignored
        XCTAssertEqual(chain.commands.count, 1)
        chain.remove(at: 0)
        XCTAssertTrue(chain.isEmpty)
        XCTAssertNil(chain.callsign)
    }

    func testIssuedCarriesTheCallsign() {
        var chain = CommandChain()
        chain.add(.descend(feet: 3000), for: "EIN1")
        chain.add(.speed(knots: 160), for: "EIN1")
        XCTAssertEqual(chain.issued().map(\.callsign), ["EIN1", "EIN1"])
        XCTAssertEqual(chain.issued().map(\.command), [.descend(feet: 3000), .speed(knots: 160)])
    }

    func testChipLabels() {
        XCTAssertEqual(Command.heading(degrees: 270, turn: .left).chipLabel, "HDG 270L")
        XCTAssertEqual(Command.heading(degrees: 90).chipLabel, "HDG 090")
        XCTAssertEqual(Command.descend(feet: 5000).chipLabel, "ALT 5000")
        XCTAssertEqual(Command.direct(fix: "KERAV").chipLabel, "DCT KERAV")
        XCTAssertEqual(Command.approach(runway: "28L").chipLabel, "ILS 28L")
        XCTAssertEqual(Command.speed(knots: 180).chipLabel, "SPD 180")
    }
}
