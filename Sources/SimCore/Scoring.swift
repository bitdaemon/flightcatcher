import Foundation

// Scoring: points for moving traffic safely and efficiently, penalties for unsafe or wasteful control. The simulation
// adds `ScoreEvent`s as things happen; the card keeps them so the debrief can explain every point.

/// The groups shown in the debrief breakdown.
public enum ScoreCategory: String, CaseIterable, Codable, Identifiable {
    case arrivals, departures, efficiency, emergencies, safety, control, delays

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .arrivals: return "Arrivals"
        case .departures: return "Departures"
        case .efficiency: return "Efficiency"
        case .emergencies: return "Emergencies"
        case .safety: return "Separation"
        case .control: return "Control"
        case .delays: return "Delays"
        }
    }
}

/// Every scored event. Points are in `ScoreRules.points`.
public enum ScoreKind: String, CaseIterable, Codable {
    case arrivalHandoff, landed, departureHandoff, departureAtPlanLevel, emergencyLanded, efficiency
    case lossOfSeparation, lossContinues, conflictAlert, goAroundCaused, missedHandoff, routeEndedNoClearance
    case refused, departureDelay, runwayHeadingUnvectored, emergencyIgnored

    public var category: ScoreCategory {
        switch self {
        case .arrivalHandoff, .landed: return .arrivals
        case .departureHandoff, .departureAtPlanLevel, .missedHandoff: return .departures
        case .efficiency: return .efficiency
        case .emergencyLanded, .emergencyIgnored: return .emergencies
        case .lossOfSeparation, .lossContinues, .conflictAlert: return .safety
        case .goAroundCaused, .routeEndedNoClearance, .refused, .runwayHeadingUnvectored: return .control
        case .departureDelay: return .delays
        }
    }

    public var title: String {
        switch self {
        case .arrivalHandoff: return "arrival handed to tower"
        case .landed: return "landed"
        case .departureHandoff: return "departure handed off"
        case .departureAtPlanLevel: return "cleared to plan level"
        case .emergencyLanded: return "emergency landed"
        case .efficiency: return "efficient arrival"
        case .lossOfSeparation: return "loss of separation"
        case .lossContinues: return "loss of separation continues"
        case .conflictAlert: return "conflict alert"
        case .goAroundCaused: return "go-around"
        case .missedHandoff: return "left the area without a handoff"
        case .routeEndedNoClearance: return "route ended without a clearance"
        case .refused: return "instruction refused"
        case .departureDelay: return "departure waiting"
        case .runwayHeadingUnvectored: return "departure not vectored"
        case .emergencyIgnored: return "emergency waiting for a clearance"
        }
    }
}

/// The points table and the limits behind the time-based rules. Tune here.
public enum ScoreRules {
    public static let points: [ScoreKind: Int] = [
        .arrivalHandoff: 100, .landed: 20, .departureHandoff: 80, .departureAtPlanLevel: 20, .emergencyLanded: 30,
        .efficiency: 30, // the most; scaled down by `efficiencyBonus`
        .lossOfSeparation: -300, .lossContinues: -50, .conflictAlert: -10, .goAroundCaused: -100,
        .missedHandoff: -150, .routeEndedNoClearance: -50, .refused: -5, .departureDelay: -1,
        .runwayHeadingUnvectored: -20, .emergencyIgnored: -50,
    ]
    /// A loss of separation costs `lossContinues` again for every this many seconds it lasts.
    public static let lossStepSeconds = 10
    /// A departure may wait this long at the holding point before it costs a point a minute.
    public static let departureGraceSeconds = 180
    /// A runway-heading departure still not vectored this far from the airport costs points once.
    public static let runwayHeadingLimitNM = 10.0
    /// An emergency aircraft given no instruction for this long after declaring costs points once.
    public static let emergencyWaitSeconds = 120
    /// Changes of this size or more are announced on the radio.
    public static let announceAtPoints = 100

    /// Efficiency bonus from actual time against the clean time: full up to 1.2 times, none from 2 times.
    public static func efficiencyBonus(actualSeconds: Double, cleanSeconds: Double) -> Int {
        guard cleanSeconds > 0 else { return 0 }
        let ratio = actualSeconds / cleanSeconds
        let best = Double(points[.efficiency] ?? 30)
        if ratio <= 1.2 { return Int(best) }
        if ratio >= 2.0 { return 0 }
        return Int((best * (2.0 - ratio) / 0.8).rounded())
    }

    /// Clean time for an arrival: the straight distance from where it was handed in to the threshold, times 1.3 for a
    /// sensible path, at 210 kt.
    public static func cleanSeconds(distanceNM: Double) -> Double { distanceNM * 1.3 / 210 * 3600 }

    /// Go-arounds that are not the controller's fault cost nothing.
    public static func isControllerGoAround(reason: String) -> Bool {
        !(reason.hasPrefix("pilot's decision") || reason.hasPrefix("windshear"))
    }
}

public struct ScoreEvent: Identifiable, Codable, Equatable {
    public var id: Int
    public var tick: Int
    public var kind: ScoreKind
    public var points: Int
    public var callsign: String?
    public var detail: String

