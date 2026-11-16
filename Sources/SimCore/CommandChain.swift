import Foundation

/// Commands collected for one aircraft before they are sent together (the mouse controls build one of these;
/// the typed command line builds the same thing from a chain such as `ein123 h270l d50 s180`).
/// Choosing a second command of the same kind replaces the first in place, so there is never a conflicting pair.
public struct CommandChain: Equatable {
    public private(set) var callsign: String?
    public private(set) var commands: [Command] = []

    public init() {}

    public var isEmpty: Bool { commands.isEmpty }

    enum Slot: Equatable { case altitude, heading, speed, direct, clearance, crossing(String), handoff, maintain }

    static func slot(of command: Command) -> Slot {
        switch command {
        case .descend, .climb: return .altitude
        case .heading: return .heading
        case .speed: return .speed
        case .direct, .route, .resumeNavigation: return .direct
        case .cross(let fix, _): return .crossing(fix)
        case .approach, .visualApproach, .joinApproach, .lineUp, .takeoff: return .clearance
        case .handoff: return .handoff
        case .maintain: return .maintain
        case .expedite(let inner): return slot(of: inner)
        }
    }

    /// Adds a command. A different aircraft starts a new chain. The same kind of command replaces the earlier one
    /// where it stood; anything else goes on the end.
    public mutating func add(_ command: Command, for callsign: String) {
        if self.callsign != callsign {
            commands = []
            self.callsign = callsign
        }
        let slot = Self.slot(of: command)
        if let index = commands.firstIndex(where: { Self.slot(of: $0) == slot }) {
            commands[index] = command
        } else {
            commands.append(command)
        }
    }

    public mutating func remove(at index: Int) {
        guard commands.indices.contains(index) else { return }
        commands.remove(at: index)
        if commands.isEmpty { callsign = nil }
    }

    public mutating func clear() {
        commands = []
        callsign = nil
    }

    public func issued() -> [IssuedCommand] {
        guard let callsign else { return [] }
        return commands.map { IssuedCommand(callsign: callsign, command: $0) }
    }
}

extension Command {
    /// Short label for a chip: "HDG 270L", "ALT 5000", "SPD 180", "DCT KERAV", "ILS 28L".
    public var chipLabel: String {
        switch self {
        case .descend(let feet), .climb(let feet): return "ALT \(feet)"
        case .heading(let degrees, let turn):
            let suffix = turn.map { $0 == .left ? "L" : "R" } ?? ""
            return "HDG \(Phraseology.pad3(degrees))\(suffix)"
        case .speed(let knots): return "SPD \(knots)"
        case .approach(let runway): return "ILS \(runway)"
        case .visualApproach(let runway): return "VIS \(runway)"
        case .direct(let fix): return "DCT \(fix)"
        case .route(let fixes): return "DCT " + fixes.joined(separator: "›")
        case .cross(let fix, let feet): return "X \(fix) \(feet)"
        case .joinApproach(let procedure, _, _): return "APP \(procedure)"
        case .expedite(let inner): return inner.chipLabel + "!"
        case .lineUp: return "LINE UP"
        case .takeoff: return "TAKE-OFF"
        case .handoff: return "HANDOFF"
        case .maintain: return "MAINT"
        case .resumeNavigation: return "OWN NAV"
        }
    }
}
