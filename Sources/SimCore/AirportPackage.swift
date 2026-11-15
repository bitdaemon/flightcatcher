import Foundation

/// One airport as the game loads it. Produced offline from the AIP; the game never parses raw AIP text.
public struct AirportPackage: Codable, Equatable {
    public var schemaVersion: Int
    public var icao: String
    public var name: String
    public var dataSource: String
    public var transitionAltitudeFt: Int
    public var runways: [Runway]
    public var fixes: [Fix]
    public var procedures: [Procedure]
    public var holds: [Hold]
    /// Aerodrome elevation in feet (AIP AD 2.2). Optional so older packages still load.
    public var elevationFt: Int?
    /// Where the airport is, for display. Optional so older packages still load.
    public var city: String?
    public var region: String?
    public var country: String?
    public var iata: String?

    /// "Boston (KBOS)": the city first, the code second. Falls back to the airport name.
    public var title: String { AirportLabel.title(city: city, name: name, icao: icao) }

    public init(schemaVersion: Int, icao: String, name: String, dataSource: String,
                transitionAltitudeFt: Int, runways: [Runway], fixes: [Fix],
                procedures: [Procedure], holds: [Hold]) {
        self.schemaVersion = schemaVersion
        self.icao = icao
        self.name = name
        self.dataSource = dataSource
        self.transitionAltitudeFt = transitionAltitudeFt
        self.runways = runways
        self.fixes = fixes
        self.procedures = procedures
        self.holds = holds
    }
}

public struct Runway: Codable, Equatable {
    public var id: String                 // "28L"
    public var trueBearingDeg: Double
    public var lengthM: Int
    public var widthM: Int
    public var surface: String
    public var thresholdLat: Double       // decimal degrees, north positive
    public var thresholdLon: Double       // decimal degrees, east positive
    public var thresholdElevationFt: Int
    public var toraM: Int
    public var todaM: Int
    public var asdaM: Int
    public var ldaM: Int
    public var ils: ILS?
}

public struct ILS: Codable, Equatable {
    public var ident: String
    public var category: String
    public var localiserMHz: Double
    public var glidepathDeg: Double
    public var thresholdCrossingHeightFt: Int
}

public struct Fix: Codable, Equatable {
    public var id: String
    public var lat: Double
    public var lon: Double
}

public enum ProcedureKind: String, Codable {
    case sid, star, approach
}

/// The kind of final approach. Packages written before RNAV approaches were imported have no type: those are ILS.
public enum ApproachType: String, Codable {
    case ils, rnav, rnp

    /// From the CIFP-style procedure ID: "I27" is ILS, "R27" RNAV (GPS), "H33LX" RNAV (RNP).
    public init(procedureId: String) {
        switch procedureId.first {
        case "R"?: self = .rnav
        case "H"?: self = .rnp
        default: self = .ils
        }
    }

    /// As said on the radio: "cleared RNAV approach runway 27".
    public var spoken: String {
        switch self {
        case .ils: return "ILS"
        case .rnav: return "RNAV"
        case .rnp: return "RNAV RNP"
        }
    }
}

public enum AltitudeConstraintKind: String, Codable {
    case at, atOrAbove, atOrBelow
    /// A window: `feet` is the lower limit and `upperFeet` the upper.
    case between
}

public struct AltitudeConstraint: Codable, Equatable {
    public var kind: AltitudeConstraintKind
    public var feet: Int
    public var upperFeet: Int?

    public init(kind: AltitudeConstraintKind, feet: Int, upperFeet: Int? = nil) {
        self.kind = kind
        self.feet = feet
        self.upperFeet = upperFeet
    }
}

public struct Leg: Codable, Equatable {
    public var fixId: String
    public var altitude: AltitudeConstraint?
    public var maxSpeedKt: Int?

    public init(fixId: String, altitude: AltitudeConstraint? = nil, maxSpeedKt: Int? = nil) {
        self.fixId = fixId
        self.altitude = altitude
        self.maxSpeedKt = maxSpeedKt
    }
}

public struct Procedure: Codable, Equatable {
    public var id: String                 // "NIMAT3L"
    public var kind: ProcedureKind
    public var runways: [String]
    public var legs: [Leg]
    /// Approaches only.
    public var missedApproach: [Leg]?
    public var note: String?
    /// Approaches only. Nil means ILS.
    public var approachType: ApproachType?
    /// Approaches only: the published vertical path angle of an RNAV approach (nil: 3 degrees).
    public var glidepathDeg: Double?

    /// The type of an approach, ILS when the package does not say.
    public var finalApproachType: ApproachType { approachType ?? .ils }

    public init(id: String, kind: ProcedureKind, runways: [String], legs: [Leg],
                missedApproach: [Leg]? = nil, note: String? = nil,
                approachType: ApproachType? = nil, glidepathDeg: Double? = nil) {
        self.approachType = approachType
        self.glidepathDeg = glidepathDeg
        self.id = id
        self.kind = kind
        self.runways = runways
        self.legs = legs
        self.missedApproach = missedApproach
        self.note = note
    }
}

public enum TurnDirection: String, Codable {
    case left, right
}

public struct Hold: Codable, Equatable {
    public var fixId: String
    public var inboundMagneticDeg: Int
    public var turn: TurnDirection
    public var maxSpeedKt: Int
    public var minAltitudeFt: Int
    public var maxLevelFt: Int
    public var outboundMinutes: Double
}

// MARK: - Loading and validation