    /// "+100 arrival handed to tower AAL123" or "−300 loss of separation AAL2972 / N535".
    public var text: String {
        let sign = points >= 0 ? "+\(points)" : "\u{2212}\(-points)"
        let who = detail.isEmpty ? (callsign ?? "") : detail
        return who.isEmpty ? "\(sign) \(kind.title)" : "\(sign) \(kind.title) \(who)"
    }
}

/// One line per minute for the debrief chart.
public struct ScoreSample: Codable, Equatable {
    public var minute: Int
    public var rawScore: Int
    public var arrivalsPerHour: Double
    public var departuresPerHour: Double
}

/// How long an arrival took from hand-in to handoff, against its clean time.
public struct ArrivalTiming: Codable, Equatable {
    public var callsign: String
    public var actualSeconds: Int
    public var cleanSeconds: Int
    public var bonus: Int
    public var instructions: Int
}

public enum ScoreGrade: String, Codable, CaseIterable {
    case a = "A", b = "B", c = "C", d = "D", e = "E"

    public var rank: String {
        switch self {
        case .a: return "Supervisor"
        case .b: return "Senior controller"
        case .c: return "Controller"
        case .d: return "Trainee"
        case .e: return "Removed from position"
        }
    }
}

/// A session's score: every event, plus what the debrief shows.
public struct ScoreCard: Codable, Equatable {
    public var events: [ScoreEvent] = []
    /// Sum of all points before the multiplier.
    public private(set) var raw = 0
    /// Difficulty multiplier from the traffic and weather of the session so far.
    public var multiplier = 1.0
    public var samples: [ScoreSample] = []
    public var arrivals: [ArrivalTiming] = []
    public var arrivalsHandled = 0
    public var departuresHandled = 0
    public var losses = 0
    public var controllerGoArounds = 0
    public var missedHandoffs = 0
    public var instructions = 0
    public var startTick = 0
    /// Set when the session is ended; nil while it runs.
    public var endTick: Int?

    public init(startTick: Int = 0) { self.startTick = startTick }

    /// The score shown: raw points times the multiplier.
    public var total: Int { Int((Double(raw) * multiplier).rounded()) }

    mutating func add(_ event: ScoreEvent) {
        events.append(event)
        raw += event.points
    }

    public func points(in category: ScoreCategory) -> Int {
        events.filter { $0.kind.category == category }.reduce(0) { $0 + $1.points }
    }

    public func count(_ kind: ScoreKind) -> Int { events.filter { $0.kind == kind }.count }

    public func durationSeconds(now: Int) -> Int { max(0, (endTick ?? now) - startTick) }

    /// The costly moments, worst first, at most `limit`.
    public func worstMoments(limit: Int = 8) -> [ScoreEvent] {
        Array(events.filter { $0.points <= -50 }.sorted { ($0.points, $0.tick) < ($1.points, $1.tick) }.prefix(limit))
    }

    /// Nil until at least one aircraft has been handled. Quality is raw points against the most the handled aircraft
    /// could have earned (150 an arrival, 100 a departure). One loss of separation caps the grade at C, three at E.
    public var grade: ScoreGrade? {
        let potential = arrivalsHandled * 150 + departuresHandled * 100
        guard potential > 0 else { return nil }
        let quality = Double(raw) / Double(potential)
        var grade: ScoreGrade
        switch quality {
        case 0.85...: grade = .a
        case 0.7..<0.85: grade = .b
        case 0.5..<0.7: grade = .c
        case 0.3..<0.5: grade = .d
        default: grade = .e
        }
        if losses >= 3 { grade = .e } else if losses >= 1, grade == .a || grade == .b { grade = .c }
        return grade
    }

    /// Average instructions per handled arrival, nil with none.
    public var instructionsPerArrival: Double? {
        guard !arrivals.isEmpty else { return nil }
        return Double(arrivals.map(\.instructions).reduce(0, +)) / Double(arrivals.count)
    }
}

/// Difficulty multiplier. Average traffic rate (arrivals plus departures per hour) over 23 sets the base, between 0.5
/// and 2; a variable rate adds 0 to 10% by variation; random events, live weather and gusts add 0.05 each.
public enum ScoreMultiplier {
    public static func value(averageRatePerHour: Double?, variable: Bool, variation: TrafficVariation,
                             events: EventSettings, liveWeather: Bool, gusting: Bool) -> Double {
        var m = averageRatePerHour.map { min(2.0, max(0.5, $0 / 23)) } ?? 1.0
        if variable {
            switch variation {
            case .steady: break
            case .moderate: m *= 1.05
            case .lively: m *= 1.1
            }
        }
        if events.pilotGoAroundPercent > 0 { m += 0.05 }
        if events.windshearPercent > 0 { m += 0.05 }
        if events.emergencyPercent > 0 { m += 0.05 }
        if liveWeather { m += 0.05 }
        if gusting { m += 0.05 }
        return (m * 100).rounded() / 100
    }
}
