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

/// Buttons on a dark band around the aircraft. The set depends on the aircraft (see `ScopeView.ringItems`):
/// arrivals get HDG ALT SPD DCT APP XNG MAINT HO, departures in the air the same without APP, departures on the ground
/// only LUP and T/O. Main items sit on the band as small square-cornered keys; the rest are chips on an outer arc.
/// The key under the pointer fills with the scheme's heading colour.
struct RadialRingView: View {
    let center: CGPoint
    let items: [RingItem]
    /// The aircraft's track tag on screen; a thin line joins the band to it. `.null` when the tag is hidden.
    var tagFrame: CGRect = .null
    let onPick: (RingAction) -> Void

    @ObservedObject private var themeStore = ThemeStore.shared
    private var theme: Theme { themeStore.theme }

    /// From the outer edge of the band to the nearest point of the tag, or nil when the tag sits on the band.
    private var leader: (from: CGPoint, to: CGPoint)? {
        guard !tagFrame.isNull else { return nil }
        let to = CGPoint(x: min(max(center.x, tagFrame.minX), tagFrame.maxX),
                         y: min(max(center.y, tagFrame.minY), tagFrame.maxY))
        let dx = to.x - center.x, dy = to.y - center.y
        let d = hypot(dx, dy)
        let edge = bandRadius + bandWidth / 2
        guard d > edge + 4 else { return nil }
        return (CGPoint(x: center.x + dx / d * edge, y: center.y + dy / d * edge), to)
    }

    private var primary: [RingItem] { items.filter { !$0.secondary } }
    private var secondary: [RingItem] { items.filter(\.secondary) }

    private let bandRadius: CGFloat = 58
    private let bandWidth: CGFloat = 26

    /// Outer arc for the secondary items: below and to the left of the aircraft, away from the track tag on the right.
    private func secondaryPosition(_ i: Int) -> CGPoint {
        let n = secondary.count
        let start = 150.0, end = 255.0 // degrees clockwise from north
        let deg = n == 1 ? (start + end) / 2 : start + (end - start) * Double(i) / Double(n - 1)
        let a = deg * .pi / 180
        let r = bandRadius + bandWidth / 2 + 22
        return CGPoint(x: center.x + CGFloat(sin(a)) * r, y: center.y - CGFloat(cos(a)) * r)
    }

    var body: some View {
        ZStack {
            if let leader {
                Path { p in p.move(to: leader.from); p.addLine(to: leader.to) }
                    .stroke(theme.heading.opacity(0.7), lineWidth: 1)
                    .allowsHitTesting(false)
                Circle().fill(theme.heading).frame(width: 4, height: 4).position(leader.to).allowsHitTesting(false)
            }
            // The band: a dark ring with hairline edges, like a bezel round the target.
            Circle()
                .stroke(theme.panel.opacity(0.94), lineWidth: bandWidth)
                .frame(width: bandRadius * 2, height: bandRadius * 2)
                .position(center)
                .allowsHitTesting(false)
            ForEach([bandRadius - bandWidth / 2, bandRadius + bandWidth / 2], id: \.self) { r in
                Circle()
                    .stroke(theme.panelBorder, lineWidth: 1)
                    .frame(width: r * 2, height: r * 2)
                    .position(center)
                    .allowsHitTesting(false)
            }
            ForEach(secondary.indices, id: \.self) { i in
                RingKey(item: secondary[i], small: true) { onPick(secondary[i].action) }
                    .position(secondaryPosition(i))
            }
            ForEach(primary.indices, id: \.self) { i in
                let angle = Double(i) * (360 / Double(primary.count)) * .pi / 180
                RingKey(item: primary[i], small: false) { onPick(primary[i].action) }
                    .position(x: center.x + CGFloat(sin(angle)) * bandRadius,
                              y: center.y - CGFloat(cos(angle)) * bandRadius)
            }
        }
    }
}

/// One key of the radial menu: outlined at rest, filled with the heading colour under the pointer, faint when disabled.
private struct RingKey: View {
    let item: RingItem
    let small: Bool
    let action: () -> Void
    @State private var hovering = false
    @ObservedObject private var themeStore = ThemeStore.shared
    private var theme: Theme { themeStore.theme }

