import SwiftUI
import AppKit

/// Where one panel is and how it is set. Nil position or size means "use the default for the current window".
struct PanelState: Codable, Equatable {
    var x: Double?
    var y: Double?
    var width: Double?
    var height: Double?
    var pinned = false
    var collapsed = false
    var visible = true
    var z = 0
}

/// Positions and settings of every panel, saved between runs.
@MainActor
final class PanelLayout: ObservableObject {
    @Published private(set) var states: [String: PanelState] = [:]
    private static let key = "panelLayout"

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let saved = try? JSONDecoder().decode([String: PanelState].self, from: data) {
            states = saved
        }
    }

    func state(_ id: String) -> PanelState { states[id] ?? PanelState() }

    func update(_ id: String, _ change: (inout PanelState) -> Void) {
        var s = state(id)
        change(&s)
        states[id] = s
    }

    func bringToFront(_ id: String) {
        let top = (states.values.map(\.z).max() ?? 0)
        guard state(id).z < top || states[id] == nil else { return }
        update(id) { $0.z = top + 1 }
    }

    func save() {
        if let data = try? JSONEncoder().encode(states) { UserDefaults.standard.set(data, forKey: Self.key) }
    }

    func setVisible(_ id: String, _ visible: Bool) {
        if visible && !state(id).visible { needsPlacement.insert(id) }
        if !visible { frames[id] = nil }
        update(id) { $0.visible = visible; if visible { $0.collapsed = false } }
        save()
    }

    func toggle(_ id: String) { setVisible(id, !state(id).visible) }

    // MARK: Keeping new panels clear of the others

    /// Where each visible panel is on screen, reported by the panels themselves. Not published: it only feeds placement.
    private(set) var frames: [String: CGRect] = [:]
    /// Panels just switched on: they are moved to free space when they appear.
    var needsPlacement: Set<String> = []

    func report(_ id: String, frame: CGRect) { frames[id] = frame }
    func moveFrame(_ id: String, to origin: CGPoint) { frames[id]?.origin = origin }
    func forget(_ id: String) { frames[id] = nil }

    /// The free spot nearest to `preferred` where a panel of `size` overlaps no other visible panel, or nil if the
    /// window has no such spot (the panel then stays where it would have gone).
    func freeOrigin(for id: String, size: CGSize, window: CGSize, preferred: CGPoint) -> CGPoint? {
        let others = frames.filter { $0.key != id }.map { $0.value.insetBy(dx: -6, dy: -6) }
        func fits(_ p: CGPoint) -> Bool {
            let r = CGRect(origin: p, size: size)
            return !others.contains { $0.intersects(r) }
        }
        if fits(preferred) { return preferred }
        let maxX = max(0, window.width - size.width), maxY = max(0, window.height - size.height)
        let step: CGFloat = 16
        var best: CGPoint?
        var bestDistance = CGFloat.greatestFiniteMagnitude
        var y: CGFloat = 0
        while y <= maxY {
            var x: CGFloat = 0
            while x <= maxX {
                let p = CGPoint(x: x, y: y)
                let d = hypot(x - preferred.x, y - preferred.y)
                if d < bestDistance, fits(p) { best = p; bestDistance = d }
                x += step
            }
            y += step
        }
        return best
    }

    /// Back to the default positions and sizes; every panel visible, none pinned.
    func reset() {
        states = [:]
        save()
    }
}

/// A window inside the main window: drag it by its title bar, pin it so it stays put, collapse it to the title bar,
/// hide it, and resize it from the bottom-right corner when `resizable`.
struct FloatingPanel<Content: View>: View {
    let id: String
    let title: String
    let window: CGSize
    let defaultOrigin: CGPoint
    let width: CGFloat
    var defaultHeight: CGFloat?
    var resizable = false
    var minSize = CGSize(width: 220, height: 100)
    @ObservedObject var layout: PanelLayout
    @ViewBuilder var content: () -> Content

    @State private var dragStart: CGPoint?
    @State private var resizeStart: CGSize?
    @ObservedObject private var themeStore = ThemeStore.shared
    private var theme: Theme { themeStore.theme }
    private let titleHeight: CGFloat = 24 * UIScale.factor
    private let snap: CGFloat = 12

    private func size(_ s: PanelState) -> CGSize {
        let w = max(minSize.width * UIScale.factor, CGFloat(s.width ?? Double(width * UIScale.factor)))
        let h = resizable ? max(minSize.height * UIScale.factor, CGFloat(s.height ?? Double((defaultHeight ?? 240) * UIScale.factor))) : 0
        return CGSize(width: w, height: h)
    }

    private func origin(_ s: PanelState) -> CGPoint {
        let x = s.x ?? Double(defaultOrigin.x)
        let y = s.y ?? Double(defaultOrigin.y)
        return CGPoint(x: min(max(x, 0), max(0, Double(window.width) - 80)),
                       y: min(max(y, 0), max(0, Double(window.height) - Double(titleHeight))))
    }

