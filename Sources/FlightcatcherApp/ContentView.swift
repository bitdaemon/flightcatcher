import SwiftUI
import AppKit
import SimCore

struct ContentView: View {
    @ObservedObject var runner: SimRunner
    @StateObject private var mouse = ControlModel()
    @StateObject private var spawner = TestSpawnModel()
    @ObservedObject private var themeStore = ThemeStore.shared
    /// Text size; a change rebuilds the views so every font and size is taken again.
    @ObservedObject private var uiScale = UIScaleStore.shared
    private var theme: Theme { themeStore.theme }

    @State private var pxPerNM: CGFloat = 20
    @State private var showAirports = false
    @ObservedObject var layout: PanelLayout
    @ObservedObject var tags: TagModel
    @AppStorage("autoDeclutter") private var autoDeclutter = true
    @AppStorage("tagCommandsAll") private var tagCommandsAll = false
    @AppStorage("showCompass") private var showCompass = true
    @AppStorage("showFixes") private var showFixes = true
    @AppStorage("showStars") private var showStars = true
    @AppStorage("showSids") private var showSids = false
    @AppStorage("showApproaches") private var showApproaches = true
    /// Comma-separated ids of individual procedures hidden by the user.
    @AppStorage("hiddenProcedures") private var hiddenProcedureText = ""

