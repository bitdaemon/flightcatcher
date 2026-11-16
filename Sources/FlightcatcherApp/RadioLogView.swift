import SwiftUI
import SimCore

/// The radio log as a panel: controller calls, pilot readbacks and simulation notices, newest at the bottom.
struct RadioLogView: View {
    @ObservedObject var runner: SimRunner
    @ObservedObject private var themeStore = ThemeStore.shared
    private var theme: Theme { themeStore.theme }
    private let mono = Font.ui(size: 12, design: .monospaced)

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(runner.radioLog) { message in
                        let mine = message.callsign != nil && message.callsign == runner.selectedCallsign
                        let colour = tint(for: message)
                        HStack(alignment: .top, spacing: 6) {
                            RoundedRectangle(cornerRadius: 1.5)
                                .fill(markerColour(message))
                                .frame(width: 3)
                            VStack(alignment: .leading, spacing: 2) {
                                header(message)
                                Text(message.text)
                                    .font(mono.weight(mine ? .semibold : .regular))
                                    .foregroundColor(colour)
                                    .fixedSize(horizontal: false, vertical: true)
                                // The instruction as it would be typed on the command bar.
                                if let code = message.code {
                                    Text("> " + code)
                                        .font(.ui(size: 10, design: .monospaced))
                                        .foregroundColor(theme.dimText)
                                        .textSelection(.enabled)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.vertical, 4)
                        .overlay(alignment: .bottom) { Rectangle().fill(theme.panelBorder.opacity(0.6)).frame(height: 1) }
                        .padding(.horizontal, 3)
                        .background(mine ? colour.opacity(0.14) : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                        .opacity(runner.selectedCallsign == nil || mine ? 1 : 0.6)
                        .id(message.id)
                    }
                }
                .padding(8)
            }
            .onChange(of: runner.radioLog.last?.id) { _, id in
                if let id { proxy.scrollTo(id, anchor: .bottom) }
            }
            .onAppear {
                if let id = runner.radioLog.last?.id { proxy.scrollTo(id, anchor: .bottom) }
            }
        }
    }

    /// The line above the message: callsign, a small speaker badge and any flag (EMERG, GO-AROUND and the like) on
    /// the left, the time on the right, so the message below gets the full width of the panel.
    private func header(_ message: RadioMessage) -> some View {
        HStack(spacing: 6) {
            Text(message.callsign ?? speakerName(message.speaker))
                .font(.ui(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(message.callsign == nil ? speakerColor(message.speaker) : theme.heading)
                .lineLimit(1)
            if message.callsign != nil {
                badge(speakerLabel(message.speaker), colour: speakerColor(message.speaker), filled: false)
            }
            if let tag = message.tag {
                badge(tag.rawValue, colour: tagColour(tag), filled: true)
            }
            Spacer(minLength: 4)
            Text(timestamp(message.tick))
                .font(.ui(size: 10, design: .monospaced))
                .foregroundColor(theme.dimText)
        }
    }

    private func badge(_ text: String, colour: Color, filled: Bool) -> some View {
        Text(text.uppercased())
            .font(.ui(size: 9, weight: .bold, design: .monospaced))
            .tracking(0.4)
            .lineLimit(1)
            .padding(.horizontal, 4)
            .frame(height: 14)
            .foregroundColor(filled ? theme.background : colour)
            .background(RoundedRectangle(cornerRadius: 2).fill(filled ? colour : Color.clear))
            .overlay(RoundedRectangle(cornerRadius: 2).stroke(colour.opacity(filled ? 1 : 0.55), lineWidth: 1))
            .fixedSize()
    }

    private func speakerName(_ speaker: RadioMessage.Speaker) -> String {
        switch speaker {
        case .controller: return "ATC"
        case .pilot: return "PILOT"
        case .system: return "SIM"
        }
    }

    private func tagColour(_ tag: RadioTag) -> Color { tag.severity == .critical ? theme.alert : theme.warning }

    /// Speaker colour, except for messages that matter: emergencies and separation in red, go-arounds and refusals
    /// in amber, good news in green.
    private func tint(for message: RadioMessage) -> Color {
        if let tag = message.tag { return tagColour(tag) }
        let t = message.text.lowercased()
        if t.contains("mayday") || t.contains("pan pan") || t.contains("emergency") || t.contains("loss of separation") {
            return theme.alert
        }
        if t.contains("go-around") || t.contains("going around") || t.contains("windshear") || t.contains("unable")
            || t.contains("conflict") || t.contains("above the glidepath") {
            return theme.warning
        }
        if message.speaker == .system,
           t.contains("established") || t.contains("landed") || t.contains("handed") || t.contains("airborne") {
            return theme.ok
        }
        return speakerColor(message.speaker)
    }

    /// The aircraft's scope marker colour as a bar at the left of its calls; clear if none is set.
    private func markerColour(_ message: RadioMessage) -> Color {
        guard let callsign = message.callsign, let index = runner.markerColours[callsign],
              AircraftMarkers.palette.indices.contains(index) else { return .clear }
        return Color(hex: AircraftMarkers.palette[index].rgb)
    }

    private func speakerLabel(_ speaker: RadioMessage.Speaker) -> String {
        switch speaker {
        case .controller: return "ATC"
        case .pilot: return "PLT"
        case .system: return "SIM"
        }
    }

    private func speakerColor(_ speaker: RadioMessage.Speaker) -> Color {
        switch speaker {
        case .controller: return theme.controller
        case .pilot: return theme.pilot
        case .system: return theme.system
        }
    }

    private func timestamp(_ tick: Int) -> String { String(format: "%02d:%02d", tick / 60, tick % 60) }
}
