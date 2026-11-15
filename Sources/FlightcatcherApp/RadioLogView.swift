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
                LazyVStack(alignment: .leading, spacing: 3) {
                    ForEach(runner.radioLog) { message in
                        let mine = message.callsign != nil && message.callsign == runner.selectedCallsign
                        let colour = tint(for: message)
                        HStack(alignment: .top, spacing: 5) {
                            RoundedRectangle(cornerRadius: 1.5)
                                .fill(markerColour(message))
                                .frame(width: 3)
                            HStack(alignment: .firstTextBaseline, spacing: 0) {
                                columns(message)
                                    .fixedSize()
                                Text(message.text)
                                    .foregroundColor(colour)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .font(mono.weight(mine ? .bold : .regular))
                        }
                        .padding(.horizontal, 3)
                        .background(mine ? colour.opacity(0.22) : Color.clear)
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

    /// Fixed-width columns ahead of the message: timestamp (dim), speaker label (bold, in its colour) and the callsign
    /// (padded to eight characters so the message text lines up, blank when the call is not about an aircraft).
    private func columns(_ message: RadioMessage) -> Text {
        let callsign = (message.callsign ?? "").padding(toLength: 8, withPad: " ", startingAt: 0)
        return Text("\(timestamp(message.tick))  ").foregroundColor(.secondary)
            + Text("\(speakerLabel(message.speaker))  ").bold().foregroundColor(speakerColor(message.speaker))
            + Text("\(callsign)  ").foregroundColor(theme.heading)
            + Text("\((message.tag?.rawValue ?? "").padding(toLength: 8, withPad: " ", startingAt: 0))  ")
                .bold().foregroundColor(message.tag.map(tagColour) ?? .clear)
    }

    private static let red = Color(red: 1.0, green: 0.38, blue: 0.36)
    private static let amber = Color(red: 1.0, green: 0.72, blue: 0.25)

    private func tagColour(_ tag: RadioTag) -> Color { tag.severity == .critical ? Self.red : Self.amber }

    /// Speaker colour, except for messages that matter: emergencies and separation in red, go-arounds and refusals
    /// in amber, good news in green.
    private func tint(for message: RadioMessage) -> Color {
        if let tag = message.tag { return tagColour(tag) }
        let t = message.text.lowercased()
        if t.contains("mayday") || t.contains("pan pan") || t.contains("emergency") || t.contains("loss of separation") {
            return Color(red: 1.0, green: 0.38, blue: 0.36)
        }
        if t.contains("go-around") || t.contains("going around") || t.contains("windshear") || t.contains("unable")
            || t.contains("conflict") || t.contains("above the glidepath") {
            return Color(red: 1.0, green: 0.72, blue: 0.25)
        }
        if message.speaker == .system,
           t.contains("established") || t.contains("landed") || t.contains("handed") || t.contains("airborne") {
            return Color(red: 0.42, green: 0.86, blue: 0.55)
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
        case .controller: return "ATC  "
        case .pilot: return "PILOT"
        case .system: return "SIM  "
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
