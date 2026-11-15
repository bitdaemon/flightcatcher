import SwiftUI
import AppKit
import Charts
import SimCore

/// End-of-session debrief: score and grade, breakdown, chart, worst moments, efficiency and best scores.
struct DebriefView: View {
    let card: ScoreCard
    let airportTitle: String
    let best: [ScoreRecord]
    /// Place of this session in the best-scores table, if it made it.
    let place: Int?
    let seed: UInt64
    let onResume: () -> Void
    let onNewSession: () -> Void
    let onReplaySeed: () -> Void

    @ObservedObject private var themeStore = ThemeStore.shared
    private var theme: Theme { themeStore.theme }
    private let mono = Font.ui(size: 12, design: .monospaced)

    private var seconds: Int { card.durationSeconds(now: card.endTick ?? card.startTick) }

    private func clock(_ s: Int) -> String { String(format: "%d:%02d", s / 60, s % 60) }
    private func signed(_ p: Int) -> String { p > 0 ? "+\(p)" : (p < 0 ? "\u{2212}\(-p)" : "0") }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header
                    Divider()
                    breakdown
                    Divider()
                    chart
                    Divider()
                    worst
                    Divider()
                    efficiency
                    Divider()
                    bestTable
                }
                .padding(18)
            }
            Divider()
            HStack {
                Button("Quit") { NSApplication.shared.terminate(nil) }
                    .help("Quit flightcATCher (the score is already saved in the best-scores table)")
                Button("Replay this seed", action: onReplaySeed)
                    .help("Start again with the same traffic seed (\(seed)) to beat this score")
                Spacer()
                Button("New session", action: onNewSession)
                Button("Resume", action: onResume)
                    .keyboardShortcut(.defaultAction)
                    .help("Close the debrief and carry on; points count again")
            }
            .padding(12)
        }
        .frame(minWidth: 620, idealWidth: 660, minHeight: 560, idealHeight: 720)
        .background(theme.panel)
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("SESSION DEBRIEF").font(.ui(size: 13, weight: .semibold, design: .monospaced)).foregroundStyle(theme.heading)
                Text(airportTitle).font(mono).foregroundStyle(theme.text)
                Text("\(clock(seconds)) played, multiplier \u{00D7}\(String(format: "%.2f", card.multiplier))")
                    .font(mono).foregroundStyle(theme.dimText)
                if let place {
                    Text(place == 1 ? "New best score for this airport" : "Number \(place) in this airport's best scores")
                        .font(mono).foregroundStyle(theme.ok)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(card.total.formatted()).font(.ui(size: 34, weight: .bold, design: .monospaced)).foregroundStyle(theme.heading)
                if let grade = card.grade {
                    Text("\(grade.rawValue)  \(grade.rank)").font(.ui(size: 14, weight: .semibold, design: .monospaced))
                        .foregroundStyle(grade == .e || grade == .d ? theme.alert : theme.selected)
                } else {
                    Text("no aircraft handled yet").font(mono).foregroundStyle(theme.dimText)
                }
            }
        }
    }

    private var breakdown: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("BREAKDOWN").font(mono).foregroundStyle(theme.heading)
            ForEach(ScoreCategory.allCases) { category in
                let points = card.points(in: category)
                if points != 0 {
                    line(category.title, signed(points), colour: points < 0 ? theme.alert : theme.text)
                }
            }
            line("Raw total", signed(card.raw), colour: theme.text)
            line("\u{00D7} multiplier", String(format: "%.2f", card.multiplier), colour: theme.dimText)
            Text(" ").font(.ui(size: 4))
            let hours = max(Double(seconds) / 3600, 1.0 / 60)
            line("Arrivals to tower", "\(card.arrivalsHandled)", colour: theme.text)
            line("Departures handed off", "\(card.departuresHandled)", colour: theme.text)
            line("Throughput", String(format: "%.1f /h", Double(card.arrivalsHandled + card.departuresHandled) / hours), colour: theme.text)
            line("Losses of separation", "\(card.losses)", colour: card.losses > 0 ? theme.alert : theme.text)
            line("Go-arounds you caused", "\(card.controllerGoArounds)", colour: card.controllerGoArounds > 0 ? theme.warning : theme.text)
            line("Missed handoffs", "\(card.missedHandoffs)", colour: card.missedHandoffs > 0 ? theme.warning : theme.text)
            line("Instructions per arrival", card.instructionsPerArrival.map { String(format: "%.1f", $0) } ?? "--", colour: theme.text)
        }
    }

    private var chart: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("SCORE AND TRAFFIC OVER THE SESSION").font(mono).foregroundStyle(theme.heading)
            if card.samples.count < 2 {
                Text("Play at least two minutes for a chart.").font(mono).foregroundStyle(theme.dimText)
            } else {
                Chart(card.samples, id: \.minute) { s in
                    LineMark(x: .value("Minute", s.minute), y: .value("Score", s.rawScore))
                        .foregroundStyle(theme.selected)
                }
                .chartXAxisLabel("minutes")
                .chartYAxisLabel("raw score")
                .frame(height: 120)
                Chart {
                    ForEach(card.samples, id: \.minute) { s in
                        LineMark(x: .value("Minute", s.minute), y: .value("Per hour", s.arrivalsPerHour))
                            .foregroundStyle(by: .value("Traffic", "Arrivals"))
                        LineMark(x: .value("Minute", s.minute), y: .value("Per hour", s.departuresPerHour))
                            .foregroundStyle(by: .value("Traffic", "Departures"))
                    }
                }
                .chartXAxisLabel("minutes")
                .chartYAxisLabel("per hour")
                .frame(height: 90)
            }
        }
    }

    private var worst: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("WORST MOMENTS").font(mono).foregroundStyle(theme.heading)
            let moments = card.worstMoments()
            if moments.isEmpty {
                Text("None. Clean session.").font(mono).foregroundStyle(theme.ok)
            }
            ForEach(moments) { e in
                HStack(alignment: .top, spacing: 8) {
                    Text(clock(max(0, e.tick - card.startTick))).font(mono).foregroundStyle(theme.dimText)
                        .frame(width: 52, alignment: .leading)
                    Text(e.text).font(mono).foregroundStyle(e.points <= -100 ? theme.alert : theme.warning)
                }
            }
        }
    }

    private var efficiency: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("ARRIVAL EFFICIENCY").font(mono).foregroundStyle(theme.heading)
            if card.arrivals.isEmpty {
                Text("No arrivals handed to the tower yet.").font(mono).foregroundStyle(theme.dimText)
            } else {
                let sorted = card.arrivals.sorted {
                    Double($0.actualSeconds) / Double(max($0.cleanSeconds, 1)) < Double($1.actualSeconds) / Double(max($1.cleanSeconds, 1))
                }
                if let b = sorted.first { timing("Best", b) }
                if sorted.count > 1, let w = sorted.last { timing("Worst", w) }
                Text("Clean time: straight distance from hand-in to the threshold \u{00D7} 1.3 at 210 kt. Up to 1.2 times clean earns +30, none from 2 times.")
                    .font(.ui(size: 10)).foregroundStyle(theme.dimText)
            }
        }
    }

    private func timing(_ label: String, _ a: ArrivalTiming) -> some View {
        line("\(label): \(a.callsign)", "\(clock(a.actualSeconds)) vs \(clock(a.cleanSeconds)) clean, \(a.instructions) instr, \(signed(a.bonus))",
             colour: theme.text)
    }

    private var bestTable: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("BEST SCORES HERE").font(mono).foregroundStyle(theme.heading)
            if best.isEmpty {
                Text("None yet.").font(mono).foregroundStyle(theme.dimText)
            }
            ForEach(Array(best.prefix(5).enumerated()), id: \.offset) { i, r in
                HStack(spacing: 8) {
                    Text("\(i + 1).").font(mono).foregroundStyle(theme.dimText).frame(width: 22, alignment: .trailing)
                    Text(r.total.formatted()).font(mono).foregroundStyle(theme.text).frame(width: 70, alignment: .trailing)
                    Text(r.grade).font(mono).foregroundStyle(theme.selected).frame(width: 16)
                    Text(r.date.formatted(date: .abbreviated, time: .shortened)).font(mono).foregroundStyle(theme.dimText)
                    Text("\(r.minutes) min, \(r.traffic)").font(mono).foregroundStyle(theme.dimText).lineLimit(1)
                    if r.fixedSeed && r.seed == seed { Text("same seed").font(mono).foregroundStyle(theme.ok) }
                }
            }
        }
    }

    private func line(_ label: String, _ value: String, colour: Color) -> some View {
        HStack {
            Text(label).font(mono).foregroundStyle(theme.dimText)
            Spacer()
            Text(value).font(mono).foregroundStyle(colour)
        }
    }
}
