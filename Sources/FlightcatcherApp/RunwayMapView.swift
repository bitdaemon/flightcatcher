import SwiftUI
import SimCore

/// The runways drawn large, as if zoomed in on the airport: green when free, red while a departure is lined up, rolling
/// or just airborne, or an arrival is about to touch down; yellow while an arrival is cleared for an approach to it. Aircraft near the runways are drawn too.
struct RunwayMapView: View {
    @ObservedObject var runner: SimRunner
    @ObservedObject private var themeStore = ThemeStore.shared
    private var theme: Theme { themeStore.theme }

    private let free = Color(red: 0.30, green: 0.80, blue: 0.42)
    private let busy = Color(red: 0.95, green: 0.32, blue: 0.30)
    private let assigned = Color(red: 1.0, green: 0.82, blue: 0.25)

    /// One physical strip: both ends, in nautical miles from the airport reference.
    private struct Strip: Identifiable {
        let id: String
        let endA: String
        let endB: String
        let a: CGPoint // threshold of endA, (east, north)
        let b: CGPoint // threshold of endB
    }

    private var strips: [Strip] {
        guard let airport = runner.airport else { return [] }
        let proj = airport.referenceProjection
        var seen = Set<String>()
        var result: [Strip] = []
        for runway in airport.runways {
            let opposite = Simulation.oppositeRunway(runway.id)
            if seen.contains(runway.id) || seen.contains(opposite) { continue }
            seen.insert(runway.id)
            let start = proj.nm(lat: runway.thresholdLat, lon: runway.thresholdLon)
            var far = (east: start.east, north: start.north)
            if let other = airport.runways.first(where: { $0.id == opposite }) {
                far = proj.nm(lat: other.thresholdLat, lon: other.thresholdLon)
            } else {
                let o = LocalProjection.offset(bearingDeg: runway.trueBearingDeg, distanceNM: Double(runway.lengthM) / 1852)
                far = (east: start.east + o.east, north: start.north + o.north)
            }
            result.append(Strip(id: runway.id, endA: runway.id, endB: opposite,
                                a: CGPoint(x: start.east, y: start.north), b: CGPoint(x: far.east, y: far.north)))
        }
        return result
    }

    var body: some View {
        Canvas { ctx, size in
            draw(ctx, size: size)
        }
        .padding(4)
    }

