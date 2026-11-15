import SwiftUI
import SimCore

/// How often random events happen, as a percentage of generated arrivals.
struct EventsSettingsView: View {
    @ObservedObject var runner: SimRunner

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("RANDOM EVENTS").font(.ui(size: 13, weight: .semibold))
            Text("Each generated arrival is rolled once when it appears and has at most one event. Changes apply to aircraft that appear from now on.")
                .font(.ui(size: 11)).foregroundStyle(.secondary)

            row("Pilot go-around", value: $runner.events.pilotGoAroundPercent,
                note: "The pilot breaks off the approach inside about 1 to 3 NM.")
            row("Windshear go-around", value: $runner.events.windshearPercent,
                note: "A windshear alert on final, inside about 1.5 to 4 NM. The wind itself is not changed.")
            row("Emergency", value: $runner.events.emergencyPercent,
                note: "Engine failure, medical or low fuel, declared one to five minutes after entering the area.")

            HStack {
                Button("Defaults") { runner.events = .gameDefault }
                Button("Off") { runner.events = EventSettings() }
            }
            Spacer()
        }
    }

    private func row(_ title: String, value: Binding<Double>, note: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                Slider(value: value, in: 0...25, step: 1)
                Text("\(Int(value.wrappedValue)) %").monospacedDigit().frame(width: 44, alignment: .trailing)
            }
            Text(note).font(.ui(size: 10)).foregroundStyle(.secondary)
        }
    }
}
