import Foundation

/// Six colours the controller can give to an aircraft to remember what has been done with it (vectored, cleared for
/// the approach, handed off and so on). They were chosen to stay clear of every colour scheme's line, alert and
/// selection colours; `AircraftMarkerTests` checks the distance in every scheme.
public enum AircraftMarkers {
    public struct Marker: Equatable {
        public let name: String
        public let rgb: UInt32
    }

    public static let palette: [Marker] = [
        Marker(name: "Salmon", rgb: 0xD28279),
        Marker(name: "Blue", rgb: 0x1919FF),
        Marker(name: "Green", rgb: 0x19FF19),
        Marker(name: "Magenta", rgb: 0xE500B7),
        Marker(name: "Purple", rgb: 0x6739AC),
        Marker(name: "Lime", rgb: 0xD1FF19),
    ]

    /// The next colour in the cycle none, 1, 2 ... 6, none.
    public static func next(after index: Int?) -> Int? {
        guard let index else { return 0 }
        return index + 1 < palette.count ? index + 1 : nil
    }
}
