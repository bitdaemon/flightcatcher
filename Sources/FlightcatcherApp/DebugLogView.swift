import SwiftUI
import AppKit
import SimCore

/// The debug log as a panel (shown while debug logging is on): commands accepted, refused or dropped, approach progress,
/// and why an aircraft has not captured its approach yet.
struct DebugLogView: View {
    @ObservedObject var runner: SimRunner
    @ObservedObject private var themeStore = ThemeStore.shared
    private var theme: Theme { themeStore.theme }
    @State private var selectedOnly = false
    private let mono = Font.ui(size: 11, design: .monospaced)

    private var entries: [DebugEntry] {
        guard selectedOnly, let selected = runner.selectedCallsign else { return runner.debugEntries }
        return runner.debugEntries.filter { $0.callsign == selected || $0.callsign == nil }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Toggle("Selected aircraft only", isOn: $selectedOnly).font(mono)
                Spacer()
                Button("Copy") { DebugLogView.copy(entries.suffix(200).map(\.text)) }
                Button("Clear") { runner.clearDebugLog() }
            }
            .padding(.horizontal, 8)
            .padding(.top, 6)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(entries) { entry in
                            Text(entry.text)
                                .font(mono)
                                .foregroundStyle(colour(entry))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(entry.id)
                        }
                    }
                    .padding(8)
                }
                .onChange(of: entries.last?.id) { _, id in
                    if let id { proxy.scrollTo(id, anchor: .bottom) }
                }
            }
        }
    }

    private func colour(_ entry: DebugEntry) -> Color {
        let m = entry.message
        if m.contains("REFUSED") || m.contains("DROPPED") || m.contains("STALLED") { return Color(red: 1.0, green: 0.38, blue: 0.36) }
        if m.contains("not captured") { return Color(red: 1.0, green: 0.72, blue: 0.25) }
        if m.contains("phase") || m.contains("can capture now") { return Color(red: 0.42, green: 0.86, blue: 0.55) }
        return theme.text
    }

    static func copy(_ lines: [String]) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)
    }
}

/// Settings > Debug.
struct DebugSettingsView: View {
    @ObservedObject var runner: SimRunner

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("TEST SPAWNER").font(.ui(size: 13, weight: .semibold))
            Toggle("Show the test spawner panel", isOn: $runner.testSpawner)
            Text("Place an aircraft at a chosen position, heading, altitude and speed, to reproduce a situation. You can click the scope to set the position.")
                .font(.ui(size: 11)).foregroundStyle(.secondary)
            Divider()
            Text("DEBUG LOG").font(.ui(size: 13, weight: .semibold))
            Toggle("Write a debug log", isOn: $runner.debugLogging)
            Text("Records every command (accepted, refused or dropped), approach progress and, for an aircraft cleared for an approach, why it has not captured the localiser yet. It does not change the simulation. A panel with the live log appears while this is on.")
                .font(.ui(size: 11)).foregroundStyle(.secondary)
            if runner.debugLogging, !runner.debugFilePath.isEmpty {
                Text(runner.debugFilePath).font(.ui(size: 10, design: .monospaced)).textSelection(.enabled)
                HStack {
                    Button("Reveal in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: runner.debugFilePath)])
                    }
                    Button("Copy last 200 lines") {
                        DebugLogView.copy(runner.debugEntries.suffix(200).map(\.text))
                    }
                }
            } else {
                Button("Open the log folder") {
                    try? FileManager.default.createDirectory(at: DebugLogFile.folder, withIntermediateDirectories: true)
                    NSWorkspace.shared.open(DebugLogFile.folder)
                }
            }
            Spacer()
        }
    }
}
