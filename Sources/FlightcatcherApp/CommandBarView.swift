import SwiftUI
import AppKit
import SimCore

/// Radio log, live preview and the command line. All parsing lives in SimCore's `CommandBar`.
struct CommandBarView: View {
    @ObservedObject var runner: SimRunner
    @ObservedObject var controls: ControlModel
    @State private var input = ""
    @State private var tabState = TabState()
    @FocusState private var focused: Bool
    @ObservedObject private var themeStore = ThemeStore.shared
    private var theme: Theme { themeStore.theme }

    private let mono = Font.ui(size: 13, design: .monospaced)

    private var result: CommandBarResult {
        CommandBar.evaluate(input: input, aircraft: runner.aircraft, selected: runner.selectedCallsign,
                            knownFixes: runner.fixIds, approaches: runner.approachJoins)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(result.message.isEmpty ? " " : result.message)
                .font(mono)
                .foregroundStyle(previewColor(result.status))

            HStack(spacing: 6) {
                Text(runner.selectedCallsign.map { "\($0) >" } ?? ">")
                    .font(mono)
                    .foregroundStyle(runner.selectedCallsign == nil ? theme.heading : theme.selected)
                TextField("callsign d70 s180 h270l i28l p kerav ... (chain codes)", text: $input)
                    .textFieldStyle(.plain)
                    .font(mono)
                    .foregroundStyle(theme.text)
                    .focused($focused)
                    .onSubmit(submit)
                    .onKeyPress(.tab) {
                        if let completed = CommandBar.tabComplete(input: input, aircraft: runner.aircraft, state: &tabState) {
                            input = completed
                        }
                        return .handled
                    }
                    .onKeyPress(.escape) {
                        if input.isEmpty && controls.escape() { return .handled }
                        input = ""
                        runner.selectedCallsign = nil
                        controls.cancelAll()
                        return .handled
                    }
            }
        }
        .padding(10)
        .background(theme.panel)
        .overlay(alignment: .top) { Rectangle().fill(theme.panelBorder).frame(height: 1) }
        .onAppear { focused = true }
    }

    private func submit() {
        defer { focused = true }
        // An empty line sends the chips collected with the mouse.
        if input.trimmingCharacters(in: .whitespaces).isEmpty, !controls.chain.isEmpty {
            controls.send(using: runner)
            return
        }
        let current = result
        if current.status == .ready, let request = current.macro {
            switch request {
            case .run(let callsign, let name):
                if let reason = runner.runMacro(named: name, on: callsign) {
                    controls.tell("\(callsign): macro not started, \(reason)")
                    NSSound.beep()
                    return
                }
                runner.selectedCallsign = callsign
            case .cancel(let callsign):
                if !runner.cancelMacro(on: callsign) {
                    controls.tell("\(callsign) is not running a macro")
                    NSSound.beep()
                    return
                }
                runner.selectedCallsign = callsign
            }
            input = ""
            return
        }
        guard current.status == .ready, let issued = current.issued else {
            if let callsign = current.selects {
                runner.selectedCallsign = callsign
                input = ""
            } else {
                NSSound.beep()
            }
            return
        }
        var anyRefused = false
        for command in current.issuedAll {
            if case .refused = runner.issue(command) { anyRefused = true }
        }
        if anyRefused { NSSound.beep() }
        runner.selectedCallsign = issued.callsign
        input = ""
    }

    private func previewColor(_ status: CommandBarResult.Status) -> Color {
        switch status {
        case .ready: return theme.ok
        case .error: return theme.alert
        case .incomplete: return theme.warning
        case .empty: return theme.dimText
        }
    }
}
