import Foundation

/// A controller instruction. Levels are stored in feet; headings 1...360.
/// A heading without a turn direction means the pilot takes the shorter way.
public indirect enum Command: Equatable {
    case descend(feet: Int)
    case climb(feet: Int)
    case heading(degrees: Int, turn: TurnDirection? = nil)
    case speed(knots: Int)
    /// Cleared ILS approach. Issued with the mouse, not the command bar.
    case approach(runway: String)
    /// Cleared visual approach to a runway that has no ILS (the simulation turns `.approach` into this
    /// automatically for such runways).
    case visualApproach(runway: String)
    /// Proceed direct to a fix. If the fix is on the aircraft's route it keeps the rest of the route; otherwise it
    /// picks up a STAR or approach that contains the fix, or just flies to the fix and holds that heading.
    case direct(fix: String)
    /// Proceed direct to each fix in order (two or more fixes; one fix is `.direct`).
    case route(fixes: [String])
    /// Cross a fix on the route at an altitude: the pilot keeps the present level, then leaves it late enough to be at
    /// `altitudeFt` over the fix.
    case cross(fix: String, altitudeFt: Int)
    /// Fly the named approach from its first fix and join it: direct to `via`, then the approach legs, cleared ILS.
    case joinApproach(procedure: String, runway: String, via: String)
    /// A heading, altitude or speed instruction flown faster: steeper turn, higher rate of climb or descent,
    /// quicker acceleration or deceleration. Other instructions cannot be expedited.
    case expedite(Command)
    /// Cancel the route, crossing restriction, expedites and an approach still being intercepted, and keep the present
    /// heading, altitude and speed.
    case maintain
    /// Departures: line up on the runway and wait.
    case lineUp
    /// Departures: cleared for take-off from the holding point or from the line-up position.
    case takeoff
    /// Departures: change to the next controller. The aircraft leaves the simulation.
    case handoff

    /// Short text for the command-bar preview.
    public var summary: String {
        switch self {
        case .descend(let feet): return "descend to \(feet) ft"
        case .climb(let feet): return "climb to \(feet) ft"
        case .heading(let degrees, let turn):
            let word = turn.map { "turn \($0.rawValue) heading" } ?? "fly heading"
            return "\(word) \(Phraseology.pad3(degrees))"
        case .speed(let knots): return "speed \(knots) kt"
        case .approach(let runway): return "cleared ILS approach runway \(runway)"
        case .visualApproach(let runway): return "cleared visual approach runway \(runway)"
        case .direct(let fix): return "proceed direct \(fix)"
        case .route(let fixes): return "proceed direct " + fixes.joined(separator: ", then ")
        case .cross(let fix, let feet): return "cross \(fix) at \(feet) ft"
        case .joinApproach(let procedure, let runway, let via):
            return "proceed direct \(via), cleared \(ApproachType(procedureId: procedure).spoken) approach runway \(runway) (\(procedure))"
        case .expedite(let inner): return "expedite: " + inner.summary
        case .maintain: return "maintain present heading, altitude and speed"
        case .lineUp: return "line up and wait"
        case .takeoff: return "cleared for take-off"
        case .handoff: return "contact the next controller (tower for an arrival)"
        }
    }
}

/// Placeholder limits until real minimum vectoring altitudes and OpenAP speed envelopes are modelled.
public enum CommandLimits {
    public static let minimumLevelFt = 2000
    /// Lowest level for an aircraft already cleared for the approach, so it can be put on the glidepath:
    /// field elevation plus 1,000 ft, rounded down to a whole thousand.
    public static func approachFloorFt(fieldElevationFt: Int) -> Int {
        max(minimumLevelFt, ((fieldElevationFt + 1000) / 1000) * 1000)
    }
    /// Lowest level the controller can assign at an airport: field elevation plus 2,000 ft, rounded up to a whole thousand.
    public static func floorFt(fieldElevationFt: Int) -> Int {
        max(minimumLevelFt, ((fieldElevationFt + 2000 + 999) / 1000) * 1000)
    }
    public static let maximumLevelFt = 41000
    public static let minimumSpeedKt = 120
    public static let maximumSpeedKt = 350
}

