import SwiftUI
import AppKit
import SimCore

/// State of the mouse controls: which aircraft is being controlled, which mode the scope is in, and the chips
/// (commands collected but not yet sent). The pure chain logic lives in SimCore's `CommandChain`.
@MainActor
final class ControlModel: ObservableObject {
    enum Mode: Equatable { case idle, ring, heading, altitude, speed, direct, approach, crossFix, crossAltitude, colour, macro }

    @Published var mode: Mode = .idle
    @Published private(set) var target: String?
    @Published private(set) var chain = CommandChain()
    /// Pointer position in scope coordinates, only tracked while it matters (heading and direct modes).
    @Published var hover: CGPoint?
    /// The level under the mouse in the altitude picker, so the scope can preview where it would be reached.
    @Published var hoverAltitude: Int?
    /// One-line message shown in the banner, for example why a choice was refused. Cleared on the next action.
    @Published private(set) var notice: String?
    /// When on, the next heading, altitude or speed chip is added as an expedited instruction. Holding Shift does the same.
    @Published var expedite = false
    /// Fixes picked so far in direct mode, in order. Committed as a chip by `commitRoute`.
    @Published private(set) var pendingRoute: [String] = []
    /// The fix chosen in crossing mode while its altitude is being picked.
    @Published private(set) var crossFix: String?

    /// True while choosing a heading, altitude or speed, where expediting makes sense.
    var canExpedite: Bool { mode == .heading || mode == .altitude || mode == .speed }

    var banner: String? {
        if let notice { return notice }
        switch mode {
        case .heading: return "Heading: point and click, or drag and release. Option turns the other way round, Shift expedites. Esc goes back."
        case .direct: return "Direct: click fixes in order, then click the last one again or press Done. Esc clears."
        case .altitude: return "Altitude: choose a level (Shift expedites). Esc goes back."
        case .speed: return "Speed: choose a speed (Shift expedites). Esc goes back."
        case .crossFix: return "Cross: click a highlighted fix on the route. Esc goes back."
        case .crossAltitude: return "\(crossFix ?? "Fix"): choose the altitude to cross at. Esc goes back."
        case .approach: return "Approach: pick from the list beside the aircraft (or the buttons on the scope). Esc goes back."
        case .colour: return "Colour: choose a marker colour for this aircraft. Esc goes back."
        case .macro: return "Macro: choose a macro to run on this aircraft, or stop the one it is running. Esc goes back."
        case .ring, .idle: return nil
        }
    }

    /// Right-click on an aircraft.
    func open(for callsign: String) {
        if target != callsign { chain.clear() }
        target = callsign
        pendingRoute = []
        mode = .ring
        notice = nil
        hover = nil
    }

    func closeRing() {
        if mode == .ring { mode = .idle }
    }

    /// Shows a message in the banner.
    func tell(_ text: String) {
        notice = text
    }

    /// Fixes a crossing restriction can be put on: those of the route in the chips, otherwise the aircraft's own route.
    func crossingCandidates(for aircraft: Aircraft) -> [String] {
        for command in chain.commands.reversed() {
            switch command {
            case .direct(let fix): return [fix]
            case .route(let fixes): return fixes
            default: continue
            }
        }
        guard aircraft.routeIndex < aircraft.route.count else { return [] }
        return aircraft.route[aircraft.routeIndex...].map(\.id)
    }

    func pickCrossFix(_ fix: String) {
        crossFix = fix
        mode = .crossAltitude
        notice = nil
    }

    func choose(_ newMode: Mode) {
        crossFix = nil
        expedite = false
        pendingRoute = []
        mode = newMode
        notice = nil
        hover = nil
    }

    func backToRing() {
        crossFix = nil
        expedite = false
        pendingRoute = []
        mode = target == nil ? .idle : .ring
        notice = nil
        hover = nil
    }

    /// Adds a chip if the aircraft would accept the command, otherwise says why not.
    func add(_ original: Command, aircraft: Aircraft) {
        var command = original
        if expedite || NSEvent.modifierFlags.contains(.shift) {
            switch original {
            case .descend, .climb, .heading, .speed: command = .expedite(original)
            default: break
            }
        }
        if let reason = command.refusal(for: aircraft) {
            notice = "\(aircraft.callsign): unable, \(reason)"
            NSSound.beep()
            return
        }
        target = aircraft.callsign
        chain.add(command, for: aircraft.callsign)
        notice = nil
        expedite = false
        backToRing()
    }

    /// A click on a fix in direct mode. Clicking the last picked fix again finishes the route.
    func pickRouteFix(_ fix: String, aircraft: Aircraft) {
        if pendingRoute.last == fix { commitRoute(aircraft: aircraft); return }
        pendingRoute.append(fix)
        notice = nil
    }

    func undoRouteFix() { _ = pendingRoute.popLast() }

    func commitRoute(aircraft: Aircraft) {
        guard !pendingRoute.isEmpty else { return }
        let command: Command = pendingRoute.count == 1 ? .direct(fix: pendingRoute[0]) : .route(fixes: pendingRoute)
        add(command, aircraft: aircraft)
    }

    func removeChip(at index: Int) {
        chain.remove(at: index)
        if chain.isEmpty && mode == .idle { target = nil }
    }

    /// Esc: step back one level. Returns false when there was nothing to step back from.
    func escape() -> Bool {
        switch mode {
        case .direct where !pendingRoute.isEmpty:
            pendingRoute = []; return true
        case .crossAltitude:
            crossFix = nil; mode = .crossFix; notice = nil; return true
        case .heading, .altitude, .speed, .direct, .approach, .crossFix, .colour, .macro:
            backToRing(); return true
        case .ring:
            mode = .idle; return true
        case .idle:
            if !chain.isEmpty { cancelAll(); return true }
            return false
        }
    }

    func cancelAll() {
        crossFix = nil
        expedite = false
        pendingRoute = []
        mode = .idle
        target = nil
        chain.clear()
        hover = nil
        notice = nil
    }

    /// Sends every chip in order, then clears.
    func send(using runner: SimRunner) {
        guard let target, !chain.isEmpty else { return }
        var refused = false
        for result in runner.issueChain(chain.issued()) {
            if case .refused = result { refused = true }
        }
        if refused { NSSound.beep() }
        runner.selectedCallsign = target
        cancelAll()
    }
}
