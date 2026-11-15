import SwiftUI
import SimCore

/// Where each aircraft's track tag sits relative to its symbol. Tags the user dragged are "manual": automatic
/// decluttering leaves them where they were put.
@MainActor
final class TagModel: ObservableObject {
    @Published private(set) var offsets: [String: CGPoint] = [:]
    private(set) var manual: Set<String> = []
    private(set) var dragging: String?
    private var dragBase = CGPoint.zero
    /// Incremented to ask the scope to rearrange every tag now.
    @Published private(set) var declutterRequest = 0

    func offset(for callsign: String) -> CGPoint { offsets[callsign] ?? TagPlacement.defaultOffset }

    func beginDrag(_ callsign: String) {
        dragging = callsign
        dragBase = offset(for: callsign)
        manual.insert(callsign)
    }

    func drag(by translation: CGSize) {
        guard let callsign = dragging else { return }
        offsets[callsign] = CGPoint(x: dragBase.x + translation.width, y: dragBase.y + translation.height)
    }

    func endDrag() { dragging = nil }

    func apply(_ placed: [String: CGPoint]) {
        for (callsign, offset) in placed where offsets[callsign] != offset { offsets[callsign] = offset }
    }

    func prune(present: Set<String>) {
        if offsets.keys.contains(where: { !present.contains($0) }) {
            offsets = offsets.filter { present.contains($0.key) }
        }
        manual = manual.intersection(present)
    }

    /// Forget every manual position (used before a full declutter).
    func releaseAll() { manual = [] }

    func requestDeclutter() { declutterRequest += 1 }

    func reset() {
        offsets = [:]
        manual = []
        dragging = nil
    }
}