    var body: some View {
        let lit = hovering && item.enabled
        Button(action: action) {
            Text(item.label)
                .font(.ui(size: small ? 9 : 10, weight: .bold, design: .monospaced))
                .tracking(0.4)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .fixedSize(horizontal: small, vertical: false)
                .padding(.horizontal, small ? 6 : 0)
                .frame(width: small ? nil : 42, height: small ? 18 : 22)
                .foregroundStyle(lit ? theme.background
                                 : item.enabled ? (small ? theme.dimText : theme.text) : theme.dimText.opacity(0.35))
                .background(RoundedRectangle(cornerRadius: 3)
                    .fill(lit ? theme.heading : small ? theme.panel.opacity(0.94) : theme.rowHighlight))
                .overlay(RoundedRectangle(cornerRadius: 3)
                    .stroke(lit ? theme.heading
                            : item.enabled ? (small ? theme.panelBorder : theme.heading.opacity(0.45))
                            : theme.panelBorder.opacity(0.5), lineWidth: 1))
                .contentShape(RoundedRectangle(cornerRadius: 3))
        }
        .buttonStyle(.plain)
        .disabled(!item.enabled)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.08), value: hovering)
    }
}

/// The card that every picker opened from the ring sits in: the panel colour, a hairline border and a header strip
/// with the title in small capitals, matching the docked panels.
struct PickerCard<Content: View>: View {
    let title: String
    var accent: Color? = nil
    @ViewBuilder var content: () -> Content
    @ObservedObject private var themeStore = ThemeStore.shared
    private var theme: Theme { themeStore.theme }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 1).fill(accent ?? theme.heading).frame(width: 3, height: 10)
                Text(title.uppercased())
                    .font(.ui(size: 10, weight: .bold, design: .monospaced))
                    .tracking(0.6)
                    .foregroundStyle(theme.dimText)
                    .lineLimit(1)
            }
            .padding(.horizontal, 8)
            .frame(height: 22)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .bottom) { Rectangle().fill(theme.panelBorder).frame(height: 1) }
            content().padding(6)
        }
        .background(RoundedRectangle(cornerRadius: 4).fill(theme.panel.opacity(0.96)))
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(theme.panelBorder, lineWidth: 1))
        .shadow(color: .black.opacity(themeStore.isLight ? 0.12 : 0.45), radius: 10, y: 4)
    }
}

/// A key inside a picker: outlined or plain at rest, filled with the heading colour under the pointer.
struct PickerKey: View {
    let label: String
    var colour: Color? = nil
    /// Marks the current value (a soft fill) or the flight-plan level (an outline in the selected colour).
    var current = false
    var outlined = false
    var enabled = true
    var width: CGFloat? = nil
    var onHover: ((Bool) -> Void)? = nil
    let action: () -> Void
    @State private var hovering = false
    @ObservedObject private var themeStore = ThemeStore.shared
    private var theme: Theme { themeStore.theme }

    var body: some View {
        let lit = hovering && enabled
        Button(action: action) {
            Text(label)
                .font(.ui(size: 11, weight: current ? .bold : .regular, design: .monospaced))
                .lineLimit(1)
                .padding(.horizontal, 6)
                .frame(width: width, height: 20, alignment: width == nil ? .center : .leading)
                .foregroundStyle(lit ? theme.background : !enabled ? theme.dimText.opacity(0.4)
                                 : outlined ? theme.selected : (colour ?? theme.text))
                .background(RoundedRectangle(cornerRadius: 3)
                    .fill(lit ? theme.heading : current ? theme.rowHighlight : Color.clear))
                .overlay(RoundedRectangle(cornerRadius: 3)
                    .stroke(lit ? theme.heading : outlined ? theme.selected : current ? theme.heading.opacity(0.5)
                            : Color.clear, lineWidth: 1))
                .contentShape(RoundedRectangle(cornerRadius: 3))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .onHover { inside in hovering = inside; onHover?(inside) }
        .animation(.easeOut(duration: 0.08), value: hovering)
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
        PickerCard(title: title) {
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 1) {
                        ForEach(items.sorted { $0.id > $1.id }) { item in
                            PickerKey(label: (item.isPlanned ? "★ " : "") + item.label,
                                      current: item.isCurrent, outlined: item.isPlanned, enabled: item.enabled,
                                      width: 88, onHover: { inside in onHover?(inside ? item.id : nil) }) {
                                onPick(item.id)
                            }
                            .id(item.id)
                        }
                    }
                }
                .frame(width: 88, height: 220)
                .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.08),
                                             .init(color: .black, location: 0.92), .init(color: .clear, location: 1)],
                                     startPoint: .top, endPoint: .bottom))
                .onAppear {
                    if let current = items.first(where: \.isCurrent) { proxy.scrollTo(current.id, anchor: .center) }
                }
            }
        }
        .fixedSize()
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
        PickerCard(title: callsign, accent: theme.selected) {
        VStack(alignment: .leading, spacing: 3) {
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
            HStack(spacing: 4) {
                PickerKey(label: "SEND ↵", colour: theme.heading, current: true, action: onSend)
                    .keyboardShortcut(.return, modifiers: .command)
                PickerKey(label: "CANCEL", colour: theme.dimText, action: onCancel)
            }
            .padding(.top, 2)
        }
        }
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
