import Foundation

/// What random traffic to generate. Persisted by the app; the simulation only reads it.
public struct TrafficSettings: Equatable, Codable {
    public var enabled: Bool
    public var arrivalsPerHour: Double
    /// Departures that appear at a holding point per hour. They wait there until the controller clears them.
    public var departuresPerHour: Double
    public var ifr: Bool
    /// VFR traffic. Off by default. Nothing generates VFR aircraft yet; the switch is saved for when it does.
    public var vfr: Bool
    public var enabledCategories: Set<AircraftCategory>
    public var disabledTypes: Set<String>
    /// Fixed seed for repeating a session. Nil means a new random seed each start.
    public var fixedSeed: UInt64?
    /// Top of the arrival range. `arrivalsPerHour` is the bottom; nil (or a value not above it) means a fixed rate.
    public var arrivalsMaxPerHour: Double?
    /// Top of the departure range. `departuresPerHour` is the bottom; nil means a fixed rate.
    public var departuresMaxPerHour: Double?
    /// How often and how sharply the rates move inside their ranges.
    public var variation: TrafficVariation

    public init(enabled: Bool = false, arrivalsPerHour: Double = 15, departuresPerHour: Double = 8,
                ifr: Bool = true, vfr: Bool = false,
                enabledCategories: Set<AircraftCategory> = [.heavy, .narrowbody, .regional, .light],
                disabledTypes: Set<String> = [], fixedSeed: UInt64? = nil,
                arrivalsMaxPerHour: Double? = nil, departuresMaxPerHour: Double? = nil,
                variation: TrafficVariation = .moderate) {
        self.arrivalsMaxPerHour = arrivalsMaxPerHour
        self.departuresMaxPerHour = departuresMaxPerHour
        self.variation = variation
        self.enabled = enabled
        self.arrivalsPerHour = arrivalsPerHour
        self.departuresPerHour = departuresPerHour
        self.ifr = ifr
        self.vfr = vfr
        self.enabledCategories = enabledCategories
        self.disabledTypes = disabledTypes
        self.fixedSeed = fixedSeed
    }
}

extension TrafficSettings {
    /// Tolerates settings saved before a field existed.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(enabled: try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? false,
                  arrivalsPerHour: try c.decodeIfPresent(Double.self, forKey: .arrivalsPerHour) ?? 15,
                  departuresPerHour: try c.decodeIfPresent(Double.self, forKey: .departuresPerHour) ?? 8,
                  ifr: try c.decodeIfPresent(Bool.self, forKey: .ifr) ?? true,
                  vfr: try c.decodeIfPresent(Bool.self, forKey: .vfr) ?? false,
                  enabledCategories: try c.decodeIfPresent(Set<AircraftCategory>.self, forKey: .enabledCategories)
                      ?? [.heavy, .narrowbody, .regional, .light],
                  disabledTypes: try c.decodeIfPresent(Set<String>.self, forKey: .disabledTypes) ?? [],
                  fixedSeed: try c.decodeIfPresent(UInt64.self, forKey: .fixedSeed),
                  arrivalsMaxPerHour: try c.decodeIfPresent(Double.self, forKey: .arrivalsMaxPerHour),
                  departuresMaxPerHour: try c.decodeIfPresent(Double.self, forKey: .departuresMaxPerHour),
                  variation: try c.decodeIfPresent(TrafficVariation.self, forKey: .variation) ?? .moderate)
    }

    /// Arrivals per hour, low to high. A single value when the range is fixed.
    public var arrivalRange: ClosedRange<Double> {
        arrivalsPerHour...max(arrivalsPerHour, arrivalsMaxPerHour ?? arrivalsPerHour)
    }

    /// Departures per hour, low to high.
    public var departureRange: ClosedRange<Double> {
        departuresPerHour...max(departuresPerHour, departuresMaxPerHour ?? departuresPerHour)
    }

    /// True when either rate can move.
    public var isVariable: Bool {
        arrivalRange.upperBound > arrivalRange.lowerBound || departureRange.upperBound > departureRange.lowerBound
    }
}

/// How the traffic rates move inside their ranges.
public enum TrafficVariation: String, Codable, CaseIterable, Identifiable {
    case steady, moderate, lively

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .steady: return "Steady"
        case .moderate: return "Moderate"
        case .lively: return "Lively"
        }
    }

    /// Seconds until the next new target rate.
    var intervalSeconds: ClosedRange<Double> {
        switch self {
        case .steady: return 1200...1800
        case .moderate: return 480...900
        case .lively: return 180...480
        }
    }

    /// How far a new target may be from the present rate, as a share of the range width.
    var jump: Double {
        switch self {
        case .steady: return 0.3
        case .moderate: return 0.6
        case .lively: return 1.0
        }
    }

    /// Seconds for the rate to move most of the way (about 95%) to a new target.
    var easeSeconds: Double {
        switch self {
        case .steady: return 180
        case .moderate: return 120
        case .lively: return 60
        }
    }
}

