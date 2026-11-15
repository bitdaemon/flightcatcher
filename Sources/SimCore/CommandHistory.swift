import Foundation

/// One instruction that was accepted for an aircraft. The pilot starts complying at `executeAtTick`.
public struct CommandRecord: Equatable, Identifiable {
    public let id: Int
    public let callsign: String
    public let command: Command
    public let issuedTick: Int
    public let executeAtTick: Int

    /// Short label such as "ALT 5000", "HDG 270L", "DCT KERAV›PIZSA", "X KERAV 5000".
    public var label: String { command.chipLabel }

    /// True while the pilot has not yet started complying.
    public func isPending(at tick: Int) -> Bool { tick < executeAtTick }
}
