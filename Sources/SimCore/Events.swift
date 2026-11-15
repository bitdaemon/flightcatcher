import Foundation

/// How often random events happen, as a percentage of generated arrivals. Each arrival is rolled once at spawn and has
/// at most one event. All zero (the default here) means no events, so tests and scripted scenarios stay in control.
public struct EventSettings: Equatable, Codable {
    /// Go-around because the pilot is not happy with the approach.
    public var pilotGoAroundPercent: Double
    /// Go-around because of a windshear alert on final.
    public var windshearPercent: Double
    /// The aircraft declares an emergency some minutes after entering the area.
    public var emergencyPercent: Double

    public init(pilotGoAroundPercent: Double = 0, windshearPercent: Double = 0, emergencyPercent: Double = 0) {
        self.pilotGoAroundPercent = pilotGoAroundPercent
        self.windshearPercent = windshearPercent
        self.emergencyPercent = emergencyPercent
    }

    /// What the app starts with.
    public static let gameDefault = EventSettings(pilotGoAroundPercent: 3, windshearPercent: 2, emergencyPercent: 2)
}

public enum EmergencyKind: String, Codable, CaseIterable, Equatable {
    case engineFailure, medical, lowFuel, hydraulicFailure, smoke, birdStrike, depressurisation, gearProblem

    /// MAYDAY for a threat to the aircraft or everyone on board, PAN PAN for an urgent but not immediate problem.
    public var urgencyWord: String {
        switch self {
        case .medical, .lowFuel, .birdStrike, .gearProblem: return "PAN PAN"
        case .engineFailure, .hydraulicFailure, .smoke, .depressurisation: return "MAYDAY"
        }
    }

    public var phrase: String {
        switch self {
        case .engineFailure: return "engine failure"
        case .medical: return "medical emergency on board"
        case .lowFuel: return "low fuel"
        case .hydraulicFailure: return "hydraulic failure"
        case .smoke: return "smoke in the cabin"
        case .birdStrike: return "bird strike"
        case .depressurisation: return "loss of pressurisation"
        case .gearProblem: return "unsafe landing gear indication"
        }
    }

    /// What the pilot asks for after declaring.
    public var request: String {
        switch self {
        case .depressurisation: return "descending to ten thousand feet, request vectors for immediate landing"
        case .gearProblem: return "request vectors, we need time to run the checklist"
        case .lowFuel: return "request direct routing and priority landing"
        default: return "request vectors for immediate landing"
        }
    }
}

/// An event decided at spawn and carried out when its trigger is reached.
public enum PlannedEvent: Equatable {
    /// Pilot's decision to go around, when the aircraft is on the glidepath inside `triggerNM`.
    case pilotGoAround(reason: String, triggerNM: Double)
    /// Windshear alert on the glidepath inside `triggerNM`.
    case windshear(triggerNM: Double)
    /// Emergency declared once the simulation clock reaches `atTick`.
    case emergency(kind: EmergencyKind, atTick: Int)
}