    /// Pulls a position to the window edges when it is within a few points of them.
    private func snapped(_ p: CGPoint, panelWidth: CGFloat) -> CGPoint {
        var q = p
        if abs(q.x) < snap { q.x = 0 }
        if abs(q.x + panelWidth - window.width) < snap { q.x = window.width - panelWidth }
        if abs(q.y) < snap { q.y = 0 }
        return q
    }

    var body: some View {
        let s = layout.state(id)
        if s.visible {
            let sz = size(s)
            let o = origin(s)
            VStack(spacing: 0) {
                titleBar(s, panelWidth: sz.width)
                if !s.collapsed {
                    if resizable {
                        content().frame(width: sz.width, height: max(0, sz.height - titleHeight), alignment: .topLeading)
                    } else {
                        content().frame(width: sz.width, alignment: .topLeading)
                    }
                }
            }
            .frame(width: sz.width)
            .background(theme.panel)
            .overlay(Rectangle().stroke(s.pinned ? theme.selected.opacity(0.7) : theme.panelBorder, lineWidth: 1))
            .overlay(alignment: .bottomTrailing) {
                if resizable && !s.pinned && !s.collapsed { resizeHandle(s) }
            }
            .background(GeometryReader { g in
                Color.clear
                    .onAppear { appeared(size: g.size) }
                    .onChange(of: g.size) { _, newSize in
                        layout.report(id, frame: CGRect(origin: origin(layout.state(id)), size: newSize))
                    }
            })
            .onChange(of: o) { _, newOrigin in layout.moveFrame(id, to: newOrigin) }
            .onDisappear { layout.forget(id) }
            .offset(x: o.x, y: o.y)
            .zIndex(Double(s.z))
            .simultaneousGesture(TapGesture().onEnded { layout.bringToFront(id) })
        }
    }

    /// A panel shown for the first time, or switched back on, moves to the nearest place where it covers no other panel.
    private func appeared(size: CGSize) {
        let s = layout.state(id)
        if layout.needsPlacement.contains(id) || s.x == nil || s.y == nil {
            layout.needsPlacement.remove(id)
            if let p = layout.freeOrigin(for: id, size: size, window: window, preferred: origin(s)) {
                layout.update(id) { $0.x = Double(p.x); $0.y = Double(p.y) }
                layout.save()
                layout.report(id, frame: CGRect(origin: p, size: size))
                return
            }
        }
        layout.report(id, frame: CGRect(origin: origin(s), size: size))
    }

    private func titleBar(_ s: PanelState, panelWidth: CGFloat) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "line.3.horizontal").foregroundStyle(s.pinned ? theme.dimText.opacity(0.4) : theme.dimText)
            Text(title.uppercased())
                .font(.ui(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(theme.heading)
                .lineLimit(1)
            Spacer(minLength: 4)
            barButton(s.pinned ? "pin.fill" : "pin", help: s.pinned ? "Unpin: allow moving" : "Pin: lock in place",
                      tint: s.pinned ? theme.selected : theme.dimText) {
                layout.update(id) { $0.pinned.toggle() }; layout.save()
            }
            barButton(s.collapsed ? "chevron.down" : "chevron.up", help: s.collapsed ? "Expand" : "Collapse to title bar",
                      tint: theme.dimText) {
                layout.update(id) { $0.collapsed.toggle() }; layout.save()
            }
            barButton("xmark", help: "Hide (bring back from the Panels menu)", tint: theme.dimText) {
                layout.setVisible(id, false)
            }
        }
        .padding(.horizontal, 8)
        .frame(width: panelWidth, height: titleHeight)
        .background(theme.rowHighlight)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 2, coordinateSpace: .global)
                .onChanged { drag in
                    guard !layout.state(id).pinned else { return }
                    if dragStart == nil {
                        dragStart = origin(layout.state(id))
                        layout.bringToFront(id)
                    }
                    let start = dragStart ?? .zero
                    let moved = snapped(CGPoint(x: start.x + drag.translation.width, y: start.y + drag.translation.height),
                                        panelWidth: panelWidth)
                    layout.update(id) { $0.x = Double(moved.x); $0.y = Double(moved.y) }
                }
                .onEnded { _ in
                    dragStart = nil
                    layout.save()
                }
        )
    }

    private func barButton(_ symbol: String, help: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.ui(size: 10, weight: .semibold)).frame(width: 16, height: 16)
        }
        .buttonStyle(.plain)
        .foregroundStyle(tint)
        .help(help)
    }

    private func resizeHandle(_ s: PanelState) -> some View {
        Image(systemName: "arrow.up.left.and.arrow.down.right")
            .font(.ui(size: 9))
            .foregroundStyle(theme.dimText)
            .frame(width: 18, height: 18)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { drag in
                        if resizeStart == nil { resizeStart = size(layout.state(id)) }
                        let start = resizeStart ?? .zero
                        layout.update(id) {
                            $0.width = Double(max(minSize.width, start.width + drag.translation.width))
                            $0.height = Double(max(minSize.height, start.height + drag.translation.height))
                        }
                    }
                    .onEnded { _ in
                        resizeStart = nil
                        layout.save()
                    }
            )
    }
}
