import Foundation

/// One line of the simulation's debug log. Written only while debug logging is on; reading the simulation to build
/// these never changes it (no random numbers are drawn and no state is touched).
public struct DebugEntry: Codable, Equatable, Identifiable {
    public let id: Int
    /// Simulation clock, in seconds.
    public let tick: Int
    /// "cmd", "approach", "event", "state".
    public let category: String
    public let callsign: String?
    public let message: String

    public var text: String {
        let clock = String(format: "%02d:%02d", tick / 60, tick % 60)
        return "\(clock)  \((callsign ?? "-").padding(toLength: 8, withPad: " ", startingAt: 0))  \(category.padding(toLength: 8, withPad: " ", startingAt: 0))  \(message)"
    }
}

/// What an arrival cleared for an approach is doing, kept between ticks so the log only reports changes.
struct ApproachTrace {
    var phase: ApproachPhase
    var blocker: String
    var clearedAtTick: Int
    var blockerSinceTick: Int
}
