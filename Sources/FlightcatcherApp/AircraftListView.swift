import SwiftUI
import SimCore

/// Every aircraft, with the last instructions given to it on a second line. Clicking a row selects it; the selected
/// aircraft gets approach-clearance buttons and its instruction history. Shown inside a floating panel.
struct AircraftListView: View {
    @ObservedObject var runner: SimRunner
    @ObservedObject private var themeStore = ThemeStore.shared
    private var theme: Theme { themeStore.theme }

    private let mono = Font.ui(size: 12, design: .monospaced)

    private var runwayIds: [String] {
        (runner.airport?.runways ?? []).map(\.id)
    }

    private var selectedAircraft: Aircraft? {
        runner.aircraft.first { $0.callsign == runner.selectedCallsign }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let ac = selectedAircraft {
                markerControls(ac)
                Text("\(ac.callsign): instructions")
                    .font(mono)
                    .foregroundStyle(theme.selected)
                let history = (runner.commandHistory[ac.callsign] ?? []).suffix(3)
                if history.isEmpty {
                    Text("none yet").font(mono).foregroundStyle(theme.dimText)
                } else {
                    ForEach(Array(history)) { record in
                        let pending = record.isPending(at: runner.tickCount)
                        Text("\(clock(record.issuedTick))  \(record.label)" + (pending ? "  waiting for pilot" : ""))
                            .font(mono)
                            .foregroundStyle(pending ? theme.warning : theme.dimText)
                    }
                }
                if ac.departure == nil {
                    VStack(spacing: 4) {
                        Menu("Clear for approach") {
                            ForEach(runwayIds, id: \.self) { runway in
                                let open = openRunwayIds.contains(runway)
                                Button("\(hasILS(runway) ? "ILS" : "Visual") runway \(runway)" + (open ? "" : "  (closed)")) {
                                    clear(ac, runway: runway)
                                }
                                .disabled(!open)
                            }
                        }
                        Menu("Join approach at a fix") {
                            ForEach(approaches, id: \.id) { proc in
                                Button("\(proc.id)  via \(proc.legs.first?.fixId ?? "?")") { join(ac, proc) }
                            }
                        }
                        Button("Hand off to tower") { send(.handoff, to: ac) }
                            .frame(maxWidth: .infinity)
                            .disabled(ac.handedToTower || (ac.approach.map { $0.phase == .intercepting } ?? true))
                            .help("Available once established on the localiser")
                    }
                } else {
                    VStack(spacing: 4) {
                        Button("Line up") { send(.lineUp, to: ac) }
                            .frame(maxWidth: .infinity)
                            .disabled(ac.groundPhase != .holdingShort)
                        Button("Cleared for take-off") { send(.takeoff, to: ac) }
                            .frame(maxWidth: .infinity)
                            .disabled(ac.groundPhase != .holdingShort && ac.groundPhase != .linedUp)
                        Button("Hand off") { send(.handoff, to: ac) }
                            .frame(maxWidth: .infinity)
                            .disabled(ac.isOnGround)
                    }
                }
            }
            if selectedAircraft != nil { Divider() }
            Text("CALLSIGN".padding(toLength: 9, withPad: " ", startingAt: 0) + "ALT SPD HDG NAV    TYPE")
                .font(mono)
                .foregroundStyle(theme.dimText)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    let arrivals = StripOrder.arrivals(runner.aircraft)
                    let departures = StripOrder.departures(runner.aircraft)
                    sectionHeader("ARRIVALS", count: arrivals.count)
                    ForEach(arrivals) { ac in row(ac) }
                    sectionHeader("DEPARTURES", count: departures.count)
                    ForEach(departures) { ac in row(ac) }
                }
            }
            .frame(maxHeight: .infinity)

        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func sectionHeader(_ title: String, count: Int) -> some View {
        HStack {
            Text(title).font(mono).foregroundStyle(theme.heading)
            Text("\(count)").font(mono).foregroundStyle(theme.dimText)
            Rectangle().fill(theme.panelBorder).frame(height: 1)
        }
        .padding(.top, 6)
        .padding(.bottom, 2)
        .padding(.horizontal, 4)
    }

    /// Second line of a departure with no instructions yet: runway and SID.
    private func departureInfo(_ ac: Aircraft) -> String? {
        guard let d = ac.departure else { return nil }
        let level = ac.isOnGround ? "" : "  initial \(d.initialAltitudeFt) ft"
        return "RWY \(d.runway)  \(d.sid.split(separator: ".").first.map(String.init) ?? d.sid)\(level)"
    }

    private func levelLabel(_ feet: Int) -> String {
        feet > (runner.airport?.transitionAltitudeFt ?? 5000) ? "FL\(Phraseology.pad3(feet / 100))" : "\(feet) ft"
    }

    /// Departure strips always show the flight-plan level and where the handoff becomes possible.
    private func departurePlan(_ ac: Aircraft) -> String? {
        guard let d = ac.departure else { return nil }
        return "plan \(levelLabel(d.expectedLevelFt))  handoff \(levelLabel(d.handoffAltitudeFt))"
    }

    private func clock(_ tick: Int) -> String { String(format: "%02d:%02d", tick / 60, tick % 60) }

    /// The last three instructions, oldest first; "..." marks one the pilot has not started on yet.
    private func lastCommands(_ ac: Aircraft) -> String? {
        guard let records = runner.commandHistory[ac.callsign], let latest = records.last else { return nil }
        let labels = records.suffix(3).map { $0.label + ($0.isPending(at: runner.tickCount) ? "..." : "") }
        return "\(clock(latest.issuedTick))  " + labels.joined(separator: " · ")
    }

    private var approaches: [Procedure] {
        (runner.airport?.procedures ?? []).filter { $0.kind == .approach && runner.availableProcedures.contains($0.id) }
    }

    private var openRunwayIds: Set<String> {
        Set(runner.runwayStatuses.filter(\.isOpen).map(\.id))
    }

    /// Direct to the approach's first fix, then the approach legs, cleared ILS.
    private func join(_ ac: Aircraft, _ proc: Procedure) {
        guard let runway = proc.runways.first, let via = proc.legs.first?.fixId else { return }
        let command = Command.joinApproach(procedure: proc.id, runway: runway, via: via)
        if case .refused = runner.issue(IssuedCommand(callsign: ac.callsign, command: command)) { NSSound.beep() }
    }

    private func send(_ command: Command, to ac: Aircraft) {
        if case .refused = runner.issue(IssuedCommand(callsign: ac.callsign, command: command)) { NSSound.beep() }
    }

    /// Six colour swatches (and none) to mark the aircraft, and a switch for drawing its assigned procedure.
    private func markerControls(_ ac: Aircraft) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text("Mark").font(mono).foregroundStyle(theme.dimText)
                Button { runner.setMarker(nil, for: ac.callsign) } label: {
                    Image(systemName: "nosign").foregroundStyle(theme.dimText)
                }
                .buttonStyle(.plain)
                .help("No colour")
                ForEach(Array(AircraftMarkers.palette.enumerated()), id: \.offset) { index, marker in
                    Button { runner.setMarker(index, for: ac.callsign) } label: {
                        Circle()
                            .fill(Color(hex: marker.rgb))
                            .frame(width: 14, height: 14)
                            .overlay(Circle().stroke(theme.text, lineWidth: runner.markerColours[ac.callsign] == index ? 2 : 0))
                    }
                    .buttonStyle(.plain)
                    .help(marker.name)
                }
            }
            if let id = ac.procedureId {
                let name = id.split(separator: ".").first.map(String.init) ?? id
                let shown = runner.shownProcedures.contains(ac.callsign)
                Button { runner.toggleProcedure(for: ac.callsign) } label: {
                    Text("\(shown ? "Hide" : "Show") \(name) on scope").font(mono)
                }
                .help("Show or hide this aircraft's assigned procedure on the scope")
            } else {
                Text("No assigned procedure").font(mono).foregroundStyle(theme.dimText)
            }
        }
        .padding(.vertical, 2)
    }

    private func hasILS(_ runway: String) -> Bool {
        runner.airport?.runways.first { $0.id == runway }?.ils != nil
    }

    private func clear(_ ac: Aircraft, runway: String) {
        let result = runner.issue(IssuedCommand(callsign: ac.callsign, command: .approach(runway: runway)))
        if case .refused = result { NSSound.beep() }
    }

    private func row(_ ac: Aircraft) -> some View {
        let isSelected = ac.callsign == runner.selectedCallsign
        let heading = Int(ac.headingDeg.rounded())
        let columns = [
            Phraseology.pad3(Int((ac.altitudeFt / 100).rounded())),
            Phraseology.pad3(Int(ac.speedKt.rounded())),
            Phraseology.pad3(heading == 0 ? 360 : heading),
        ].joined(separator: " ")

        let handedOver = ac.handedToTower || (ac.departure?.handedOff ?? false)
        let main = ac.callsign.padding(toLength: 9, withPad: " ", startingAt: 0) + columns + " "
            + ac.navLabel.padding(toLength: 6, withPad: " ", startingAt: 0) + " " + (ac.typeCode ?? "")
        // Handed over: callsign, type and who has it now, greyed out like its box on the scope.
        let reduced = ac.callsign.padding(toLength: 9, withPad: " ", startingAt: 0)
            + (ac.departure == nil ? "TWR" : "HANDED OFF") + "  " + (ac.typeCode ?? "")
        return VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 5) {
                Circle()
                    .fill(handedOver ? Color.clear
                          : (runner.markerColours[ac.callsign].map { Color(hex: AircraftMarkers.palette[$0].rgb) } ?? Color.clear))
                    .frame(width: 8, height: 8)
                Text(handedOver ? reduced : main)
                    .font(mono)
                    .foregroundStyle(handedOver ? theme.dimText.opacity(0.75) : (isSelected ? theme.selected : theme.text))
                if !handedOver, let emergency = ac.emergency {
                    Text(emergency.urgencyWord)
                        .font(.ui(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4)
                        .background(Color(red: 1.0, green: 0.27, blue: 0.24), in: RoundedRectangle(cornerRadius: 3))
                        .help(emergency.phrase)
                }
            }
            if !handedOver {
                Text(lastCommands(ac) ?? departureInfo(ac) ?? "no instructions yet")
                    .font(.ui(size: 11, design: .monospaced))
                    .foregroundStyle(theme.dimText)
                if let plan = departurePlan(ac) {
                    Text(plan)
                        .font(.ui(size: 11, design: .monospaced))
                        .foregroundStyle(theme.heading)
                }
            }
        }
            .padding(.vertical, 3)
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? theme.rowHighlight.opacity(handedOver ? 0.5 : 1) : Color.clear)
            .contentShape(Rectangle())
            .onTapGesture { runner.selectedCallsign = ac.callsign }
    }
}
