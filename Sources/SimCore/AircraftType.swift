import Foundation

public enum AircraftCategory: String, CaseIterable, Codable, Identifiable {
    case heavy, narrowbody, regional, light, helicopter
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .heavy: return "Heavy jets"
        case .narrowbody: return "Narrowbody jets"
        case .regional: return "Regional jets and turboprops"
        case .light: return "Light aircraft"
        case .helicopter: return "Helicopters"
        }
    }
}

/// ICAO wake turbulence category. Not used for spacing yet.
public enum WakeCategory: String, Codable {
    case light = "L", medium = "M", heavy = "H", superHeavy = "J"
}

/// Rough performance for one aircraft type. The figures are round-number approximations for gameplay, not
/// manufacturer or OpenAP data; replace them with real performance data later.
public struct AircraftType: Identifiable, Equatable {
    public var id: String { code }
    public let code: String          // ICAO type designator
    public let name: String
    public let category: AircraftCategory
    public let wake: WakeCategory
    /// False for aircraft that only operate VFR in the game.
    public let canFlyIFR: Bool
    public let turnRateDegPerSec: Double
    public let climbRateFpm: Double
    public let descentRateFpm: Double
    public let accelerationKtPerSec: Double
    public let minSpeedKt: Int
    public let maxSpeedKt: Int
    /// Final approach speed. Speed limits on the glidepath are set from it.
    public let approachSpeedKt: Double
    public let ceilingFt: Int
    /// Relative weight when traffic is generated.
    public let share: Double
}

