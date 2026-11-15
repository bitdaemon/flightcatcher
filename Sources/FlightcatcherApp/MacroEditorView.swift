import SwiftUI
import AppKit
import SimCore

/// The Macros panel: the current airport's macros on the left, the selected one on the right. Styled like the other
/// panels (theme colours, monospaced text). Changes are saved at once; a macro with an error is kept but refused when run.
struct MacroEditorView: View {
    @ObservedObject var runner: SimRunner
    @State private var selection: UUID?
    @State private var runMessage: String?
    @State private var showHelp = false
    @ObservedObject private var themeStore = ThemeStore.shared
    private var theme: Theme { themeStore.theme }

    private let mono = Font.ui(size: 12, design: .monospaced)
    private let small = Font.ui(size: 11, design: .monospaced)

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 128 * UIScale.factor)
            Rectangle().fill(theme.panelBorder).frame(width: 1)
            Group {
                if let index = selectedIndex {
                    editor(index)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(runner.macros.isEmpty ? "NO MACROS FOR \(runner.airport?.icao ?? "-")" : "SELECT A MACRO")
                            .font(mono).foregroundStyle(theme.heading)
                        Text("+ adds one. Macros are saved per airport.").font(small).foregroundStyle(theme.dimText)
                        Spacer()
                    }
                    .padding(8)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .clipped()
        .onAppear { if selection == nil { selection = runner.macros.first?.id } }
    }

    private var selectedIndex: Int? {
        guard let selection else { return nil }
        return runner.macros.firstIndex { $0.id == selection }
    }

    private func compile(_ macro: Macro) -> Result<CompiledMacro, MacroError> {
        MacroCompiler.compile(macro, knownFixes: runner.fixIds, approaches: runner.approachJoins)
    }

    // MARK: List

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(MacroPhase.allCases, id: \.self) { phase in
                        let items = runner.macros.filter { $0.phase == phase }.sorted { $0.name < $1.name }
                        if !items.isEmpty {
                            Text(phase.label.uppercased()).font(small).foregroundStyle(theme.heading)
                                .padding(.horizontal, 6).padding(.top, 6).padding(.bottom, 2)
                            ForEach(items) { macro in row(macro) }
                        }
                    }
                }
            }
            Rectangle().fill(theme.panelBorder).frame(height: 1)
            HStack(spacing: 10) {
                iconButton("plus", "New macro") { addMacro() }
                iconButton("plus.square.on.square", "Duplicate") { duplicateSelected() }.disabled(selectedIndex == nil)
                iconButton("minus", "Delete") { deleteSelected() }.disabled(selectedIndex == nil)
                Spacer()
            }
            .padding(6)
        }
        .disabled(runner.airport == nil)
    }

    private func row(_ macro: Macro) -> some View {
        let isSelected = macro.id == selection
        let broken: Bool = { if case .failure = compile(macro) { return true }; return false }()
        return HStack(spacing: 4) {
            Text(macro.name.isEmpty ? "(no name)" : macro.name)
                .font(mono)
                .foregroundStyle(isSelected ? theme.selected : theme.text)
            Spacer(minLength: 0)
            if broken { Text("!").font(mono).foregroundStyle(theme.warning).help("Has an error; will not run") }
        }
        .padding(.horizontal, 6).padding(.vertical, 2)
        .background(isSelected ? theme.rowHighlight : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture { selection = macro.id; runMessage = nil }
    }

    private func iconButton(_ symbol: String, _ help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.ui(size: 11)).foregroundStyle(theme.text)
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func uniqueName(_ base: String) -> String {
        let taken = Set(runner.macros.map { $0.name.uppercased() })
        if !taken.contains(base) { return base }
        var n = 2
        while taken.contains("\(base)\(n)") { n += 1 }
        return "\(base)\(n)"
    }

    private func addMacro() {
        let phase = runner.selectedCallsign
            .flatMap { cs in runner.aircraft.first { $0.callsign == cs } }
            .map(MacroPhase.of) ?? .arrival
        let macro = Macro(name: uniqueName("NEW"), phase: phase, text: "")
        runner.macros.append(macro)
        selection = macro.id
    }

    private func duplicateSelected() {
        guard let index = selectedIndex else { return }
        var copy = runner.macros[index]
        copy.id = UUID()
        copy.name = uniqueName(String(copy.name.prefix(10)))
        runner.macros.append(copy)
        selection = copy.id
    }

    private func deleteSelected() {
        guard let index = selectedIndex else { return }
        runner.macros.remove(at: index)
        selection = runner.macros.first?.id
    }

    // MARK: Editor

    private func editor(_ index: Int) -> some View {
        let macro = runner.macros[index]
        let compiled = compile(macro)
        let duplicate = runner.macros.contains { $0.id != macro.id && $0.name.uppercased() == macro.name.uppercased() }
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                label("NAME")
                TextField("", text: Binding(
                    get: { runner.macros[safe: index]?.name ?? "" },
                    set: { typed in
                        // Spaces become "_" and anything else that cannot be in a name is dropped, so the name
                        // can be typed on the command bar as one word.
                        let cleaned = typed.uppercased().map { $0 == " " ? "_" : $0 }
                            .filter { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }
                        runner.macros[index].name = String(String(cleaned).prefix(12))
                    }))
                    .textFieldStyle(.plain)
                    .font(mono)
                    .foregroundStyle(theme.text)
                    .padding(.horizontal, 4).padding(.vertical, 2)
                    .overlay(Rectangle().stroke(theme.panelBorder, lineWidth: 1))
                    .frame(width: 110 * UIScale.factor)
                Spacer(minLength: 0)
                ForEach(MacroPhase.allCases, id: \.self) { phase in
                    let on = macro.phase == phase
                    Button { runner.macros[index].phase = phase } label: {
                        Text(phase == .departure ? "DEP" : phase == .arrival ? "ARR" : "GND")
                            .font(small)
                            .foregroundStyle(on ? theme.selected : theme.dimText)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .overlay(Rectangle().stroke(on ? theme.selected : theme.panelBorder, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .help(phase.label)
                }
            }

            label("STEPS, ONE PER LINE")
            TextEditor(text: Binding(
                get: { runner.macros[safe: index]?.text ?? "" },
                set: { runner.macros[index].text = $0 }))
                .font(mono)
                .foregroundStyle(theme.text)
                .scrollContentBackground(.hidden)
                .background(theme.background.opacity(0.6))
                .autocorrectionDisabled()
                .frame(minHeight: 60, maxHeight: .infinity)
                .overlay(Rectangle().stroke(theme.panelBorder, lineWidth: 1))

            status(compiled, duplicate: duplicate)

            HStack(spacing: 8) {
                let canRun = runner.selectedCallsign != nil && !duplicate && (try? compiled.get()) != nil
                Button { runOnSelected(macro) } label: {
                    Text("RUN ON \(runner.selectedCallsign ?? "SELECTED")")
                        .font(small)
                        .foregroundStyle(canRun ? theme.selected : theme.dimText)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .overlay(Rectangle().stroke(canRun ? theme.selected : theme.panelBorder, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .disabled(!canRun)
                if let runMessage {
                    Text(runMessage).font(small).foregroundStyle(theme.dimText).lineLimit(1).truncationMode(.tail)
                }
                Spacer(minLength: 0)
                Button { showHelp.toggle() } label: {
                    Text(showHelp ? "HIDE HELP" : "HELP").font(small).foregroundStyle(theme.dimText)
                }
                .buttonStyle(.plain)
            }
            if showHelp { help }
        }
        .padding(8)
    }

    private func label(_ text: String) -> some View {
        Text(text).font(small).foregroundStyle(theme.heading)
    }

    @ViewBuilder
    private func status(_ compiled: Result<CompiledMacro, MacroError>, duplicate: Bool) -> some View {
        if duplicate {
            Text("Another macro has this name").font(small).foregroundStyle(theme.warning)
        }
        switch compiled {
        case .failure(let error):
            Text(error.description).font(small).foregroundStyle(theme.alert)
                .fixedSize(horizontal: false, vertical: true)
        case .success(let c):
            VStack(alignment: .leading, spacing: 1) {
                ForEach(Array(c.steps.enumerated()), id: \.offset) { n, step in
                    Text("\(n + 1) \(step.trigger.map { $0.tagLabel + " " } ?? "")› "
                         + step.commands.map(\.chipLabel).joined(separator: " "))
                        .font(small).foregroundStyle(theme.ok)
                        .lineLimit(1).truncationMode(.tail)
                }
            }
        }
    }

    private var help: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("codes as on the command bar: d30 h270l s180 p cape i4r j I27.AYBEE ho").font(small)
            Text("codes on one line go out as one call").font(small)
            Text("triggers:  at CAPE:   when alt<4000:   when spd<=180:").font(small)
            Text("run: CALLSIGN mac NAME, stop: mac-, or MAC on the ring").font(small)
            Text("your own instruction cancels it; a refusal stops it (M!)").font(small)
        }
        .foregroundStyle(theme.dimText)
    }

    private func runOnSelected(_ macro: Macro) {
        guard let callsign = runner.selectedCallsign else { return }
        if let reason = runner.runMacro(named: macro.name, on: callsign) {
            runMessage = "not started: \(reason)"
            NSSound.beep()
        } else {
            runMessage = "running on \(callsign)"
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
