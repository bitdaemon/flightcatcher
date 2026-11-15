import SwiftUI
import SimCore

/// What a ring button does: open a mode (heading, altitude and so on), or add a command as a chip at once.
enum RingAction: Equatable {
    case mode(ControlModel.Mode)
    case command(Command)
}

struct RingItem: Identifiable {
    let id: String
    let label: String
    let action: RingAction
    let enabled: Bool
    /// Less used items (crossing, maintain, macro, colour) go on a small outer arc so the main ring stays uncluttered.
    var secondary: Bool = false
}

/// Round buttons around the aircraft. The set depends on the aircraft (see `ScopeView.ringItems`):
/// arrivals get HDG ALT SPD DCT APP XNG MAINT HO, departures in the air the same without APP, departures on the ground
/// only LUP and T/O.
struct RadialRingView: View {
    let center: CGPoint
    let items: [RingItem]
    let onPick: (RingAction) -> Void

    @ObservedObject private var themeStore = ThemeStore.shared
    private var theme: Theme { themeStore.theme }

    private var primary: [RingItem] { items.filter { !$0.secondary } }
    private var secondary: [RingItem] { items.filter(\.secondary) }

    /// Outer arc for the secondary items: below and to the left of the aircraft, away from the track tag on the right.
    private func secondaryPosition(_ i: Int) -> CGPoint {
        let n = secondary.count
        let start = 150.0, end = 255.0 // degrees clockwise from north
        let deg = n == 1 ? (start + end) / 2 : start + (end - start) * Double(i) / Double(n - 1)
        let a = deg * .pi / 180
        return CGPoint(x: center.x + CGFloat(sin(a)) * 92, y: center.y - CGFloat(cos(a)) * 92)
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(theme.selected.opacity(0.5), lineWidth: 1)
                .frame(width: 104, height: 104)
                .position(center)
                .allowsHitTesting(false)
            ForEach(secondary.indices, id: \.self) { i in
                let item = secondary[i]
                Button { onPick(item.action) } label: {
                    Text(item.label)
                        .font(.ui(size: 9, weight: .semibold, design: .monospaced))
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.horizontal, 6)
                        .frame(height: 18)
                        .background(Capsule().fill(theme.panel))
                        .overlay(Capsule().stroke(item.enabled ? theme.panelBorder.opacity(1) : theme.panelBorder.opacity(0.5), lineWidth: 1))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .foregroundStyle(item.enabled ? theme.dimText : theme.dimText.opacity(0.4))
                .disabled(!item.enabled)
                .position(secondaryPosition(i))
            }
            ForEach(primary.indices, id: \.self) { i in
                let angle = Double(i) * (360 / Double(primary.count)) * .pi / 180
                let item = primary[i]
                Button { onPick(item.action) } label: {
                    Text(item.label)
                        .font(.ui(size: 10, weight: .bold, design: .monospaced))
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(theme.panel))
                        .overlay(Circle().stroke(item.enabled ? theme.heading : theme.panelBorder, lineWidth: 1.5))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(item.enabled ? theme.text : theme.dimText)
                .disabled(!item.enabled)
                .position(x: center.x + CGFloat(sin(angle)) * 52, y: center.y - CGFloat(cos(angle)) * 52)
            }
        }
    }
}

/// A scrolling column of values (levels or speeds) with the current one marked. High values at the top.
struct ValueColumnView: View {
    struct Item: Identifiable {
        let id: Int
        let label: String
        let isCurrent: Bool
        let enabled: Bool
        /// A departure's flight-plan level: drawn with a coloured outline and a star.
        var isPlanned: Bool = false
    }

    let title: String
    let items: [Item]
    let onPick: (Int) -> Void
    /// Called with the item under the mouse, or nil when the mouse leaves it.
    var onHover: ((Int?) -> Void)? = nil

    @ObservedObject private var themeStore = ThemeStore.shared
    private var theme: Theme { themeStore.theme }

    var body: some View {
        VStack(spacing: 4) {
            Text(title).font(.ui(size: 11, weight: .bold, design: .monospaced)).foregroundStyle(theme.heading)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(items.sorted { $0.id > $1.id }) { item in
                            Button { onPick(item.id) } label: {
                                Text((item.isCurrent ? "● " : "") + (item.isPlanned ? "★ " : "") + item.label)
                                    .font(.ui(size: 11, design: .monospaced))
                                    .frame(width: 86, height: 20)
                                    .background(RoundedRectangle(cornerRadius: 3).fill(item.isCurrent ? theme.rowHighlight : theme.panel))
                                    .overlay(RoundedRectangle(cornerRadius: 3)
                                        .stroke(theme.selected, lineWidth: item.isPlanned ? 1.5 : 0))
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(item.isPlanned ? theme.selected : (item.enabled ? theme.text : theme.dimText.opacity(0.5)))
                            .disabled(!item.enabled)
                            .onHover { inside in onHover?(inside ? item.id : nil) }
                            .id(item.id)
                        }
                    }
                }
                .frame(width: 92, height: 220)
                .onAppear {
                    if let current = items.first(where: \.isCurrent) { proxy.scrollTo(current.id, anchor: .center) }
                }
            }
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 4).fill(theme.panel))
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(theme.panelBorder, lineWidth: 1))
    }
}

/// The commands collected so far, as removable chips, with Send and Cancel.
struct ChipStripView: View {
    let callsign: String
    let commands: [Command]
    let onRemove: (Int) -> Void
    let onSend: () -> Void
    let onCancel: () -> Void

    @ObservedObject private var themeStore = ThemeStore.shared
    private var theme: Theme { themeStore.theme }
    private let mono = Font.ui(size: 11, design: .monospaced)

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(callsign).font(mono).foregroundStyle(theme.selected)
            ForEach(commands.indices, id: \.self) { i in
                Button { onRemove(i) } label: {
                    HStack(spacing: 6) {
                        Text(commands[i].chipLabel).font(mono)
                        Spacer(minLength: 4)
                        Text("✕").font(.ui(size: 9)).foregroundStyle(theme.dimText)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .frame(width: 150)
                    .background(RoundedRectangle(cornerRadius: 3).fill(theme.rowHighlight))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(theme.text)
                .help("Click to remove")
            }
            HStack(spacing: 6) {
                Button("Send ↵", action: onSend).keyboardShortcut(.return, modifiers: .command)
                Button("Cancel", action: onCancel)
            }
            .font(mono)
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 4).fill(theme.panel))
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(theme.selected.opacity(0.6), lineWidth: 1))
        .fixedSize()
    }
}

/// One-line prompt at the top of the scope while a mode is active, or a notice after a refused choice.
struct ModeBannerView: View {
    let text: String
    @ObservedObject private var themeStore = ThemeStore.shared
    private var theme: Theme { themeStore.theme }

    var body: some View {
        Text(text)
            .font(.ui(size: 12, design: .monospaced))
            .foregroundStyle(theme.text)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 4).fill(theme.panel))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(theme.heading.opacity(0.7), lineWidth: 1))
            .allowsHitTesting(false)
    }
}