public enum AircraftCatalog {
    public static let all: [AircraftType] = [
        AircraftType(code: "A388", name: "Airbus A380-800", category: .heavy, wake: .superHeavy, canFlyIFR: true,
                     turnRateDegPerSec: 2.5, climbRateFpm: 1700, descentRateFpm: 1800, accelerationKtPerSec: 0.7,
                     minSpeedKt: 150, maxSpeedKt: 350, approachSpeedKt: 145, ceilingFt: 41000, share: 0.3),
        AircraftType(code: "B77W", name: "Boeing 777-300ER", category: .heavy, wake: .heavy, canFlyIFR: true,
                     turnRateDegPerSec: 2.5, climbRateFpm: 1800, descentRateFpm: 1900, accelerationKtPerSec: 0.8,
                     minSpeedKt: 150, maxSpeedKt: 350, approachSpeedKt: 150, ceilingFt: 41000, share: 1),
        AircraftType(code: "A333", name: "Airbus A330-300", category: .heavy, wake: .heavy, canFlyIFR: true,
                     turnRateDegPerSec: 2.7, climbRateFpm: 1900, descentRateFpm: 1900, accelerationKtPerSec: 0.9,
                     minSpeedKt: 140, maxSpeedKt: 350, approachSpeedKt: 140, ceilingFt: 41000, share: 1.2),
        AircraftType(code: "B788", name: "Boeing 787-8", category: .heavy, wake: .heavy, canFlyIFR: true,
                     turnRateDegPerSec: 2.8, climbRateFpm: 2200, descentRateFpm: 2000, accelerationKtPerSec: 1.0,
                     minSpeedKt: 140, maxSpeedKt: 350, approachSpeedKt: 140, ceilingFt: 41000, share: 1),
        AircraftType(code: "A320", name: "Airbus A320", category: .narrowbody, wake: .medium, canFlyIFR: true,
                     turnRateDegPerSec: 3, climbRateFpm: 2400, descentRateFpm: 2000, accelerationKtPerSec: 1.0,
                     minSpeedKt: 130, maxSpeedKt: 350, approachSpeedKt: 135, ceilingFt: 39000, share: 3),
        AircraftType(code: "A21N", name: "Airbus A321neo", category: .narrowbody, wake: .medium, canFlyIFR: true,
                     turnRateDegPerSec: 3, climbRateFpm: 2300, descentRateFpm: 2000, accelerationKtPerSec: 1.0,
                     minSpeedKt: 135, maxSpeedKt: 350, approachSpeedKt: 140, ceilingFt: 39000, share: 1.5),
        AircraftType(code: "B738", name: "Boeing 737-800", category: .narrowbody, wake: .medium, canFlyIFR: true,
                     turnRateDegPerSec: 3, climbRateFpm: 2500, descentRateFpm: 2000, accelerationKtPerSec: 1.0,
                     minSpeedKt: 130, maxSpeedKt: 350, approachSpeedKt: 138, ceilingFt: 41000, share: 3),
        AircraftType(code: "E190", name: "Embraer E190", category: .regional, wake: .medium, canFlyIFR: true,
                     turnRateDegPerSec: 3, climbRateFpm: 2500, descentRateFpm: 2000, accelerationKtPerSec: 1.0,
                     minSpeedKt: 125, maxSpeedKt: 350, approachSpeedKt: 125, ceilingFt: 41000, share: 1),
        AircraftType(code: "CRJ9", name: "Bombardier CRJ900", category: .regional, wake: .medium, canFlyIFR: true,
                     turnRateDegPerSec: 3, climbRateFpm: 2500, descentRateFpm: 2000, accelerationKtPerSec: 1.0,
                     minSpeedKt: 130, maxSpeedKt: 350, approachSpeedKt: 130, ceilingFt: 41000, share: 0.7),
        AircraftType(code: "AT76", name: "ATR 72-600", category: .regional, wake: .medium, canFlyIFR: true,
                     turnRateDegPerSec: 3, climbRateFpm: 1400, descentRateFpm: 1500, accelerationKtPerSec: 0.8,
                     minSpeedKt: 100, maxSpeedKt: 250, approachSpeedKt: 105, ceilingFt: 25000, share: 1),
        AircraftType(code: "DH8D", name: "De Havilland Dash 8 Q400", category: .regional, wake: .medium, canFlyIFR: true,
                     turnRateDegPerSec: 3, climbRateFpm: 1800, descentRateFpm: 1600, accelerationKtPerSec: 0.9,
                     minSpeedKt: 100, maxSpeedKt: 250, approachSpeedKt: 110, ceilingFt: 27000, share: 0.8),
        AircraftType(code: "PC12", name: "Pilatus PC-12", category: .light, wake: .light, canFlyIFR: true,
                     turnRateDegPerSec: 3, climbRateFpm: 1700, descentRateFpm: 1500, accelerationKtPerSec: 0.8,
                     minSpeedKt: 90, maxSpeedKt: 240, approachSpeedKt: 85, ceilingFt: 30000, share: 0.6),
        AircraftType(code: "SR22", name: "Cirrus SR22", category: .light, wake: .light, canFlyIFR: true,
                     turnRateDegPerSec: 3, climbRateFpm: 1200, descentRateFpm: 1000, accelerationKtPerSec: 0.7,
                     minSpeedKt: 80, maxSpeedKt: 180, approachSpeedKt: 80, ceilingFt: 25000, share: 0.6),
        AircraftType(code: "C172", name: "Cessna 172", category: .light, wake: .light, canFlyIFR: false,
                     turnRateDegPerSec: 3, climbRateFpm: 700, descentRateFpm: 700, accelerationKtPerSec: 0.5,
                     minSpeedKt: 60, maxSpeedKt: 120, approachSpeedKt: 65, ceilingFt: 13000, share: 2),
        AircraftType(code: "PA28", name: "Piper PA-28", category: .light, wake: .light, canFlyIFR: false,
                     turnRateDegPerSec: 3, climbRateFpm: 700, descentRateFpm: 700, accelerationKtPerSec: 0.5,
                     minSpeedKt: 65, maxSpeedKt: 130, approachSpeedKt: 70, ceilingFt: 14000, share: 1.5),
        AircraftType(code: "R44", name: "Robinson R44", category: .helicopter, wake: .light, canFlyIFR: false,
                     turnRateDegPerSec: 4, climbRateFpm: 1000, descentRateFpm: 1000, accelerationKtPerSec: 0.8,
                     minSpeedKt: 40, maxSpeedKt: 100, approachSpeedKt: 50, ceilingFt: 8000, share: 0.5),
        AircraftType(code: "AW139", name: "Leonardo AW139", category: .helicopter, wake: .medium, canFlyIFR: false,
                     turnRateDegPerSec: 4, climbRateFpm: 1800, descentRateFpm: 1500, accelerationKtPerSec: 1.0,
                     minSpeedKt: 40, maxSpeedKt: 150, approachSpeedKt: 70, ceilingFt: 15000, share: 0.3),
    ]

    public static func type(code: String) -> AircraftType? { all.first { $0.code == code } }
    public static func types(in category: AircraftCategory) -> [AircraftType] { all.filter { $0.category == category } }
}

/// Airlines (ICAO designator, weight) that operate each kind of aircraft in the generated traffic. Light aircraft
/// and helicopters get Irish-style registrations instead.
/// One airline: ICAO designator, radio telephony name, home country and how often it appears per aircraft category.
/// Weights are (at home, abroad, at a US airport when not a US carrier). A zero means it does not appear there.
/// Starter data from memory of public schedules; radio names and fleets should be checked before relying on them.
public struct Airline {
    public let code: String
    public let radio: String
    public let home: String
    public let weights: [AircraftCategory: (home: Double, abroad: Double, us: Double)]
    /// Flight numbers: mainline 1-2999, US regional carriers 3000-6999, cargo 1-3999.
    public let numbers: ClosedRange<Int>