    var body: some View {
        VStack(spacing: 0) {
            controlBar
            GeometryReader { geo in
                mainStack(window: geo.size)
            }
            .clipped()
        }
        .id(uiScale.factor)
        .background(theme.background)
        .overlay(alignment: .bottom) { CommandBarView(runner: runner, controls: mouse).id(uiScale.factor) }
        .onChange(of: uiScale.factor) { _, _ in mouse.tell("Text size \(uiScale.percent)%") }
        .overlay(alignment: .top) {
            // Same style and place as the mode prompts, a line lower while one of those is showing.
            if let notice = runner.weatherNotice {
                ModeBannerView(text: notice)
                    .padding(.top, (mouse.banner == nil ? 8 : 40) + 40 * UIScale.factor)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: runner.weatherNotice)
        .preferredColorScheme(themeStore.isLight ? .light : .dark)
        .frame(minWidth: 700, minHeight: 500)
        .onChange(of: runner.airport?.icao) { _, _ in mouse.cancelAll(); tags.reset() }
        .onAppear {
            print("flightcATCher: window appeared")
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    /// Last instructions for the track tags: the selected aircraft, or every aircraft if switched on.
    private var commandTags: [String: String] {
        var tags: [String: String] = [:]
        for ac in runner.aircraft where tagCommandsAll || ac.callsign == runner.selectedCallsign {
            guard let records = runner.commandHistory[ac.callsign], !records.isEmpty else { continue }
            tags[ac.callsign] = records.suffix(2)
                .map { $0.label + ($0.isPending(at: runner.tickCount) ? "..." : "") }
                .joined(separator: " ")
        }
        return tags
    }

    private func mainStack(window: CGSize) -> some View {
        ZStack(alignment: .topLeading) {
            if let airport = runner.airport {
                ScopeView(airport: airport,
                          aircraft: runner.aircraft,
                          selected: runner.selectedCallsign,
                          showCompass: showCompass,
                          showFixes: showFixes,
                          showStars: showStars,
                          showSids: showSids,
                          showApproaches: showApproaches,
                          hiddenProcedures: hiddenSet,
                          availableProcedures: runner.availableProcedures,
                          conflicts: runner.conflicts,
                          runwayStatuses: runner.runwayStatuses,
                          markerColours: runner.markerColours,
                          shownProcedures: runner.shownProcedures,
                          commandTags: commandTags,
                          autoDeclutter: autoDeclutter,
                          tags: tags,
                          controls: mouse,
                          onSend: { mouse.send(using: runner) },
                          onSelect: { runner.selectedCallsign = $0 },
                          pxPerNM: $pxPerNM,
                          onMark: { runner.setMarker($0, for: $1) },
                          macroTags: runner.macroRuns.mapValues(\.tagText),
                          areaRadiusNM: runner.areaRadiusNM,
                          macroChoices: { runner.macros(for: $0).map(\.name) },
                          onMacro: { name, callsign in
                              if let name {
                                  if let reason = runner.runMacro(named: name, on: callsign) {
                                      mouse.tell("\(callsign): macro not started, \(reason)")
                                      NSSound.beep()
                                  }
                              } else {
                                  runner.cancelMacro(on: callsign)
                              }
                          },
                          placing: runner.testSpawner && spawner.placing,
                          onPlace: { spawner.place(east: $0, north: $1, runner: runner) })
                    .id(airport.icao)
            } else {
                Text("Could not load airport package: \(runner.loadError ?? "unknown")")
                    .foregroundStyle(theme.alert)
                    .padding()
            }
            panels(window: window)
        }
    }

    /// The movable panels. Default positions depend on the window size until the user moves a panel.
    @ViewBuilder
    private func panels(window: CGSize) -> some View {
        FloatingPanel(id: "radio", title: "Radio", window: window,
                      defaultOrigin: CGPoint(x: 12, y: max(60, window.height - 84 - 180)),
                      width: min(620, max(300, window.width - 24)), defaultHeight: 180,
                      resizable: true, minSize: CGSize(width: 260, height: 90), layout: layout) {
            RadioLogView(runner: runner)
        }
        FloatingPanel(id: "aircraft", title: "Aircraft (\(runner.aircraft.count))", window: window,
                      defaultOrigin: CGPoint(x: max(12, window.width - 392), y: 12),
                      width: 380, defaultHeight: 340, resizable: true,
                      minSize: CGSize(width: 300, height: 120), layout: layout) {
            AircraftListView(runner: runner)
        }
        FloatingPanel(id: "info", title: "Airport info", window: window,
                      defaultOrigin: CGPoint(x: max(12, window.width - 312), y: 364),
                      width: 300, layout: layout) {
            InfoPanelView(airport: runner.airport, conflicts: runner.conflicts, lossCount: runner.lossCount,
                          wind: runner.wind, runways: runner.runwayStatuses,
                          windSource: runner.windSource, nextWeatherUpdate: runner.nextWeatherUpdate,
                          trafficRates: runner.trafficRates)
        }
        FloatingPanel(id: "runways", title: "Runways", window: window,
                      defaultOrigin: CGPoint(x: max(12, window.width - 312), y: 620),
                      width: 300, defaultHeight: 220, resizable: true,
                      minSize: CGSize(width: 220, height: 140), layout: layout) {
            RunwayMapView(runner: runner)
        }
        if runner.debugLogging {
            FloatingPanel(id: "debuglog", title: "Debug log", window: window,
                          defaultOrigin: CGPoint(x: 12, y: max(60, window.height - 84 - 380)),
                          width: min(760, max(320, window.width - 24)), defaultHeight: 190,
                          resizable: true, minSize: CGSize(width: 300, height: 100), layout: layout) {
                DebugLogView(runner: runner)
            }
        }
        if runner.testSpawner {
            FloatingPanel(id: "spawner", title: "Test spawner", window: window,
                          defaultOrigin: CGPoint(x: 12, y: 96),
                          width: 300, layout: layout) {
                TestSpawnerView(runner: runner, model: spawner)
            }
        }
        FloatingPanel(id: "macros", title: "Macros", window: window,
                      defaultOrigin: CGPoint(x: max(12, window.width / 2 - 270), y: 60),
                      width: 540, defaultHeight: 380, resizable: true,
                      minSize: CGSize(width: 440, height: 240), layout: layout) {
            MacroEditorView(runner: runner)
        }
        FloatingPanel(id: "help", title: "Commands", window: window,
                      defaultOrigin: CGPoint(x: 12, y: 96), width: 380, layout: layout) {
            HelpView()
        }
    }

    private var hiddenSet: Set<String> {
        Set(hiddenProcedureText.split(separator: ",").map(String.init))
    }

    // MARK: Control bar

    /// Panels with a button in the control bar: id, icon, name.
    private var panelButtons: [(String, String, String)] {
        var list = [("radio", "antenna.radiowaves.left.and.right", "Radio"),
                    ("aircraft", "airplane", "Aircraft"),
                    ("info", "info.circle", "Airport info"),
                    ("runways", "road.lanes", "Runways"),
                    ("macros", "list.bullet.rectangle", "Macros"),
                    ("help", "questionmark.circle", "Commands")]
        if runner.debugLogging { list.append(("debuglog", "ladybug", "Debug log")) }
        if runner.testSpawner { list.append(("spawner", "plus.viewfinder", "Test spawner")) }
        return list
    }

    private var mono: Font { .ui(size: 12, design: .monospaced) }

    /// The box across the top of the window: clock, run and speed, zoom, airport, STAR and SID display, panel buttons,
    /// settings. Everything else is in the settings window (Cmd+,).
    private var controlBar: some View {
        HStack(spacing: 10) {
            Text("\(runner.airport?.title ?? "----")  t+\(runner.tickCount) s")
                .font(.ui(size: 13, design: .monospaced))
                .foregroundStyle(theme.heading)
                .lineLimit(1)
                .layoutPriority(1)

            divider
            barButton(runner.isRunning ? "pause.fill" : "play.fill", help: runner.isRunning ? "Pause" : "Run", on: false) {
                runner.isRunning.toggle()
            }
            Slider(value: Binding(get: { Double(runner.speed) },
                                  set: { runner.speed = min(20, max(1, Int($0.rounded()))) }),
                   in: 1...20, step: 1)
                .frame(width: 110 * UIScale.factor)
                .help("Simulation speed")
            Text("\(runner.speed)x")
                .font(mono)
                .foregroundStyle(theme.text)
                .frame(width: 30 * UIScale.factor, alignment: .leading)

            divider
            barButton("minus.magnifyingglass", help: "Zoom out", on: false) { pxPerNM = max(pxPerNM / 1.25, 4) }
            barButton("plus.magnifyingglass", help: "Zoom in", on: false) { pxPerNM = min(pxPerNM * 1.25, 600) }
            Button { showAirports.toggle() } label: {
                Text(runner.airport?.city ?? runner.airport?.icao ?? "Airport")
                    .font(mono).foregroundStyle(theme.text).lineLimit(1)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .overlay(Rectangle().stroke(theme.panelBorder, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .help("Choose the airport")
            .popover(isPresented: $showAirports, arrowEdge: .bottom) {
                AirportPicker(entries: runner.airportIndex, currentICAO: runner.airport?.icao) { entry in
                    runner.loadAirport(entry.resourceName)
                    showAirports = false
                }
            }

            divider
            textToggle("STAR", on: showStars, help: "Show all STARs") { showStars.toggle() }
            textToggle("SID", on: showSids, help: "Show all SIDs") { showSids.toggle() }

            Spacer(minLength: 6)

            ForEach(panelButtons, id: \.0) { id, icon, name in
                barButton(icon, help: (layout.state(id).visible ? "Hide " : "Show ") + name, on: layout.state(id).visible) {
                    layout.toggle(id)
                }
            }
            divider
            SettingsLink {
                Image(systemName: "gearshape").font(.ui(size: 13)).foregroundStyle(theme.dimText)
            }
            .buttonStyle(.plain)
            .help("Settings (Cmd+,)")
        }
        .padding(.horizontal, 10)
        .frame(height: 36 * UIScale.factor)
        .background(theme.panel)
        .overlay(alignment: .bottom) { Rectangle().fill(theme.panelBorder).frame(height: 1) }
    }

    private var divider: some View {
        Rectangle().fill(theme.panelBorder).frame(width: 1, height: 18 * UIScale.factor)
    }

    /// A small icon button, lit when its panel or option is on.
    private func barButton(_ symbol: String, help: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.ui(size: 13))
                .foregroundStyle(on ? theme.selected : theme.dimText)
                .frame(width: 24 * UIScale.factor, height: 22 * UIScale.factor)
                .background(on ? theme.rowHighlight : Color.clear)
                .overlay(Rectangle().stroke(on ? theme.selected.opacity(0.6) : Color.clear, lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func textToggle(_ label: String, on: Bool, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.ui(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(on ? theme.selected : theme.dimText)
                .padding(.horizontal, 6).padding(.vertical, 3)
                .background(on ? theme.rowHighlight : Color.clear)
                .overlay(Rectangle().stroke(on ? theme.selected : theme.panelBorder, lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
