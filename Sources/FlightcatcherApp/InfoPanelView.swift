import SwiftUI
import SimCore

/// Small panel with airport data, wind, and the separation monitor.
struct InfoPanelView: View {
    let airport: AirportPackage?
    let conflicts: [Conflict]
    let lossCount: Int
    let wind: Wind
    let runways: [RunwayStatus]
    /// Where the wind comes from ("Real, METAR KBOS", "Random drift", "Fixed") and when the next live fetch is due.
    var windSource: String = ""
    var nextWeatherUpdate: Date? = nil
    @ObservedObject private var themeStore = ThemeStore.shared
    private var theme: Theme { themeStore.theme }

    private let mono = Font.ui(size: 12, design: .monospaced)

    private var elevationText: String {
        guard let airport else { return "--" }
        if let elevation = airport.elevationFt { return "\(elevation) ft" }
        return "--"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(airport?.title ?? "----").font(mono).foregroundStyle(theme.heading)
            if let airport, airport.city != nil {
                Text(airport.name).font(mono).foregroundStyle(theme.dimText)
            }
            row("ELEV", elevationText)
            row("TA", airport.map { "\($0.transitionAltitudeFt) ft" } ?? "--")
            row("WIND", wind.text + (wind.speedKt < 0.5 ? "" : " kt"))
            if !windSource.isEmpty {
                row("SRC", windSource)
            }
            if let next = nextWeatherUpdate {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let left = max(0, Int(next.timeIntervalSince(context.date)))
                    row("NEXT", left == 0 ? "due now" : String(format: "in %d:%02d", left / 60, left % 60))
                }
            }
            runwayLines
            Divider()
            HStack {
                Text("SEPARATION").font(mono).foregroundStyle(theme.heading)
                Spacer()
                Text("losses \(lossCount)").font(mono).foregroundStyle(lossCount == 0 ? theme.dimText : theme.alert)
            }
            Text("min \(Int(SeparationMinima.lateralNM)) NM / \(Int(SeparationMinima.verticalFt)) ft")
                .font(mono).foregroundStyle(theme.dimText)
            if conflicts.isEmpty {
                Text("no conflicts").font(mono).foregroundStyle(theme.dimText)
            } else {
                ForEach(conflicts.prefix(5)) { c in
                    Text(line(c))
                        .font(mono)
                        .foregroundStyle(c.kind == .loss ? theme.alert : theme.warning)
                }
                if conflicts.count > 5 {
                    Text("+\(conflicts.count - 5) more").font(mono).foregroundStyle(theme.dimText)
                }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Open runways one per line with their head and crosswind, closed ones together on one line.
    @ViewBuilder private var runwayLines: some View {
        let open = runways.filter(\.isOpen)
        let closed = runways.filter { !$0.isOpen }
        if !runways.isEmpty {
            if open.isEmpty {
                row("OPEN", "none")
            } else {
                ForEach(open.prefix(6)) { status in
                    Text("\(status.id.padding(toLength: 4, withPad: " ", startingAt: 0))open  \(windComponents(status))")
                        .font(mono)
                        .foregroundStyle(theme.text)
                }
                if open.count > 6 {
                    Text("+\(open.count - 6) more open").font(mono).foregroundStyle(theme.dimText)
                }
            }
            if !closed.isEmpty {
                row("CLSD", closed.map(\.id).joined(separator: " "), valueColour: theme.warning)
            }
        }
    }

    /// "head 8 / x 3": headwind (tailwind shown as "tail") and crosswind, whole knots.
    private func windComponents(_ status: RunwayStatus) -> String {
        let head = Int(status.headwindKt.rounded())
        let cross = Int(abs(status.crosswindKt).rounded())
        return (head < 0 ? "tail \(-head)" : "head \(head)") + " / x \(cross)"
    }

    private func row(_ label: String, _ value: String, valueColour: Color? = nil) -> some View {
        HStack(spacing: 8) {
            Text(label).font(mono).foregroundStyle(theme.dimText).frame(width: 44 * UIScale.factor, alignment: .leading)
            Text(value).font(mono).foregroundStyle(valueColour ?? theme.text)
        }
    }

    private func line(_ c: Conflict) -> String {
        switch c.kind {
        case .loss:
            return "\(c.first)/\(c.second) LOSS \(String(format: "%.1f", c.lateralNM)) NM \(Int(c.verticalFt.rounded())) ft"
        case .predicted:
            return "\(c.first)/\(c.second) in \(c.secondsToLoss) s"
        }
    }
}