    init(_ code: String, _ radio: String, _ home: String, numbers: ClosedRange<Int> = 1...999,
         _ weights: [AircraftCategory: (home: Double, abroad: Double, us: Double)]) {
        self.code = code; self.radio = radio; self.home = home; self.weights = weights; self.numbers = numbers
    }

    /// Weight of this airline for the category at an airport in `country` (ISO 3166 alpha-2, nil if unknown).
    func weight(for category: AircraftCategory, country: String?) -> Double {
        guard let w = weights[category] else { return 0 }
        if country == home { return w.home }
        return country == "US" ? w.us : w.abroad
    }
}

public enum AirlineTable {
    public static let all: [Airline] = [
        // US mainline and low-cost
        Airline("AAL", "American", "US", numbers: 1...2999, [.heavy: (4, 2, 0), .narrowbody: (6, 0, 0)]),
        Airline("DAL", "Delta", "US", numbers: 1...2999, [.heavy: (4, 1, 0), .narrowbody: (6, 0, 0)]),
        Airline("UAL", "United", "US", numbers: 1...2999, [.heavy: (4, 1, 0), .narrowbody: (6, 0, 0)]),
        Airline("SWA", "Southwest", "US", numbers: 1...2999, [.narrowbody: (7, 0, 0)]),
        Airline("JBU", "JetBlue", "US", numbers: 1...2999, [.narrowbody: (3, 0.5, 0)]),
        Airline("ASA", "Alaska", "US", numbers: 1...2999, [.narrowbody: (3, 0, 0)]),
        Airline("NKS", "Spirit Wings", "US", numbers: 1...2999, [.narrowbody: (2, 0, 0)]),
        Airline("FFT", "Frontier Flight", "US", numbers: 1...2999, [.narrowbody: (2, 0, 0)]),
        Airline("AAY", "Allegiant", "US", numbers: 1...2999, [.narrowbody: (1, 0, 0)]),
        Airline("HAL", "Hawaiian", "US", numbers: 1...999, [.heavy: (0.5, 0, 0), .narrowbody: (0.5, 0, 0)]),
        Airline("SCX", "Sun Country", "US", numbers: 1...999, [.narrowbody: (1, 0, 0)]),
        // US cargo
        Airline("FDX", "FedEx", "US", numbers: 1...3999, [.heavy: (2, 1, 0)]),
        Airline("UPS", "UPS", "US", numbers: 1...3999, [.heavy: (2, 1, 0)]),
        // US regionals (operate for the majors)
        Airline("SKW", "SkyWest", "US", numbers: 3000...6999, [.regional: (4, 0, 0)]),
        Airline("RPA", "Brickyard", "US", numbers: 3000...6999, [.regional: (3, 0, 0)]),
        Airline("EDV", "Endeavor", "US", numbers: 3000...6999, [.regional: (3, 0, 0)]),
        Airline("ENY", "Envoy", "US", numbers: 3000...6999, [.regional: (3, 0, 0)]),
        Airline("JIA", "Blue Streak", "US", numbers: 3000...6999, [.regional: (2, 0, 0)]),
        Airline("PDT", "Piedmont", "US", numbers: 3000...6999, [.regional: (2, 0, 0)]),
        Airline("ASH", "Air Shuttle", "US", numbers: 3000...6999, [.regional: (2, 0, 0)]),
        Airline("GJS", "Lindbergh", "US", numbers: 3000...6999, [.regional: (1, 0, 0)]),
        Airline("QXE", "Horizon Air", "US", numbers: 3000...6999, [.regional: (1, 0, 0)]),
        // Ireland, UK and Europe
        Airline("EIN", "Shamrock", "IE", [.heavy: (2, 2, 2), .narrowbody: (3, 0.5, 0.5), .regional: (3, 1, 0)]),
        Airline("RYR", "Ryanair", "IE", [.narrowbody: (5, 1, 0)]),
        Airline("BAW", "Speedbird", "GB", [.heavy: (3, 3, 3), .narrowbody: (2, 2, 0), .regional: (1, 1, 0)]),
        Airline("VIR", "Virgin", "GB", [.heavy: (1, 1, 1)]),
        Airline("EZY", "Easy", "GB", [.narrowbody: (2, 2, 0)]),
        Airline("DLH", "Lufthansa", "DE", [.heavy: (2, 1, 2), .narrowbody: (1, 1, 0)]),
        Airline("AFR", "Airfrans", "FR", [.heavy: (1, 1, 1), .narrowbody: (1, 1, 0)]),
        Airline("KLM", "KLM", "NL", [.heavy: (1, 1, 1), .narrowbody: (1, 1, 0), .regional: (1, 1, 0)]),
        Airline("IBE", "Iberia", "ES", [.heavy: (0.5, 0.5, 0.5), .narrowbody: (1, 1, 0)]),
        Airline("VLG", "Vueling", "ES", [.narrowbody: (1, 1, 0)]),
        Airline("SAS", "Scandinavian", "SE", [.heavy: (0.5, 0.5, 0.5), .narrowbody: (1, 1, 0), .regional: (1, 1, 0)]),
        Airline("SWR", "Swiss", "CH", [.heavy: (1, 1, 1), .narrowbody: (1, 1, 0)]),
        Airline("AUA", "Austrian", "AT", [.heavy: (0.5, 0.5, 0.5), .narrowbody: (1, 1, 0)]),
        Airline("TAP", "Air Portugal", "PT", [.heavy: (0.5, 0.5, 0.5), .narrowbody: (1, 1, 0.5)]),
        Airline("LOT", "Lot", "PL", [.heavy: (0.5, 0.5, 0.5), .narrowbody: (1, 1, 0)]),
        Airline("FIN", "Finnair", "FI", [.heavy: (0.5, 0.5, 0.5), .narrowbody: (1, 1, 0)]),
        Airline("ICE", "Icelandair", "IS", [.narrowbody: (1, 1, 1)]),
        Airline("THY", "Turkish", "TR", [.heavy: (1.5, 1.5, 1.5), .narrowbody: (1, 1, 0)]),
        Airline("NOZ", "Nor Shuttle", "NO", [.narrowbody: (1, 1, 0)]),
        // Middle East, Africa, Asia-Pacific (long haul to the US and Europe)
        Airline("UAE", "Emirates", "AE", [.heavy: (2, 2, 2)]),
        Airline("QTR", "Qatari", "QA", [.heavy: (1, 1, 1)]),
        Airline("ETD", "Etihad", "AE", [.heavy: (1, 1, 1)]),
        Airline("ELY", "El Al", "IL", [.heavy: (0.5, 0.5, 0.5)]),
        Airline("ETH", "Ethiopian", "ET", [.heavy: (0.5, 0.5, 0.5)]),
        Airline("SIA", "Singapore", "SG", [.heavy: (1, 1, 1)]),
        Airline("CPA", "Cathay", "HK", [.heavy: (1, 1, 1)]),
        Airline("JAL", "Japan Air", "JP", [.heavy: (1, 1, 1)]),
        Airline("ANA", "All Nippon", "JP", [.heavy: (1, 1, 1)]),
        Airline("KAL", "Korean Air", "KR", [.heavy: (1, 1, 1)]),
        Airline("AAR", "Asiana", "KR", [.heavy: (0.5, 0.5, 0.5)]),
        Airline("EVA", "Eva", "TW", [.heavy: (1, 1, 1)]),
        Airline("CAL", "Dynasty", "TW", [.heavy: (0.5, 0.5, 0.5)]),
        Airline("CCA", "Air China", "CN", [.heavy: (0.5, 0.5, 0.5)]),
        Airline("AIC", "Air India", "IN", [.heavy: (1, 1, 1)]),
        Airline("QFA", "Qantas", "AU", [.heavy: (1, 1, 1)]),
        Airline("ANZ", "New Zealand", "NZ", [.heavy: (0.5, 0.5, 0.5)]),
        // Canada and Latin America
        Airline("ACA", "Air Canada", "CA", [.heavy: (1.5, 1.5, 1.5), .narrowbody: (2, 0.5, 2), .regional: (0, 0, 0)]),
        Airline("WJA", "Westjet", "CA", [.narrowbody: (1, 0.5, 1)]),
        Airline("AMX", "Aeromexico", "MX", [.heavy: (0.5, 0.5, 0.5), .narrowbody: (1, 0, 1)]),
        Airline("VOI", "Volaris", "MX", [.narrowbody: (0.5, 0, 0.5)]),
        Airline("AVA", "Avianca", "CO", [.heavy: (0.5, 0.5, 0.5), .narrowbody: (0.5, 0, 0.5)]),
        Airline("CMP", "Copa", "PA", [.narrowbody: (0.5, 0, 1)]),
        Airline("LAN", "Lan", "CL", [.heavy: (0.5, 0.5, 0.5)]),
        Airline("AZU", "Azul", "BR", [.heavy: (0.3, 0.3, 0.3)]),
    ]

    /// Radio telephony name by designator.
    public static let radioNames: [String: String] = Dictionary(uniqueKeysWithValues: all.map { ($0.code, $0.radio) })

    /// (airline, weight) pairs for a category at an airport in `country`.
    static func airlines(for category: AircraftCategory, country: String?) -> [(Airline, Double)] {
        all.compactMap { airline in
            let w = airline.weight(for: category, country: country)
            return w > 0 ? (airline, w) : nil
        }
    }
}