    private func draw(_ ctx: GraphicsContext, size: CGSize) {
        let strips = strips
        guard !strips.isEmpty else {
            ctx.draw(Text("no runways").font(.ui(size: 12)).foregroundColor(theme.dimText),
                     at: CGPoint(x: size.width / 2, y: size.height / 2))
            return
        }
        // Fit all strips with a margin.
        let xs = strips.flatMap { [$0.a.x, $0.b.x] }
        let ys = strips.flatMap { [$0.a.y, $0.b.y] }
        let minX = xs.min()!, maxX = xs.max()!, minY = ys.min()!, maxY = ys.max()!
        let spanX = max(maxX - minX, 0.5), spanY = max(maxY - minY, 0.5)
        let margin: CGFloat = 26
        let scale = min((size.width - 2 * margin) / spanX, (size.height - 2 * margin) / spanY)
        let cx = (minX + maxX) / 2, cy = (minY + maxY) / 2
        func pt(_ east: Double, _ north: Double) -> CGPoint {
            CGPoint(x: size.width / 2 + (east - cx) * scale, y: size.height / 2 - (north - cy) * scale)
        }

        let uses = runner.runwayUses
        // Arrivals cleared for an approach, by runway end (nearest to touchdown listed first).
        var cleared: [String: [String]] = [:]
        for ac in runner.aircraft where ac.departure == nil && !ac.landed {
            if let app = ac.approach { cleared[app.ils.runwayId, default: []].append(ac.callsign) }
        }
        let status = Dictionary(uniqueKeysWithValues: runner.runwayStatuses.map { ($0.id, $0) })

        for strip in strips {
            let use = uses[strip.endA] ?? uses[strip.endB]
            let clearedHere = (cleared[strip.endA] ?? []) + (cleared[strip.endB] ?? [])
            let colour = use != nil ? busy : (clearedHere.isEmpty ? free : assigned)
            let p = pt(strip.a.x, strip.a.y), q = pt(strip.b.x, strip.b.y)
            var line = Path(); line.move(to: p); line.addLine(to: q)
            ctx.stroke(line, with: .color(theme.background), style: StrokeStyle(lineWidth: 13, lineCap: .butt))
            ctx.stroke(line, with: .color(colour.opacity(0.85)), style: StrokeStyle(lineWidth: 9, lineCap: .butt))
            ctx.stroke(line, with: .color(.white.opacity(0.55)), style: StrokeStyle(lineWidth: 1, dash: [6, 6]))

            // Direction vector away from the strip's start, for placing labels beyond the ends.
            let dx = q.x - p.x, dy = q.y - p.y
            let len = max((dx * dx + dy * dy).squareRoot(), 1)
            let ux = dx / len, uy = dy / len
            for (end, at, sign) in [(strip.endA, p, CGFloat(-1)), (strip.endB, q, CGFloat(1))] {
                let open = status[end]?.isOpen ?? true
                ctx.draw(Text(end).font(.ui(size: 11, weight: open ? .bold : .regular, design: .monospaced))
                            .foregroundColor(open ? theme.text : theme.dimText),
                         at: CGPoint(x: at.x + ux * sign * 16, y: at.y + uy * sign * 16))
            }
            if use == nil, !clearedHere.isEmpty {
                let text = "APP " + clearedHere.prefix(2).joined(separator: " ") + (clearedHere.count > 2 ? " +\(clearedHere.count - 2)" : "")
                ctx.draw(Text(text).font(.ui(size: 10, weight: .bold, design: .monospaced)).foregroundColor(assigned),
                         at: CGPoint(x: (p.x + q.x) / 2 - uy * 14, y: (p.y + q.y) / 2 + ux * 14))
            }
            if let use {
                let text: String
                switch use {
                case .departing(let callsign): text = "T/O \(callsign)"
                case .landing(let callsign, _): text = "LDG \(callsign)"
                }
                ctx.draw(Text(text).font(.ui(size: 10, weight: .bold, design: .monospaced)).foregroundColor(busy),
                         at: CGPoint(x: (p.x + q.x) / 2 - uy * 14, y: (p.y + q.y) / 2 + ux * 14))
            }
        }

        // Aircraft inside the view: a small triangle along the heading, with the callsign.
        for ac in runner.aircraft where !ac.handedToTower {
            let a = pt(ac.eastNM, ac.northNM)
            guard a.x > 0, a.x < size.width, a.y > 0, a.y < size.height else { continue }
            let h = ac.headingDeg * .pi / 180
            let f = CGPoint(x: sin(h), y: -cos(h))
            let s = CGPoint(x: -f.y, y: f.x)
            var tri = Path()
            tri.move(to: CGPoint(x: a.x + f.x * 6, y: a.y + f.y * 6))
            tri.addLine(to: CGPoint(x: a.x - f.x * 4 + s.x * 3.5, y: a.y - f.y * 4 + s.y * 3.5))
            tri.addLine(to: CGPoint(x: a.x - f.x * 4 - s.x * 3.5, y: a.y - f.y * 4 - s.y * 3.5))
            tri.closeSubpath()
            let selected = ac.callsign == runner.selectedCallsign
            ctx.fill(tri, with: .color(selected ? theme.selected : theme.aircraft))
            ctx.draw(Text(ac.callsign).font(.ui(size: 9, design: .monospaced))
                        .foregroundColor(selected ? theme.selected : theme.dimText),
                     at: CGPoint(x: a.x + 8, y: a.y - 6), anchor: .leading)
        }
    }
}