extension Command {
    /// Why this command cannot be accepted for the aircraft, or nil if it can.
    public func refusal(for aircraft: Aircraft) -> String? {
        let current = Int(aircraft.altitudeFt.rounded())
        if aircraft.handedToTower { return "\(aircraft.callsign) is with the tower" }
        if aircraft.isOnGround {
            switch self {
            case .lineUp, .takeoff: break
            default: return "aircraft is on the ground"
            }
        }
        switch self {
        case .descend(let feet):
            if feet < aircraft.effectiveLevelFloorFt { return "\(feet) ft is below the minimum altitude, \(aircraft.effectiveLevelFloorFt) ft" }
            if feet >= current { return "\(feet) ft is not below the aircraft (\(current) ft)" }
        case .climb(let feet):
            let ceiling = aircraft.type?.ceilingFt ?? CommandLimits.maximumLevelFt
            if feet > ceiling { return "level \(feet) ft is above the \(ceiling) ft ceiling" }
            if feet <= current { return "\(feet) ft is not above the aircraft (\(current) ft)" }
        case .heading(let degrees, _):
            if !(1...360).contains(degrees) { return "heading must be 0 to 360" }
        case .speed(let knots):
            let low = aircraft.type?.minSpeedKt ?? CommandLimits.minimumSpeedKt
            let high = aircraft.type?.maxSpeedKt ?? CommandLimits.maximumSpeedKt
            if !(low...high).contains(knots) {
                return "speed must be \(low) to \(high) kt" + (aircraft.typeCode.map { " for a \($0)" } ?? "")
            }
        case .route(let fixes):
            if fixes.count < 2 { return "a route needs at least two fixes" }
        case .cross(_, let feet):
            let ceiling = aircraft.type?.ceilingFt ?? CommandLimits.maximumLevelFt
            if feet < aircraft.effectiveLevelFloorFt { return "\(feet) ft is below the minimum altitude, \(aircraft.effectiveLevelFloorFt) ft" }
            if feet > ceiling { return "level \(feet) ft is above the \(ceiling) ft ceiling" }
        case .lineUp:
            if aircraft.groundPhase != .holdingShort { return "not holding short of a runway" }
        case .takeoff:
            if aircraft.groundPhase != .holdingShort && aircraft.groundPhase != .linedUp {
                return "not holding short or lined up"
            }
        case .handoff:
            if let d = aircraft.departure {
                let at = Int(aircraft.altitudeFt.rounded())
                if at < d.handoffAltitudeFt { return "climbing through \(at) ft, handoff at \(d.handoffAltitudeFt) ft" }
                if Int(aircraft.targetAltitudeFt.rounded()) < d.expectedLevelFt {
                    return "not cleared to its plan level, \(d.expectedLevelFt) ft"
                }
            } else {
                // An arrival goes to the tower once it is established on the localiser.
                guard let approach = aircraft.approach, approach.phase != .intercepting else {
                    return "not established on the localiser"
                }
                if approach.phase == .localiser {
                    let p = approach.ils.position(eastNM: aircraft.eastNM, northNM: aircraft.northNM)
                    let beam = approach.ils.glidepathAltitudeFt(distanceNM: max(p.along, 0))
                    if aircraft.altitudeFt > beam + 300 {
                        return "\(Int((aircraft.altitudeFt - beam).rounded())) ft above the glidepath, descend first"
                    }
                }
            }
        case .maintain:
            if let phase = aircraft.approach?.phase, phase != .intercepting {
                return "established on the approach, give a heading to break off"
            }
        case .approach, .visualApproach, .direct, .joinApproach:
            break // availability depends on the airport data; the simulation checks it
        case .expedite(let inner):
            switch inner {
            case .descend, .climb, .heading, .speed: return inner.refusal(for: aircraft)
            default: return "only heading, altitude and speed can be expedited"
            }
        }
        return nil
    }
}
