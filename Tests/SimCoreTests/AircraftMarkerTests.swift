import XCTest
@testable import SimCore

final class AircraftMarkerTests: XCTestCase {
    /// CIE76 distance in L*a*b*, as in DisplaySchemeTests.
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

    func testSixColoursClearOfEverySchemeColour() {
        XCTAssertEqual(AircraftMarkers.palette.count, 6)
        for scheme in DisplaySchemes.all {
            let c = scheme.colors
            let reserved: [(String, UInt32)] = [("star", c.star), ("sid", c.sid), ("approach", c.approach), ("route", c.route),
                                                ("selected", c.selected), ("alert", c.alert), ("warning", c.warning),
                                                ("ok", c.ok), ("aircraft", c.aircraft), ("heading", c.heading),
                                                ("runway", c.runway), ("controller", c.controller)]
            for marker in AircraftMarkers.palette {
                for (name, colour) in reserved {
                    XCTAssertGreaterThan(distance(marker.rgb, colour), 25, "\(scheme.name): \(marker.name) / \(name)")
                }
                XCTAssertGreaterThan(distance(marker.rgb, c.background), 35, "\(scheme.name): \(marker.name) / background")
                XCTAssertGreaterThan(distance(marker.rgb, c.panel), 35, "\(scheme.name): \(marker.name) / panel")
            }
        }
    }

    func testColoursAreDistinctFromEachOther() {
        let colours = AircraftMarkers.palette
        for i in colours.indices {
            for j in colours.indices where j > i {
                XCTAssertGreaterThan(distance(colours[i].rgb, colours[j].rgb), 30, "\(colours[i].name) / \(colours[j].name)")
            }
        }
        XCTAssertEqual(Set(colours.map(\.name)).count, 6)
    }

    func testCycle() {
        var index: Int? = nil
        var seen: [Int] = []
        for _ in 0..<6 { index = AircraftMarkers.next(after: index); seen.append(index!) }
        XCTAssertEqual(seen, [0, 1, 2, 3, 4, 5])
        XCTAssertNil(AircraftMarkers.next(after: 5))
    }

    func testAircraftRememberTheirAssignedProcedure() throws {
        let airport = try TestSupport.airport("kbos")
        let s = Simulation(seed: 3, airport: airport, initialWind: .calm, windDrifts: false)
        XCTAssertTrue(s.spawn(callsign: "TST1", procedure: "WOONS2", altitudeFt: 8000, speedKt: 220))
        XCTAssertEqual(s.aircraft[0].procedureId, "WOONS2")
        s.traffic = TrafficSettings(enabled: true, arrivalsPerHour: 0, departuresPerHour: 3600)
        s.run(seconds: 3)
        let departure = try XCTUnwrap(s.aircraft.first { $0.departure != nil })
        // A runway without SIDs gives no procedure and an empty SID.
        XCTAssertEqual(departure.procedureId ?? "", departure.departure?.sid)
    }
}
