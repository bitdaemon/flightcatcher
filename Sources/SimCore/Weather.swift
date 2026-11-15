import Foundation

/// Surface wind, direction the wind blows FROM in degrees true, speed in knots. Aloft the wind is stronger:
/// see `vectorKt(atAltitudeFt:)`. This is a placeholder model: one wind for the whole airspace.
public struct Wind: Equatable {
    public var fromDeg: Double
    public var speedKt: Double
    /// Gust speed, never below the mean speed. Equal to `speedKt` when there are no gusts. Only the runway limits use it.
    public var gustKt: Double

    public static let calm = Wind(fromDeg: 0, speedKt: 0)

    public init(fromDeg: Double, speedKt: Double, gustKt: Double? = nil) {
        self.fromDeg = Aircraft.normalized(fromDeg)
        self.speedKt = max(0, speedKt)
        self.gustKt = max(self.speedKt, gustKt ?? speedKt)
    }

    public var isGusting: Bool { gustKt > speedKt + 0.5 }

    /// Wind speed scale with altitude: 1x at the surface, 3x from 30000 ft up.
    static func altitudeScale(_ altitudeFt: Double) -> Double {
        1 + min(max(altitudeFt, 0), 30000) / 15000
    }

    /// Velocity of the air over the ground in knots (east, north): it moves toward `fromDeg + 180`.
    public func vectorKt(atAltitudeFt altitude: Double) -> (east: Double, north: Double) {
        let rad = fromDeg * .pi / 180
        let speed = speedKt * Self.altitudeScale(altitude)
        return (-speed * sin(rad), -speed * cos(rad))
    }

    /// Surface wind relative to a runway: `head` is positive into the wind and negative for a tailwind;
    /// `cross` is the absolute crosswind component. With `gusts` the gust speed is used instead of the mean.
    public func components(runwayBearingDeg: Double, gusts: Bool = false) -> (head: Double, cross: Double) {
        let angle = (fromDeg - runwayBearingDeg) * .pi / 180
        let speed = gusts ? gustKt : speedKt
        return (speed * cos(angle), abs(speed * sin(angle)))
    }

    /// For display: "270/12", "270/12G22", or "calm".
    public var text: String {
        guard speedKt >= 0.5 else { return "calm" }
        let dir = Int(fromDeg.rounded()) % 360 == 0 ? 360 : Int(fromDeg.rounded()) % 360
        let gust = isGusting ? String(format: "G%02d", Int(gustKt.rounded())) : ""
        return String(format: "%03d/%02d", dir, Int(speedKt.rounded())) + gust
    }
}

/// Placeholder limits for choosing runways. A runway closes when the tailwind or crosswind exceeds them and
/// reopens only when both are `reopenMarginKt` inside them, so it does not flicker. Of the two ends of a strip only
/// the one facing the wind is open (the runway in use).
public enum WindLimits {
    public static let maxTailwindKt = 5.0
    public static let maxCrosswindKt = 25.0
    public static let reopenMarginKt = 1.0
    /// Once a direction of a strip is in use, the other one only takes over when its headwind is better by more than this.
    public static let directionChangeKt = 2.0
}

public struct RunwayStatus: Equatable, Identifiable {
    public var id: String
    public var isOpen: Bool
    /// Negative for a tailwind.
    public var headwindKt: Double
    public var crosswindKt: Double
    /// Why it is closed, empty when open.
    public var reason: String
}

/// Where the wind comes from. `random` drifts on its own, `live` follows real METARs (and drifts randomly until the
/// first one arrives or when none can be had), `fixed` never changes.
public enum WeatherMode: String, Codable, CaseIterable, Identifiable {
    case live, random, fixed
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .live: return "Live (METAR)"
        case .random: return "Random"
        case .fixed: return "Fixed"
        }
    }
}

/// The surface wind from one observation.
public struct WeatherReport: Equatable {
    public var icao: String
    /// Degrees true the wind blows from; nil for a variable or calm wind (the present direction is kept).
    public var fromDeg: Double?
    public var speedKt: Double
    public var gustKt: Double?
    public var raw: String

    public init(icao: String, fromDeg: Double?, speedKt: Double, gustKt: Double? = nil, raw: String = "") {
        self.icao = icao
        self.fromDeg = fromDeg
        self.speedKt = speedKt
        self.gustKt = gustKt
        self.raw = raw
    }
}

/// Reads the Aviation Weather Center METAR response (`/api/data/metar?ids=ICAO&format=json`). The wind comes from the
/// standard group in the raw report, which does not depend on the JSON field names; `wdir`, `wspd` and `wgst` are the
/// fallback.
public enum MetarParser {
    public static func parse(json: Data) -> WeatherReport? {
        guard let array = (try? JSONSerialization.jsonObject(with: json)) as? [[String: Any]], let first = array.first else {
            return nil
        }
        let raw = (first["rawOb"] as? String) ?? ""
        let icao = (first["icaoId"] as? String) ?? ""
        if let wind = parseWind(raw: raw) {
            return WeatherReport(icao: icao, fromDeg: wind.fromDeg, speedKt: wind.speedKt, gustKt: wind.gustKt, raw: raw)
        }
        guard let speed = number(first["wspd"]) else { return nil }
        let dir = number(first["wdir"]) // "VRB" is a string, so nil
        return WeatherReport(icao: icao, fromDeg: speed < 1 ? nil : dir, speedKt: speed, gustKt: number(first["wgst"]), raw: raw)
    }

    /// "25012KT", "VRB03KT", "31015G27KT", "24006MPS". A direction of 000 or a speed under 1 kt keeps the direction.
    static func parseWind(raw: String) -> (fromDeg: Double?, speedKt: Double, gustKt: Double?)? {
        guard let regex = try? NSRegularExpression(pattern: #"\b(\d{3}|VRB)(\d{2,3})(?:G(\d{2,3}))?(KT|MPS)\b"#),
              let m = regex.firstMatch(in: raw, range: NSRange(raw.startIndex..., in: raw)) else { return nil }
        func group(_ i: Int) -> String? { Range(m.range(at: i), in: raw).map { String(raw[$0]) } }
        guard let dirText = group(1), let speedText = group(2), let speed = Double(speedText), let unit = group(4) else { return nil }
        let scale = unit == "MPS" ? 1.943844 : 1.0
        let gust = group(3).flatMap(Double.init).map { $0 * scale }
        let dir = dirText == "VRB" ? nil : Double(dirText)
        let knots = speed * scale
        return (knots < 1 || dir == 0 ? nil : dir, knots, gust)
    }

    private static func number(_ value: Any?) -> Double? {
        if let n = value as? NSNumber { return n.doubleValue }
        if let s = value as? String { return Double(s) }
        return nil
    }
}
