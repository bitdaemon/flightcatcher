import SwiftUI
import SimCore

/// The settings window (Cmd+,): everything that used to sit on top of the scope, in tabs.
struct SettingsView: View {
    @ObservedObject var runner: SimRunner
    @ObservedObject var layout: PanelLayout
    @ObservedObject var tags: TagModel

    var body: some View {
        TabView {
            DisplaySettingsTab(runner: runner, tags: tags)
                .tabItem { Label("Display", systemImage: "display") }
            LayersSettingsTab(runner: runner)
                .tabItem { Label("Layers", systemImage: "square.3.layers.3d") }
            PanelsSettingsTab(layout: layout)
                .tabItem { Label("Panels", systemImage: "rectangle.3.group") }
            TrafficView(runner: runner)
                .padding(16)
                .tabItem { Label("Traffic", systemImage: "airplane") }
            WeatherSettingsView(runner: runner)
                .padding(16)
                .tabItem { Label("Weather", systemImage: "wind") }
            EventsSettingsView(runner: runner)
                .padding(16)
                .tabItem { Label("Events", systemImage: "exclamationmark.triangle") }
            DebugSettingsView(runner: runner)
                .padding(16)
                .tabItem { Label("Debug", systemImage: "ladybug") }
        }
        .frame(width: 520, height: 560)
    }
}

/// Colours, text size and the track tags.
private struct DisplaySettingsTab: View {
    @ObservedObject var runner: SimRunner
    @ObservedObject var tags: TagModel
    @ObservedObject private var themeStore = ThemeStore.shared
    @ObservedObject private var uiScale = UIScaleStore.shared
    @AppStorage("showCompass") private var showCompass = true
    @AppStorage("autoDeclutter") private var autoDeclutter = true
    @AppStorage("tagCommandsAll") private var tagCommandsAll = false

    var body: some View {
        Form {
            Section("Text size") {
                HStack {
                    Button("Smaller") { uiScale.smaller() }
                    Text("\(uiScale.percent)%").monospacedDigit().frame(width: 50)
                    Button("Larger") { uiScale.larger() }
                    Button("Default") { uiScale.reset() }
                }
                Text("Also Cmd+- and Cmd+= in the View menu, Cmd+0 for the default.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Colour scheme") {
                Picker("Colour scheme", selection: $themeStore.schemeID) {
                    ForEach(DisplaySchemes.all) { Text($0.name).tag($0.id) }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }
            Section("Track tags") {
                Toggle("Compass", isOn: $showCompass)
                Toggle("Last instructions on all tags", isOn: $tagCommandsAll)
                Toggle("Auto-declutter tags", isOn: $autoDeclutter)
                HStack {
                    Button("Declutter tags now") { tags.requestDeclutter() }
                    Button("Reset tag positions") { tags.reset() }
                }
            }
        }
        .formStyle(.grouped)
    }
}

/// What is drawn on the scope: fixes and the procedures of the airport, one by one if wanted.
private struct LayersSettingsTab: View {
    @ObservedObject var runner: SimRunner
    @AppStorage("showFixes") private var showFixes = true
    @AppStorage("showStars") private var showStars = true
    @AppStorage("showSids") private var showSids = false
    @AppStorage("showApproaches") private var showApproaches = true
    @AppStorage("hiddenProcedures") private var hiddenProcedureText = ""

    private var hiddenSet: Set<String> {
        Set(hiddenProcedureText.split(separator: ",").map(String.init))
    }

    private func setHidden(_ ids: [String], hidden: Bool) {
        var set = hiddenSet
        for id in ids { if hidden { set.insert(id) } else { set.remove(id) } }
        hiddenProcedureText = set.sorted().joined(separator: ",")
    }

    var body: some View {
        Form {
            Section("Scope") {
                Toggle("Fixes", isOn: $showFixes)
            }
            procedureSection("STARs", kind: .star, master: $showStars)
            procedureSection("SIDs", kind: .sid, master: $showSids)
            procedureSection("Approaches", kind: .approach, master: $showApproaches)
        }
        .formStyle(.grouped)
    }

    private func procedureSection(_ title: String, kind: ProcedureKind, master: Binding<Bool>) -> some View {
        let ids = (runner.airport?.procedures ?? [])
            .filter { $0.kind == kind && runner.availableProcedures.contains($0.id) }.map(\.id)
        return Section(title) {
            Toggle("Show \(title)", isOn: master)
            HStack {
                Button("All on") { master.wrappedValue = true; setHidden(ids, hidden: false) }
                Button("All off") { setHidden(ids, hidden: true) }
            }
            DisclosureGroup("Individual (\(ids.count))") {
                ForEach(ids, id: \.self) { id in
                    Toggle(id, isOn: Binding(get: { !hiddenSet.contains(id) },
                                             set: { setHidden([id], hidden: !$0) }))
                }
            }
        }
    }
}

private struct PanelsSettingsTab: View {
    @ObservedObject var layout: PanelLayout
    private let panels = [("radio", "Radio"), ("aircraft", "Aircraft"), ("info", "Airport info"), ("runways", "Runways"), ("macros", "Macros"), ("help", "Commands")]

    var body: some View {
        Form {
            Section("Panels") {
                ForEach(panels, id: \.0) { panel in
                    Toggle(panel.1, isOn: Binding(get: { layout.state(panel.0).visible },
                                                  set: { layout.setVisible(panel.0, $0) }))
                }
                Button("Reset layout") { layout.reset() }
            }
        }
        .formStyle(.grouped)
    }
}

/// Where the wind comes from.
struct WeatherSettingsView: View {
    @ObservedObject var runner: SimRunner

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("WEATHER").font(.headline)
            Picker("Wind", selection: $runner.weatherMode) {
                ForEach(WeatherMode.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            Text(runner.weatherStatus).font(.caption).foregroundStyle(.secondary)
            Text("Live wind comes from the airport's METAR (NOAA Aviation Weather Center), refreshed every 15 minutes. The simulated wind eases toward it, and runway limits use the gusts.")
                .font(.caption).foregroundStyle(.secondary)
            Spacer()
        }
    }
}
