import XCTest
@testable import SimCore

final class DisplaySchemeTests: XCTestCase {
    /// CIE L*a*b* distance (CIE76) between two 0xRRGGBB colours. Roughly: 2 is just noticeable, 25 and up is
    /// clearly different at a glance.
    private func distance(_ a: UInt32, _ b: UInt32) -> Double {
        func lab(_ hex: UInt32) -> (Double, Double, Double) {
            func lin(_ v: Double) -> Double { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
            let r = lin(Double((hex >> 16) & 0xFF) / 255), g = lin(Double((hex >> 8) & 0xFF) / 255), b = lin(Double(hex & 0xFF) / 255)
            let x = (0.4124564 * r + 0.3575761 * g + 0.1804375 * b) / 0.95047
            let y = 0.2126729 * r + 0.7151522 * g + 0.0721750 * b
            let z = (0.0193339 * r + 0.1191920 * g + 0.9503041 * b) / 1.08883
            func f(_ t: Double) -> Double { t > 0.008856 ? cbrt(t) : 7.787 * t + 16.0 / 116 }
            return (116 * f(y) - 16, 500 * (f(x) - f(y)), 200 * (f(y) - f(z)))
        }
        let p = lab(a), q = lab(b)
        return ((p.0 - q.0) * (p.0 - q.0) + (p.1 - q.1) * (p.1 - q.1) + (p.2 - q.2) * (p.2 - q.2)).squareRoot()
    }

    func testThereAreAtLeastTenUniqueSchemes() {
        XCTAssertGreaterThanOrEqual(DisplaySchemes.all.count, 10)
        XCTAssertEqual(Set(DisplaySchemes.all.map(\.id)).count, DisplaySchemes.all.count)
        XCTAssertEqual(DisplaySchemes.scheme(id: "no-such-scheme").id, DisplaySchemes.all[0].id)
        XCTAssertEqual(DisplaySchemes.scheme(id: DisplaySchemes.defaultID).id, DisplaySchemes.defaultID)
    }

    func testScopeLinesAreClearlyDistinguishableInEveryScheme() {
        for scheme in DisplaySchemes.all {
            let c = scheme.colors
            let lines: [(String, UInt32)] = [("star", c.star), ("sid", c.sid), ("approach", c.approach),
                                             ("route", c.route), ("runway", c.runway)]
            for i in lines.indices {
                for j in lines.indices where j > i {
                    XCTAssertGreaterThan(distance(lines[i].1, lines[j].1), 22, "\(scheme.name): \(lines[i].0) / \(lines[j].0)")
                }
            }
            // The projected route must stand apart from the approach line it often runs along.
            XCTAssertGreaterThan(distance(c.route, c.approach), 40, "\(scheme.name): route / approach")
            for (name, color) in lines + [("selected", c.selected), ("alert", c.alert), ("warning", c.warning),
                                          ("ok", c.ok), ("aircraft", c.aircraft), ("heading", c.heading)] {
                XCTAssertGreaterThan(distance(color, c.background), 40, "\(scheme.name): \(name) against the background")
            }
            for (name, color) in [("star", c.star), ("sid", c.sid), ("approach", c.approach)] {
                XCTAssertGreaterThan(distance(c.selected, color), 28, "\(scheme.name): selected / \(name)")
            }
            XCTAssertGreaterThan(distance(c.aircraft, c.runway), 12, "\(scheme.name): aircraft / runway")
        }
    }

    func testTextIsReadableOnPanels() {
        for scheme in DisplaySchemes.all {
            let c = scheme.colors
            XCTAssertGreaterThan(distance(c.text, c.panel), 55, "\(scheme.name): text")
            XCTAssertGreaterThan(distance(c.dimText, c.panel), 32, "\(scheme.name): dim text")
            XCTAssertGreaterThan(distance(c.background, c.panel), 2, "\(scheme.name): panel / background")
        }
    }
}