public enum AirportPackageError: Error, Equatable {
    case resourceNotFound(String)
}

extension AirportPackage {
    /// Local projection centred on the mean of the runway thresholds. The scope and the simulation share it.
    public var referenceProjection: LocalProjection {
        guard !runways.isEmpty else { return LocalProjection(originLat: 0, originLon: 0) }
        let n = Double(runways.count)
        return LocalProjection(originLat: runways.map(\.thresholdLat).reduce(0, +) / n,
                               originLon: runways.map(\.thresholdLon).reduce(0, +) / n)
    }

    public static func decode(from data: Data) throws -> AirportPackage {
        try JSONDecoder().decode(AirportPackage.self, from: data)
    }

    /// Lower-case names of the packages bundled with SimCore, sorted, for example ["kbos", "kjfk"].
    public static func bundledNames() -> [String] {
        let urls = Bundle.module.urls(forResourcesWithExtension: "json", subdirectory: "Resources/Airports") ?? []
        return urls.map { $0.deletingPathExtension().lastPathComponent }
            .filter { $0 != "airports-index" }.sorted()
    }

    /// Load a package bundled with SimCore, for example `loadBundled("kbos")`.
    public static func loadBundled(_ name: String) throws -> AirportPackage {
        guard let url = Bundle.module.url(forResource: name, withExtension: "json",
                                          subdirectory: "Resources/Airports") else {
            throw AirportPackageError.resourceNotFound(name)
        }
        return try decode(from: Data(contentsOf: url))
    }

    /// Returns human-readable problems; an empty array means the package is consistent.
    public func validate() -> [String] {
        var problems: [String] = []

        func duplicates(_ ids: [String]) -> [String] {
            Dictionary(grouping: ids, by: { $0 }).filter { $0.value.count > 1 }.keys.sorted()
        }
        for d in duplicates(runways.map(\.id)) { problems.append("duplicate runway \(d)") }
        for d in duplicates(fixes.map(\.id)) { problems.append("duplicate fix \(d)") }
        for d in duplicates(procedures.map(\.id)) { problems.append("duplicate procedure \(d)") }

        let runwayIds = Set(runways.map(\.id))
        let fixIds = Set(fixes.map(\.id))

        for p in procedures {
            for r in p.runways where !runwayIds.contains(r) {
                problems.append("procedure \(p.id) references unknown runway \(r)")
            }
            for leg in p.legs where !fixIds.contains(leg.fixId) {
                problems.append("procedure \(p.id) references unknown fix \(leg.fixId)")
            }
            if p.legs.isEmpty { problems.append("procedure \(p.id) has no legs") }
            for leg in p.missedApproach ?? [] where !fixIds.contains(leg.fixId) {
                problems.append("procedure \(p.id) missed approach references unknown fix \(leg.fixId)")
            }
            if p.kind == .approach, p.finalApproachType == .ils {
                for r in p.runways where runways.first(where: { $0.id == r })?.ils == nil {
                    problems.append("approach \(p.id) needs an ILS on runway \(r)")
                }
            }
        }
        for h in holds where !fixIds.contains(h.fixId) {
            problems.append("hold references unknown fix \(h.fixId)")
        }
        for r in runways where !(0.0..<360.0).contains(r.trueBearingDeg) {
            problems.append("runway \(r.id) bearing out of range")
        }
        return problems
    }
}

// MARK: - Airport index

public enum AirportLabel {
    public static func title(city: String?, name: String, icao: String) -> String {
        let place = (city?.isEmpty == false) ? city! : name
        return "\(place) (\(icao))"
    }
}

/// One line of `airports-index.json`: enough to list and search airports without loading every package.
public struct AirportIndexEntry: Codable, Equatable, Identifiable {
    public var icao: String
    public var name: String
    public var city: String?
    public var region: String?
    public var country: String?
    public var iata: String?
    public var ilsRunways: Int
    public var stars: Int
    public var sids: Int
    public var approaches: Int

    public var id: String { icao }
    /// Lower-case resource name, "kbos".
    public var resourceName: String { icao.lowercased() }
    public var title: String { AirportLabel.title(city: city, name: name, icao: icao) }
    /// "Airport name, MA US" style second line.
    public var subtitle: String {
        let place = [region, country].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
        return place.isEmpty ? name : "\(name), \(place)"
    }

    /// Case-insensitive match on city, name, ICAO, IATA, region.
    public func matches(_ query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        if q.isEmpty { return true }
        return [city, name, icao, iata, region, country].compactMap { $0?.lowercased() }.contains { $0.contains(q) }
    }
}

public enum AirportIndex {
    /// The bundled index, sorted by city. Falls back to bare entries built from the package file names if the index is missing.
    public static func loadBundled() -> [AirportIndexEntry] {
        if let url = Bundle.module.url(forResource: "airports-index", withExtension: "json",
                                       subdirectory: "Resources/Airports"),
           let data = try? Data(contentsOf: url),
           let entries = try? JSONDecoder().decode([AirportIndexEntry].self, from: data), !entries.isEmpty {
            // Only airports whose package is really bundled.
            let available = Set(AirportPackage.bundledNames())
            let present = entries.filter { available.contains($0.resourceName) }
            if !present.isEmpty { return present }
        }
        return AirportPackage.bundledNames().map {
            AirportIndexEntry(icao: $0.uppercased(), name: $0.uppercased(), ilsRunways: 0, stars: 0, sids: 0, approaches: 0)
        }
    }
}