public struct TrafficPreset: Identifiable {
    public var id: String { name }
    public let name: String
    /// Arrival range, low to high.
    public let arrivals: ClosedRange<Double>
    public let variation: TrafficVariation
    public let categories: Set<AircraftCategory>

    private static let all4: Set<AircraftCategory> = [.heavy, .narrowbody, .regional, .light]

    public static let all: [TrafficPreset] = [
        TrafficPreset(name: "Quiet", arrivals: 2...8, variation: .steady, categories: all4),
        TrafficPreset(name: "Moderate", arrivals: 12...24, variation: .moderate, categories: all4),
        TrafficPreset(name: "Busy", arrivals: 25...45, variation: .moderate, categories: all4),
        TrafficPreset(name: "Rush", arrivals: 30...50, variation: .lively, categories: all4),
        TrafficPreset(name: "Airline only", arrivals: 20...35, variation: .moderate, categories: [.heavy, .narrowbody, .regional]),
        TrafficPreset(name: "Heavy mix", arrivals: 15...30, variation: .moderate, categories: [.heavy, .narrowbody]),
        TrafficPreset(name: "Turboprops and light", arrivals: 8...18, variation: .moderate, categories: [.regional, .light]),
    ]

    /// Applies the arrival range, variation and type selection, leaving the on/off switch, departures, IFR flag and
    /// seed alone.
    public func apply(to settings: inout TrafficSettings) {
        settings.arrivalsPerHour = arrivals.lowerBound
        settings.arrivalsMaxPerHour = arrivals.upperBound
        settings.variation = variation
        settings.enabledCategories = categories
        settings.disabledTypes = []
    }
}

enum TrafficPlanner {
    /// Types that may be generated as IFR arrivals under the settings.
    static func eligibleTypes(_ settings: TrafficSettings) -> [AircraftType] {
        guard settings.ifr else { return [] }
        return AircraftCatalog.all.filter {
            $0.canFlyIFR && settings.enabledCategories.contains($0.category) && !settings.disabledTypes.contains($0.code)
        }
    }

    /// Weighted choice; `roll` is in 0..<1.
    static func pick<T>(_ items: [(T, Double)], roll: Double) -> T {
        let total = items.reduce(0) { $0 + $1.1 }
        var target = roll * total
        for (item, weight) in items {
            if target < weight { return item }
            target -= weight
        }
        return items[items.count - 1].0
    }

    static func unit(_ rng: inout SeededRNG) -> Double { Double(rng.next() >> 11) / Double(1 << 53) }

    /// A callsign not in `taken`. Airline traffic gets a designator that suits the airport's country plus a flight number.
    /// Light aircraft and helicopters get a national registration: "N" plus digits and letters in the US, "EI" plus three
    /// letters in Ireland, and "G" plus four letters elsewhere.
    static func callsign(for type: AircraftType, country: String? = nil, rng: inout SeededRNG, taken: Set<String>) -> String {
        var candidate = ""
        let letters = Array("ABCDEFGHJKLMNPQRSTUVWXYZ")   // no I or O, as in US registrations
        func letter(_ rng: inout SeededRNG) -> String { String(letters[Int(rng.next() % UInt64(letters.count))]) }
        for _ in 0..<40 {
            let airlines = AirlineTable.airlines(for: type.category, country: country)
            if airlines.isEmpty {
                switch country {
                case "US":
                    // N + 1 to 3 digits (first not zero), then two more digits or one or two letters.
                    let digits = 1 + Int(rng.next() % 3)   // 1 to 3 digits after the first, so at most 5 in all
                    var text = "N" + String(1 + rng.next() % 9)
                    for _ in 1..<digits { text += String(rng.next() % 10) }
                    let tail = rng.next() % 3
                    if tail == 0 { text += String(rng.next() % 10) + String(rng.next() % 10) }
                    else { text += letter(&rng) + (tail == 1 ? letter(&rng) : "") }
                    candidate = text
                case "IE", nil:
                    candidate = "EI" + (0..<3).map { _ in letter(&rng) }.joined()
                default:
                    candidate = "G" + (0..<4).map { _ in letter(&rng) }.joined()
                }
            } else {
                let airline = pick(airlines.map { ($0.0, $0.1) }, roll: unit(&rng))
                let span = airline.numbers.upperBound - airline.numbers.lowerBound + 1
                let number = airline.numbers.lowerBound + Int(rng.next() % UInt64(span))
                candidate = airline.code + String(number)
            }
            if !taken.contains(candidate) { return candidate }
        }
        return candidate
    }
}
