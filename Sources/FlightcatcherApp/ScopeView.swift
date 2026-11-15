import SwiftUI
import SimCore

/// Radar scope. Canvas is redrawn when its inputs change; static layers can be cached later.
struct ScopeView: View {
    let airport: AirportPackage
    let aircraft: [Aircraft]
    let selected: String?
    let showCompass: Bool
    let showFixes: Bool
    let showStars: Bool
    let showSids: Bool
    let showApproaches: Bool
    let hiddenProcedures: Set<String>
    /// Procedures whose runways the wind currently allows; the others are not drawn.
    let availableProcedures: Set<String>
    let conflicts: [Conflict]
    let runwayStatuses: [RunwayStatus]
    /// Colour index per callsign (`AircraftMarkers.palette`), and aircraft whose assigned procedure is drawn.
    let markerColours: [String: Int]
    let shownProcedures: Set<String>
    /// Text for a third tag line (the last instructions), by callsign.
    let commandTags: [String: String]
    let autoDeclutter: Bool
    @ObservedObject var tags: TagModel
    @ObservedObject var controls: ControlModel
    /// Sends the collected chips (the Send button on the chip strip).
    let onSend: () -> Void
    /// Called with the clicked aircraft's callsign, or nil when empty space is clicked.
    let onSelect: (String?) -> Void
    @Binding var pxPerNM: CGFloat
    /// Sets (or with nil clears) an aircraft's marker colour, from the colour button on the ring.
    var onMark: ((Int?, String) -> Void)? = nil
    /// Macro line for the track tag ("M APPR 2/4 @CAPE"), by callsign.
    var macroTags: [String: String] = [:]
    /// Edge of the player's airspace, drawn as a dashed circle.
    var areaRadiusNM: Double = 40
    /// Names of the macros that suit an aircraft, for the ring's MAC menu.
    var macroChoices: ((Aircraft) -> [String])? = nil
    /// Run a macro (name) or, with nil, stop the aircraft's macro.
    var onMacro: ((String?, String) -> Void)? = nil
    /// While true a click reports the scope position (east and north, NM) instead of selecting (test spawner).
    var placing: Bool = false
    var onPlace: ((Double, Double) -> Void)? = nil

    @State private var panOffset: CGSize = .zero
    @GestureState private var dragDelta: CGSize = .zero
    @GestureState private var pinch: CGFloat = 1

    @ObservedObject private var themeStore = ThemeStore.shared
    private var theme: Theme { themeStore.theme }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                Canvas { ctx, size in
                    draw(ctx, size: size)
                }
                .gesture(
                    DragGesture()
                        .updating($dragDelta) { value, state, _ in
                            // A drag that starts on a tag moves the tag; anywhere else it pans.
                            let onTag = tags.dragging != nil || tagAt(value.startLocation, size: geo.size) != nil
                            if controls.mode != .heading && !onTag { state = value.translation }
                        }
                        .onChanged { value in
                            if controls.mode == .heading { controls.hover = value.location; return }
                            if tags.dragging == nil, let callsign = tagAt(value.startLocation, size: geo.size) {
                                tags.beginDrag(callsign)
                            }
                            if tags.dragging != nil { tags.drag(by: value.translation) }
                        }
                        .onEnded { value in
                            if controls.mode == .heading {
                                commitHeading(at: value.location, size: geo.size)
                            } else if tags.dragging != nil {
                                tags.endDrag()
                            } else {
                                panOffset.width += value.translation.width
                                panOffset.height += value.translation.height
                            }
                        }
                )
                .simultaneousGesture(
                    MagnifyGesture()
                        .updating($pinch) { value, state, _ in state = value.magnification }
                        .onEnded { value in
                            pxPerNM = min(max(pxPerNM * value.magnification, 4), 600)
                        }
                )
                .simultaneousGesture(
                    SpatialTapGesture()
                        .onEnded { tap in handleTap(at: tap.location, size: geo.size) }
                )

                controlOverlays(size: geo.size)
            }
            .onContinuousHover { phase in
                if case .active(let location) = phase, controls.mode == .heading || controls.mode == .direct || controls.mode == .crossFix {
                    controls.hover = location
                }
            }
            .overlay(RightClickCatcher { location in rightClick(at: location, size: geo.size) })
            .onChange(of: aircraft) { _, _ in relayout(size: geo.size, force: false) }
            .onChange(of: commandTags) { _, _ in relayout(size: geo.size, force: false) }
            .onChange(of: pxPerNM) { _, _ in relayout(size: geo.size, force: false) }
            .onChange(of: tags.declutterRequest) { _, _ in relayout(size: geo.size, force: true) }
        }
    }

    // MARK: Coordinates and hit testing

    private func viewTransform(size: CGSize) -> (cx: CGFloat, cy: CGFloat, scale: CGFloat) {
        (size.width / 2 + panOffset.width + dragDelta.width,
         size.height / 2 + panOffset.height + dragDelta.height,
         min(max(pxPerNM * pinch, 4), 600))
    }

    private func screenPoint(of ac: Aircraft, size: CGSize) -> CGPoint {
        screen(east: ac.eastNM, north: ac.northNM, size: size)
    }

    private func screen(east: Double, north: Double, size: CGSize) -> CGPoint {
        let t = viewTransform(size: size)
        return CGPoint(x: t.cx + CGFloat(east) * t.scale, y: t.cy - CGFloat(north) * t.scale)
    }

    private func screen(lat: Double, lon: Double, size: CGSize) -> CGPoint {
        let q = airport.referenceProjection.nm(lat: lat, lon: lon)
        return screen(east: q.east, north: q.north, size: size)
    }

    private var targetAircraft: Aircraft? {
        guard let target = controls.target else { return nil }
        return aircraft.first { $0.callsign == target }
    }

    /// The nearest aircraft whose symbol or label a point lands on.
    private func aircraftAt(_ tap: CGPoint, size: CGSize) -> String? {
        var best: (callsign: String, distance: CGFloat)?
        for ac in aircraft {
            let p = screenPoint(of: ac, size: size)
            let dx = tap.x - p.x
            let dy = tap.y - p.y
            let distance = (dx * dx + dy * dy).squareRoot()
            let onLabel = tagFrame(ac, size: size).contains(tap)
            if distance <= 14 || onLabel {
                if best == nil || distance < best!.distance { best = (ac.callsign, distance) }
            }
        }
        return best?.callsign
    }

    /// Left click. What it does depends on the mouse-control mode.
    private func handleTap(at tap: CGPoint, size: CGSize) {
        if placing, let onPlace {
            let t = viewTransform(size: size)
            onPlace(Double((tap.x - t.cx) / t.scale), Double((t.cy - tap.y) / t.scale))
            return
        }
        switch controls.mode {
        case .heading:
            commitHeading(at: tap, size: size)
        case .direct:
            pickFix(at: tap, size: size)
        case .crossFix:
            guard let ac = targetAircraft,
                  let fix = nearestFix(to: tap, size: size, among: Set(controls.crossingCandidates(for: ac))) else { return }
            controls.pickCrossFix(fix)
        case .altitude, .speed, .approach, .crossAltitude, .colour, .macro:
            controls.backToRing()
        case .idle, .ring:
            onSelect(aircraftAt(tap, size: size))
            controls.closeRing()
        }
    }

    /// Right click on an aircraft opens its ring; elsewhere it steps back or closes the ring.
    private func rightClick(at point: CGPoint, size: CGSize) {
        if let callsign = aircraftAt(point, size: size) {
            onSelect(callsign)
            controls.open(for: callsign)
        } else {
            _ = controls.escape()
        }
    }

    private static func normalizedHeading(_ degrees: Double) -> Double {
        let r = degrees.truncatingRemainder(dividingBy: 360)
        return r < 0 ? r + 360 : r
    }

    /// True heading from the aircraft's screen position to a point (screen y grows downward).
    private func heading(from origin: CGPoint, to point: CGPoint) -> Double {
        Self.normalizedHeading(atan2(Double(point.x - origin.x), Double(-(point.y - origin.y))) * 180 / .pi)
    }

    /// Pointer headings are assigned in 5 degree steps (360 rather than 0).
    static func snapped(_ degrees: Double) -> Int {
        let step = Int((degrees / 5).rounded()) * 5 % 360
        return step == 0 ? 360 : step
    }

    private func commitHeading(at point: CGPoint, size: CGSize) {
        guard let ac = targetAircraft else { return }
        let origin = screenPoint(of: ac, size: size)
        guard hypot(point.x - origin.x, point.y - origin.y) > 12 else { return }
        let degrees = Self.snapped(heading(from: origin, to: point))
        controls.add(.heading(degrees: degrees, turn: forcedTurn(for: ac, to: degrees)), aircraft: ac)
    }

    /// Pointing sends the shorter way (turn nil). With Option held it is the other way round.
    private func forcedTurn(for ac: Aircraft, to degrees: Int) -> TurnDirection? {
        guard NSEvent.modifierFlags.contains(.option) else { return nil }
        var delta = (Double(degrees) - ac.headingDeg).truncatingRemainder(dividingBy: 360)
        if delta > 180 { delta -= 360 } else if delta <= -180 { delta += 360 }
        return delta > 0 ? .left : .right // opposite of the shorter way
    }

    private func pickFix(at tap: CGPoint, size: CGSize) {
        guard let ac = targetAircraft, let fix = nearestFix(to: tap, size: size) else { return }
        controls.pickRouteFix(fix, aircraft: ac)
    }

    private func nearestFix(to point: CGPoint, size: CGSize, among allowed: Set<String>? = nil) -> String? {
        var best: (id: String, distance: CGFloat)?
        for fix in airport.fixes where allowed?.contains(fix.id) ?? true {
            let p = screen(lat: fix.lat, lon: fix.lon, size: size)
            let distance = hypot(point.x - p.x, point.y - p.y)
            if distance <= 14, best == nil || distance < best!.distance { best = (fix.id, distance) }
        }
        return best?.id
    }

    // MARK: Track tags

    private func tagLines(_ ac: Aircraft) -> [String] {
        // An aircraft handed to the tower is no longer the controller's: just its callsign.
        if ac.handedToTower { return [ac.callsign] }
        var lines = [ac.labelTop, ac.labelBottom]
        if ac.onRunwayHeading { lines.append("RWY HDG") }
        if let emergency = ac.emergency { lines.insert(emergency.urgencyWord, at: 1) }
        if let text = commandTags[ac.callsign] { lines.append(text) }
        if let text = macroTags[ac.callsign] { lines.append(text) }
        return lines
    }

    private func tagFrame(_ ac: Aircraft, size: CGSize) -> CGRect {
        let p = screenPoint(of: ac, size: size)
        let o = tags.offset(for: ac.callsign)
        let s = TagPlacement.size(lines: tagLines(ac), charWidth: 6.7 * UIScale.factor, lineHeight: 13 * UIScale.factor)
        return CGRect(x: p.x + o.x, y: p.y + o.y, width: s.width, height: s.height)
    }

    /// The tag under a point, topmost (last drawn) first.
    private func tagAt(_ point: CGPoint, size: CGSize) -> String? {
        for ac in aircraft.reversed() where tagFrame(ac, size: size).insetBy(dx: -2, dy: -2).contains(point) {
            return ac.callsign
        }
        return nil
    }

    private func tagItems(size: CGSize) -> [TagItem] {
        aircraft.map {
            TagItem(callsign: $0.callsign, symbol: screenPoint(of: $0, size: size), size: TagPlacement.size(lines: tagLines($0), charWidth: 6.7 * UIScale.factor, lineHeight: 13 * UIScale.factor))
        }
    }

    /// Moves tags apart. Automatic mode only touches tags that were not dragged by hand and keeps clear ones in place;
    /// a forced pass (the Declutter button) rearranges every tag.
    private func relayout(size: CGSize, force: Bool) {
        let items = tagItems(size: size)
        tags.prune(present: Set(items.map(\.callsign)))
        if force {
            tags.releaseAll()
            tags.apply(TagPlacement.place(items: items, offsets: tags.offsets, fixed: [], keepIfClear: false))
        } else if autoDeclutter {
            tags.apply(TagPlacement.place(items: items, offsets: tags.offsets, fixed: tags.manual, keepIfClear: true))
        }
    }

    // MARK: Mouse-control overlays

    /// Every open runway can be approached: by ILS where it has one, visually otherwise.
    private var openIlsRunways: [Runway] {
        let open = Set(runwayStatuses.filter(\.isOpen).map(\.id))
        return airport.runways.filter { open.contains($0.id) }
    }

    private var availableApproaches: [Procedure] {
        airport.procedures.filter { $0.kind == .approach && availableProcedures.contains($0.id) }
    }

    /// The ring for an aircraft: separate sets for aircraft on the ground, departures in the air and arrivals.
    private func ringItems(for ac: Aircraft) -> [RingItem] {
        if ac.isOnGround {
            return [RingItem(id: "lu", label: "LUP", action: .command(.lineUp), enabled: ac.groundPhase == .holdingShort),
                    RingItem(id: "to", label: "T/O", action: .command(.takeoff),
                             enabled: ac.groundPhase == .holdingShort || ac.groundPhase == .linedUp),
                    RingItem(id: "mac", label: "MAC", action: .mode(.macro),
                             enabled: !(macroChoices?(ac) ?? []).isEmpty || macroTags[ac.callsign] != nil, secondary: true),
                    RingItem(id: "col", label: "COL", action: .mode(.colour), enabled: true, secondary: true)]
        }
        var items = [RingItem(id: "hdg", label: "HDG", action: .mode(.heading), enabled: true),
                     RingItem(id: "alt", label: "ALT", action: .mode(.altitude), enabled: true),
                     RingItem(id: "spd", label: "SPD", action: .mode(.speed), enabled: true),
                     RingItem(id: "dct", label: "DCT", action: .mode(.direct), enabled: true)]
        let isArrival = ac.departure == nil
        if isArrival {
            items.append(RingItem(id: "app", label: "APP", action: .mode(.approach), enabled: !openIlsRunways.isEmpty))
        }
        items.append(RingItem(id: "xng", label: "XNG", action: .mode(.crossFix), enabled: true, secondary: true))
        items.append(RingItem(id: "mnt", label: "MAINT", action: .command(.maintain), enabled: !ac.handedToTower, secondary: true))
        items.append(RingItem(id: "mac", label: "MAC", action: .mode(.macro),
                              enabled: !ac.handedToTower && (!(macroChoices?(ac) ?? []).isEmpty || macroTags[ac.callsign] != nil),
                              secondary: true))
        let handoffReady = isArrival ? (ac.approach.map { $0.phase != .intercepting } ?? false) : true
        items.append(RingItem(id: "ho", label: "HO", action: .command(.handoff), enabled: handoffReady && !ac.handedToTower))
        items.append(RingItem(id: "col", label: "COL", action: .mode(.colour), enabled: true, secondary: true))
        return items
    }

    @ViewBuilder
    private func controlOverlays(size: CGSize) -> some View {
        ZStack(alignment: .topLeading) {
            if let ac = targetAircraft {
                let p = screenPoint(of: ac, size: size)
                if controls.mode == .ring {
                    RadialRingView(center: p, items: ringItems(for: ac)) { picked in
                        switch picked {
                        case .command(let command):
                            controls.add(command, aircraft: ac)
                        case .mode(let mode):
                            if mode == .crossFix && controls.crossingCandidates(for: ac).isEmpty {
                                controls.tell("\(ac.callsign) has no route to cross a fix on. Give a direct or a route first.")
                                NSSound.beep()
                            } else {
                                controls.choose(mode)
                            }
                        }
                    }
                }
                if controls.mode == .colour {
                    HStack(spacing: 8) {
                        Button { onMark?(nil, ac.callsign); controls.backToRing() } label: {
                            Image(systemName: "nosign").font(.system(size: 15)).foregroundStyle(theme.dimText)
                        }
                        .buttonStyle(.plain)
                        .help("No colour")
                        ForEach(Array(AircraftMarkers.palette.enumerated()), id: \.offset) { index, marker in
                            Button { onMark?(index, ac.callsign); controls.backToRing() } label: {
                                Circle()
                                    .fill(Color(hex: marker.rgb))
                                    .frame(width: 20, height: 20)
                                    .overlay(Circle().stroke(theme.text, lineWidth: markerColours[ac.callsign] == index ? 2.5 : 0))
                            }
                            .buttonStyle(.plain)
                            .help(marker.name)
                        }
                    }
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 6).fill(theme.panel))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(theme.panelBorder, lineWidth: 1))
                    .offset(x: min(max(8, p.x - 90), size.width - 220), y: min(p.y + 62, size.height - 50))
                }
                if controls.mode == .macro {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("MACRO").font(.ui(size: 11, design: .monospaced)).foregroundStyle(theme.heading)
                        if let running = macroTags[ac.callsign] {
                            Button { onMacro?(nil, ac.callsign); controls.mode = .idle } label: {
                                Text("STOP  \(running)").font(.ui(size: 12, design: .monospaced)).foregroundStyle(theme.alert)
                            }
                            .buttonStyle(.plain)
                        }
                        ForEach(macroChoices?(ac) ?? [], id: \.self) { name in
                            Button { onMacro?(name, ac.callsign); controls.mode = .idle } label: {
                                Text(name).font(.ui(size: 12, design: .monospaced)).foregroundStyle(theme.text)
                                    .frame(minWidth: 90, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 6).fill(theme.panel))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(theme.panelBorder, lineWidth: 1))
                    .offset(x: min(p.x + 70, size.width - 160), y: max(8, min(p.y - 60, size.height - 200)))
                }
                if controls.mode == .altitude {
                    ValueColumnView(title: "ALT", items: altitudeItems(for: ac), onPick: { feet in
                        let command: Command = Double(feet) < ac.altitudeFt ? .descend(feet: feet) : .climb(feet: feet)
                        controls.hoverAltitude = nil
                        controls.add(command, aircraft: ac)
                    }, onHover: { controls.hoverAltitude = $0 })
                    .onDisappear { controls.hoverAltitude = nil }
                    .offset(x: min(p.x + 70, size.width - 120), y: max(8, min(p.y - 120, size.height - 260)))
                }
                if controls.mode == .crossAltitude, let fix = controls.crossFix {
                    ValueColumnView(title: "\(fix) AT", items: crossLevelItems(for: ac)) { feet in
                        controls.add(.cross(fix: fix, altitudeFt: feet), aircraft: ac)
                    }
                    .offset(x: min(p.x + 70, size.width - 120), y: max(8, min(p.y - 120, size.height - 260)))
                }
                if controls.mode == .speed {
                    ValueColumnView(title: "SPD", items: speedItems(for: ac)) { knots in
                        controls.add(.speed(knots: knots), aircraft: ac)
                    }
                    .offset(x: min(p.x + 70, size.width - 120), y: max(8, min(p.y - 120, size.height - 260)))
                }
                if controls.mode == .approach {
                    approachButtons(for: ac, size: size)
                }
                if controls.mode == .direct && !controls.pendingRoute.isEmpty {
                    HStack(spacing: 6) {
                        Text(controls.pendingRoute.joined(separator: " › ")).font(.ui(size: 11, design: .monospaced))
                        Button("Undo") { controls.undoRouteFix() }
                        Button("Done") { controls.commitRoute(aircraft: ac) }.tint(.orange)
                    }
                    .padding(6)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
                    .offset(x: min(p.x + 70, size.width - 320), y: max(8, min(p.y + 40, size.height - 60)))
                }
                if controls.canExpedite {
                    Toggle("Expedite", isOn: $controls.expedite)
                        .toggleStyle(.button)
                        .tint(.orange)
                        .offset(x: min(p.x + 70, size.width - 100), y: max(8, min(p.y - 150, size.height - 290)))
                }
                let columnOpen = controls.mode == .altitude || controls.mode == .speed || controls.mode == .crossAltitude
                if !controls.chain.isEmpty {
                    ChipStripView(callsign: ac.callsign, commands: controls.chain.commands,
                                  onRemove: { controls.removeChip(at: $0) },
                                  onSend: onSend,
                                  onCancel: { controls.cancelAll() })
                        // Right of the track label (about 85 px wide) and clear of the ring, so neither is covered.
                        .offset(x: columnOpen ? max(8, p.x - 215) : min(p.x + 95, size.width - 200),
                                y: max(8, min(p.y - 12, size.height - 170)))
                }
            }
            if let banner = controls.banner {
                ModeBannerView(text: banner)
                    .frame(maxWidth: .infinity)
                    .offset(y: 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func crossLevelItems(for ac: Aircraft) -> [ValueColumnView.Item] {
        let current = Int(ac.altitudeFt.rounded())
        return stride(from: 2000, through: 41000, by: 1000).map { feet in
            let label = feet > airport.transitionAltitudeFt ? "FL\(Phraseology.pad3(feet / 100))" : "\(feet) ft"
            return ValueColumnView.Item(id: feet, label: label, isCurrent: abs(feet - current) < 500, enabled: true)
        }
    }

    private func altitudeItems(for ac: Aircraft) -> [ValueColumnView.Item] {
        let current = Int(ac.altitudeFt.rounded())
        let planned = ac.departure?.expectedLevelFt
        return stride(from: 2000, through: 41000, by: 1000).map { feet in
            let command: Command = Double(feet) < ac.altitudeFt ? .descend(feet: feet) : .climb(feet: feet)
            let label = feet > airport.transitionAltitudeFt ? "FL\(Phraseology.pad3(feet / 100))" : "\(feet) ft"
            return ValueColumnView.Item(id: feet, label: label,
                                        isCurrent: abs(feet - current) < 500,
                                        enabled: command.refusal(for: ac) == nil,
                                        isPlanned: planned.map { abs($0 - feet) < 500 } ?? false)
        }
    }

    private func speedItems(for ac: Aircraft) -> [ValueColumnView.Item] {
        let current = Int(ac.targetSpeedKt.rounded())
        return stride(from: 120, through: 350, by: 10).map { knots in
            ValueColumnView.Item(id: knots, label: "\(knots) kt", isCurrent: abs(knots - current) < 5,
                                 enabled: Command.speed(knots: knots).refusal(for: ac) == nil)
        }
    }

    /// Buttons on the scope: one per open runway on its extended centreline, and one per approach on its first leg.
    @ViewBuilder
    private func approachButtons(for ac: Aircraft, size: CGSize) -> some View {
        ForEach(openIlsRunways, id: \.id) { runway in
            let t = airport.referenceProjection.nm(lat: runway.thresholdLat, lon: runway.thresholdLon)
            let out = LocalProjection.offset(bearingDeg: runway.trueBearingDeg + 180, distanceNM: 8)
            let spot = screen(east: t.east + out.east, north: t.north + out.north, size: size)
            sceneButton("\(runway.ils == nil ? "VIS" : "ILS") \(runway.id)", at: spot) {
                controls.add(runway.ils == nil ? .visualApproach(runway: runway.id) : .approach(runway: runway.id), aircraft: ac)
            }
        }
        ForEach(availableApproaches, id: \.id) { proc in
            if let first = proc.legs.first, let runway = proc.runways.first,
               let a = airport.fixes.first(where: { $0.id == first.fixId }) {
                let pa = screen(lat: a.lat, lon: a.lon, size: size)
                let second = proc.legs.dropFirst().first.flatMap { leg in airport.fixes.first { $0.id == leg.fixId } }
                let pb = second.map { screen(lat: $0.lat, lon: $0.lon, size: size) } ?? pa
                sceneButton(proc.id, at: CGPoint(x: (pa.x + pb.x) / 2, y: (pa.y + pb.y) / 2)) {
                    controls.add(.joinApproach(procedure: proc.id, runway: runway, via: first.fixId), aircraft: ac)
                }
            }
        }
    }

    private func sceneButton(_ title: String, at point: CGPoint, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.ui(size: 10, weight: .bold, design: .monospaced))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 3).fill(theme.panel))
                .overlay(RoundedRectangle(cornerRadius: 3).stroke(theme.approach, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .foregroundStyle(theme.text)
        .fixedSize()
        .position(point)
    }

    // MARK: Drawing

    /// Heading compass fixed to the window like a bezel, so it stays put while the picture pans.
    /// Marks every 5 degrees, longer every 10, labelled every 10 (360, 010, 020, ...). Headings are true, not magnetic.
    private func drawCompass(_ ctx: GraphicsContext, size: CGSize) {
        let centre = CGPoint(x: size.width / 2, y: size.height / 2)
        let radius = max(min(size.width, size.height) / 2 - 30, 40)

        ctx.stroke(Path(ellipseIn: CGRect(x: centre.x - radius, y: centre.y - radius,
                                          width: radius * 2, height: radius * 2)),
                   with: .color(theme.compass), lineWidth: 1)

        for deg in stride(from: 0, to: 360, by: 5) {
            let isLabelled = deg % 10 == 0
            let length: CGFloat = deg % 30 == 0 ? 14 : (isLabelled ? 9 : 5)
            let angle = Double(deg) * .pi / 180
            let dx = CGFloat(sin(angle))
            let dy = -CGFloat(cos(angle)) // screen y grows downward; north is up

            var tick = Path()
            tick.move(to: CGPoint(x: centre.x + dx * radius, y: centre.y + dy * radius))
            tick.addLine(to: CGPoint(x: centre.x + dx * (radius - length), y: centre.y + dy * (radius - length)))
            ctx.stroke(tick, with: .color(theme.compass), lineWidth: deg % 30 == 0 ? 1.5 : 1)

            if isLabelled {
                let label = Phraseology.pad3(deg == 0 ? 360 : deg)
                ctx.draw(Text(label).font(.ui(size: 11, design: .monospaced)).foregroundColor(deg % 30 == 0 ? theme.compassLabel : theme.compass),
                         at: CGPoint(x: centre.x + dx * (radius + 16), y: centre.y + dy * (radius + 16)),
                         anchor: .center)
            }
        }
    }

    // MARK: Mouse-control drawing

    private func ray(from origin: CGPoint, headingDeg: Double, length: CGFloat) -> CGPoint {
        let rad = headingDeg * .pi / 180
        return CGPoint(x: origin.x + CGFloat(sin(rad)) * length, y: origin.y - CGFloat(cos(rad)) * length)
    }

    /// Previews of the collected chips and the visuals of the active mode.
    private func drawControls(_ ctx: GraphicsContext, size: CGSize) {
        guard let ac = targetAircraft else { return }
        let origin = screenPoint(of: ac, size: size)
        let dashed = StrokeStyle(lineWidth: 1.5, dash: [4, 4])

        for command in controls.chain.commands {
            switch command {
            case .heading(let degrees, _):
                var line = Path()
                line.move(to: origin)
                line.addLine(to: ray(from: origin, headingDeg: Double(degrees), length: 90))
                ctx.stroke(line, with: .color(theme.selected), style: dashed)
            case .direct(let fix):
                if let f = airport.fixes.first(where: { $0.id == fix }) {
                    var line = Path()
                    line.move(to: origin)
                    line.addLine(to: screen(lat: f.lat, lon: f.lon, size: size))
                    ctx.stroke(line, with: .color(theme.selected), style: dashed)
                }
            case .route(let fixes):
                var line = Path()
                line.move(to: origin)
                for id in fixes {
                    if let f = airport.fixes.first(where: { $0.id == id }) {
                        line.addLine(to: screen(lat: f.lat, lon: f.lon, size: size))
                    }
                }
                ctx.stroke(line, with: .color(theme.selected), style: dashed)
            case .cross(let id, _):
                if let f = airport.fixes.first(where: { $0.id == id }) {
                    let p = screen(lat: f.lat, lon: f.lon, size: size)
                    ctx.stroke(Path(ellipseIn: CGRect(x: p.x - 8, y: p.y - 8, width: 16, height: 16)),
                               with: .color(theme.selected), lineWidth: 1.5)
                }
            default:
                break
            }
        }

        switch controls.mode {
        case .heading:
            let radius: CGFloat = 80
            ctx.stroke(Path(ellipseIn: CGRect(x: origin.x - radius, y: origin.y - radius, width: radius * 2, height: radius * 2)),
                       with: .color(theme.selected.opacity(0.6)), lineWidth: 1)
            for deg in stride(from: 0, to: 360, by: 10) {
                let long = deg % 30 == 0
                var tick = Path()
                tick.move(to: ray(from: origin, headingDeg: Double(deg), length: radius))
                tick.addLine(to: ray(from: origin, headingDeg: Double(deg), length: radius - (long ? 10 : 5)))
                ctx.stroke(tick, with: .color(theme.selected.opacity(0.7)), lineWidth: 1)
                if long {
                    ctx.draw(Text(Phraseology.pad3(deg == 0 ? 360 : deg)).font(.ui(size: 9, design: .monospaced))
                                .foregroundColor(theme.selected),
                             at: ray(from: origin, headingDeg: Double(deg), length: radius + 12), anchor: .center)
                }
            }
            if let hover = controls.hover, hypot(hover.x - origin.x, hover.y - origin.y) > 12 {
                let h = Double(Self.snapped(heading(from: origin, to: hover)))
                var line = Path()
                line.move(to: origin)
                line.addLine(to: ray(from: origin, headingDeg: h, length: radius))
                ctx.stroke(line, with: .color(theme.selected), lineWidth: 2)
                let rounded = Int(h.rounded()) % 360
                let degrees = rounded == 0 ? 360 : rounded
                let turn = forcedTurn(for: ac, to: degrees)
                var text = "HDG \(Phraseology.pad3(degrees))"
                if let turn { text += turn == .left ? "  turn left" : "  turn right" }
                ctx.draw(Text(text).font(.ui(size: 12, weight: .bold, design: .monospaced)).foregroundColor(theme.selected),
                         at: CGPoint(x: hover.x + 14, y: hover.y - 14), anchor: .bottomLeading)
            }
        case .direct:
            let hovered = controls.hover.flatMap { nearestFix(to: $0, size: size) }
            for fix in airport.fixes {
                let p = screen(lat: fix.lat, lon: fix.lon, size: size)
                let isHovered = fix.id == hovered
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - 3, y: p.y - 3, width: 6, height: 6)),
                         with: .color(isHovered ? theme.selected : theme.heading))
                ctx.draw(Text(fix.id).font(.ui(size: isHovered ? 11 : 9, weight: isHovered ? .bold : .regular, design: .monospaced))
                            .foregroundColor(isHovered ? theme.selected : theme.heading),
                         at: CGPoint(x: p.x + 6, y: p.y - 5), anchor: .bottomLeading)
            }
            var last = origin
            if !controls.pendingRoute.isEmpty {
                var route = Path()
                route.move(to: origin)
                for (n, id) in controls.pendingRoute.enumerated() {
                    guard let f = airport.fixes.first(where: { $0.id == id }) else { continue }
                    let p = screen(lat: f.lat, lon: f.lon, size: size)
                    route.addLine(to: p)
                    last = p
                    ctx.draw(Text("\(n + 1)").font(.ui(size: 10, weight: .bold, design: .monospaced))
                                .foregroundColor(theme.selected),
                             at: CGPoint(x: p.x - 7, y: p.y + 8), anchor: .center)
                }
                ctx.stroke(route, with: .color(theme.selected), lineWidth: 2)
            }
            if let hovered, let f = airport.fixes.first(where: { $0.id == hovered }) {
                var line = Path()
                line.move(to: last)
                line.addLine(to: screen(lat: f.lat, lon: f.lon, size: size))
                ctx.stroke(line, with: .color(theme.selected), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
            }
        case .crossFix, .crossAltitude:
            let candidates = Set(controls.crossingCandidates(for: ac))
            let hovered = controls.mode == .crossFix
                ? controls.hover.flatMap { nearestFix(to: $0, size: size, among: candidates) } : controls.crossFix
            for fix in airport.fixes where candidates.contains(fix.id) {
                let p = screen(lat: fix.lat, lon: fix.lon, size: size)
                let on = fix.id == hovered
                ctx.stroke(Path(ellipseIn: CGRect(x: p.x - 7, y: p.y - 7, width: 14, height: 14)),
                           with: .color(on ? theme.selected : theme.heading), lineWidth: on ? 2 : 1)
                ctx.draw(Text(fix.id).font(.ui(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(on ? theme.selected : theme.heading),
                         at: CGPoint(x: p.x + 10, y: p.y - 6), anchor: .bottomLeading)
            }
        case .approach:
            for runway in openIlsRunways {
                let t = airport.referenceProjection.nm(lat: runway.thresholdLat, lon: runway.thresholdLon)
                let out = LocalProjection.offset(bearingDeg: runway.trueBearingDeg + 180, distanceNM: 15)
                var line = Path()
                line.move(to: screen(east: t.east, north: t.north, size: size))
                line.addLine(to: screen(east: t.east + out.east, north: t.north + out.north, size: size))
                ctx.stroke(line, with: .color(theme.runway), style: StrokeStyle(lineWidth: 2, dash: [8, 5]))
            }
            for proc in availableApproaches {
                var path = Path()
                var started = false
                for leg in proc.legs {
                    guard let f = airport.fixes.first(where: { $0.id == leg.fixId }) else { continue }
                    let p = screen(lat: f.lat, lon: f.lon, size: size)
                    if started { path.addLine(to: p) } else { path.move(to: p); started = true }
                }
                ctx.stroke(path, with: .color(theme.approach), lineWidth: 2.5)
            }
        default:
            break
        }
    }

    private func markerColor(_ index: Int) -> Color {
        let palette = AircraftMarkers.palette
        return Color(hex: palette[min(max(index, 0), palette.count - 1)].rgb)
    }

    /// A short arc across the flight path at the point where a level is reached, with the level beside it.
    private func drawLevelMark(_ ctx: GraphicsContext, at q: CGPoint, bearingDeg: Double, colour: Color,
                               label: String?, dashed: Bool = false) {
        let b = bearingDeg * .pi / 180
        let forward = CGPoint(x: sin(b), y: -cos(b)) // screen direction of travel
        let side = CGPoint(x: -forward.y, y: forward.x)
        var arc = Path()
        for k in 0...8 {
            let t = (Double(k) / 8 - 0.5) * 2 // -1 ... 1
            let across = CGFloat(t) * 7
            let bow = CGFloat(t * t) * -3 // the ends trail behind the middle, like a bow facing forward
            let pt = CGPoint(x: q.x + side.x * across + forward.x * bow, y: q.y + side.y * across + forward.y * bow)
            if k == 0 { arc.move(to: pt) } else { arc.addLine(to: pt) }
        }
        ctx.stroke(arc, with: .color(theme.background), style: StrokeStyle(lineWidth: 4, lineCap: .round))
        ctx.stroke(arc, with: .color(colour), style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: dashed ? [3, 2] : []))
        if let label {
            ctx.draw(Text(label).font(.ui(size: 10, weight: .bold, design: .monospaced)).foregroundColor(colour),
                     at: CGPoint(x: q.x + side.x * 10 + forward.x * 2, y: q.y + side.y * 10 + forward.y * 2),
                     anchor: .leading)
        }
    }

    /// Emergency aircraft: ring, tag border and tag line.
    private static let emergencyRed = Color(red: 1.0, green: 0.27, blue: 0.24)

    private func draw(_ ctx: GraphicsContext, size: CGSize) {
        guard !airport.runways.isEmpty else { return }

        if showCompass { drawCompass(ctx, size: size) }

        let view = viewTransform(size: size)
        let cx = view.cx
        let cy = view.cy
        let scale = view.scale
        let proj = airport.referenceProjection

        func point(east: Double, north: Double) -> CGPoint {
            CGPoint(x: cx + CGFloat(east) * scale, y: cy - CGFloat(north) * scale)
        }

        // Procedure lines and fixes. Every fix of the airport is drawn when Fixes is on, so there are always
        // fixes to give "direct" to; names show for fixes on a visible procedure, or for all of them when zoomed in.
        var fixPoints: [String: CGPoint] = [:]
        for fix in airport.fixes {
            let q = proj.nm(lat: fix.lat, lon: fix.lon)
            fixPoints[fix.id] = point(east: q.east, north: q.north)
        }
        var shownFixes = Set<String>()
        for proc in airport.procedures where !hiddenProcedures.contains(proc.id) && availableProcedures.contains(proc.id) {
            let color: Color
            switch proc.kind {
            case .star:
                guard showStars else { continue }
                color = theme.star.opacity(0.9)
            case .sid:
                guard showSids else { continue }
                color = theme.sid.opacity(0.9)
            case .approach:
                guard showApproaches else { continue }
                color = theme.approach.opacity(0.9)
            }
            var path = Path()
            var started = false
            for leg in proc.legs {
                guard let p = fixPoints[leg.fixId] else { continue }
                if started { path.addLine(to: p) } else { path.move(to: p); started = true }
                shownFixes.insert(leg.fixId)
            }
            ctx.stroke(path, with: .color(color), lineWidth: 1.5)
        }
        if showFixes {
            for fix in airport.fixes {
                let id = fix.id
                guard let p = fixPoints[id] else { continue }
                let onProcedure = shownFixes.contains(id)
                let fixColor = onProcedure ? theme.fix : theme.fix.opacity(0.65)
                var tri = Path()
                tri.move(to: CGPoint(x: p.x, y: p.y - 4))
                tri.addLine(to: CGPoint(x: p.x + 3.5, y: p.y + 3))
                tri.addLine(to: CGPoint(x: p.x - 3.5, y: p.y + 3))
                tri.closeSubpath()
                ctx.stroke(tri, with: .color(fixColor), lineWidth: 1)
                if onProcedure || scale >= 8 {
                    ctx.draw(Text(id).font(.ui(size: 9, design: .monospaced)).foregroundColor(fixColor),
                             at: CGPoint(x: p.x + 6, y: p.y - 5), anchor: .bottomLeading)
                }
            }
        }

        // Range rings every 5 NM.
        for nm in stride(from: 5, through: max(40, Int(areaRadiusNM)), by: 5) {
            let r = CGFloat(nm) * scale
            let rect = CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)
            ctx.stroke(Path(ellipseIn: rect), with: .color(theme.rings), lineWidth: 1)
            ctx.draw(Text("\(nm)").font(.ui(size: 10)).foregroundColor(theme.dimText),
                     at: CGPoint(x: cx + r + 10, y: cy))
        }

        // Edge of the approach area.
        do {
            let r = CGFloat(areaRadiusNM) * scale
            let rect = CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)
            ctx.stroke(Path(ellipseIn: rect), with: .color(theme.heading.opacity(0.45)),
                       style: StrokeStyle(lineWidth: 1.2, dash: [6, 5]))
            ctx.draw(Text("APP \(Int(areaRadiusNM)) NM").font(.ui(size: 9, design: .monospaced)).foregroundColor(theme.heading.opacity(0.7)),
                     at: CGPoint(x: cx, y: cy - r - 8))
        }

        // Runways in use are drawn bright with their extended centreline; closed runways are dimmed, thin, crossed
        // out, and have no centreline.
        let openRunwayIds = Set(runwayStatuses.filter(\.isOpen).map(\.id))
        let runwaysToDraw = airport.runways.sorted { openRunwayIds.contains($0.id) != openRunwayIds.contains($1.id)
                                                      ? !openRunwayIds.contains($0.id) : $0.id < $1.id }
        for rwy in runwaysToDraw {
            let isOpen = runwayStatuses.isEmpty || openRunwayIds.contains(rwy.id)
            let t = proj.nm(lat: rwy.thresholdLat, lon: rwy.thresholdLon)
            // Pavement starts before the landing threshold when the threshold is displaced.
            let displacementNM = Double(rwy.lengthM - rwy.ldaM) / 1852
            let lengthNM = Double(rwy.lengthM) / 1852

            let back = LocalProjection.offset(bearingDeg: rwy.trueBearingDeg + 180, distanceNM: displacementNM)
            let along = LocalProjection.offset(bearingDeg: rwy.trueBearingDeg, distanceNM: lengthNM)
            let start = (east: t.east + back.east, north: t.north + back.north)
            let end = (east: start.east + along.east, north: start.north + along.north)

            var pavement = Path()
            pavement.move(to: point(east: start.east, north: start.north))
            pavement.addLine(to: point(east: end.east, north: end.north))
            ctx.stroke(pavement, with: .color(isOpen ? theme.runway : theme.dimText.opacity(0.55)),
                       lineWidth: isOpen ? 4 : 2)

            if isOpen {
                // Extended centreline (dashed) on the approach side, 10 NM out.
                let out = LocalProjection.offset(bearingDeg: rwy.trueBearingDeg + 180, distanceNM: 10)
                var centreline = Path()
                centreline.move(to: point(east: t.east, north: t.north))
                centreline.addLine(to: point(east: t.east + out.east, north: t.north + out.north))
                ctx.stroke(centreline, with: .color(theme.runwayCentreline),
                           style: StrokeStyle(lineWidth: 1, dash: [6, 6]))
            } else {
                // A cross over the middle of the pavement.
                let mid = point(east: (start.east + end.east) / 2, north: (start.north + end.north) / 2)
                var cross = Path()
                cross.move(to: CGPoint(x: mid.x - 5, y: mid.y - 5)); cross.addLine(to: CGPoint(x: mid.x + 5, y: mid.y + 5))
                cross.move(to: CGPoint(x: mid.x - 5, y: mid.y + 5)); cross.addLine(to: CGPoint(x: mid.x + 5, y: mid.y - 5))
                ctx.stroke(cross, with: .color(theme.warning), lineWidth: 2)
            }

            // Threshold marker and label.
            let tp = point(east: t.east, north: t.north)
            ctx.fill(Path(ellipseIn: CGRect(x: tp.x - 3, y: tp.y - 3, width: 6, height: 6)),
                     with: .color(isOpen ? theme.runway : theme.dimText.opacity(0.55)))
            ctx.draw(Text(rwy.id)
                        .font(.ui(size: 10, weight: isOpen ? .bold : .regular, design: .monospaced))
                        .foregroundColor(isOpen ? theme.runway : theme.dimText.opacity(0.7)),
                     at: CGPoint(x: tp.x + 22, y: tp.y - 10))
        }

        // Conflict lines between the pair: red when separation is lost, amber when predicted.
        var worst: [String: Conflict.Kind] = [:]
        for c in conflicts {
            guard let a = aircraft.first(where: { $0.callsign == c.first }),
                  let b = aircraft.first(where: { $0.callsign == c.second }) else { continue }
            let color: Color = c.kind == .loss ? theme.alert : theme.warning
            var line = Path()
            line.move(to: point(east: a.eastNM, north: a.northNM))
            line.addLine(to: point(east: b.eastNM, north: b.northNM))
            ctx.stroke(line, with: .color(color.opacity(0.9)),
                       style: StrokeStyle(lineWidth: 1.5, dash: c.kind == .loss ? [] : [5, 4]))
            for id in [c.first, c.second] {
                if worst[id] == nil || c.kind == .loss { worst[id] = c.kind }
            }
        }

        drawControls(ctx, size: size)

        // Assigned procedures switched on for single aircraft: drawn thick in the aircraft's colour, or in the STAR or
        // SID colour when it has none, with the fix names.
        for ac in aircraft where shownProcedures.contains(ac.callsign) {
            guard let id = ac.procedureId, let proc = airport.procedures.first(where: { $0.id == id }) else { continue }
            let colour = markerColours[ac.callsign].map(markerColor) ?? (proc.kind == .sid ? theme.sid : theme.star)
            var path = Path()
            var started = false
            var labelled: [(String, CGPoint)] = []
            for leg in proc.legs {
                guard let f = airport.fixes.first(where: { $0.id == leg.fixId }) else { continue }
                let q = screen(lat: f.lat, lon: f.lon, size: size)
                if started { path.addLine(to: q) } else { path.move(to: q); started = true }
                labelled.append((f.id, q))
            }
            ctx.stroke(path, with: .color(theme.background), style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
            ctx.stroke(path, with: .color(colour), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
            for (name, q) in labelled {
                ctx.fill(Path(ellipseIn: CGRect(x: q.x - 2.5, y: q.y - 2.5, width: 5, height: 5)), with: .color(colour))
                ctx.draw(Text(name).font(.ui(size: 10, weight: .bold, design: .monospaced)).foregroundColor(colour),
                         at: CGPoint(x: q.x + 6, y: q.y - 4), anchor: .bottomLeading)
            }
        }

        for ac in aircraft {
            let handedOff = ac.handedToTower
            let marker = handedOff ? nil : markerColours[ac.callsign].map(markerColor)
            var trackColor = ac.callsign == selected ? theme.selected : theme.aircraft // text stays readable; the marker colour is on the symbol, bar and box
            if handedOff { trackColor = theme.dimText.opacity(0.75) }
            if let kind = worst[ac.callsign] { trackColor = kind == .loss ? theme.alert : theme.warning }
            let p = point(east: ac.eastNM, north: ac.northNM)
            if worst[ac.callsign] != nil {
                ctx.stroke(Path(ellipseIn: CGRect(x: p.x - 9, y: p.y - 9, width: 18, height: 18)),
                           with: .color(trackColor), lineWidth: 1)
            }
            // An aircraft with an emergency: a red double ring, until it is handed to the tower.
            let emergency = handedOff ? nil : ac.emergency
            if emergency != nil {
                ctx.stroke(Path(ellipseIn: CGRect(x: p.x - 12, y: p.y - 12, width: 24, height: 24)),
                           with: .color(Self.emergencyRed), lineWidth: 2)
                ctx.stroke(Path(ellipseIn: CGRect(x: p.x - 17, y: p.y - 17, width: 34, height: 34)),
                           with: .color(Self.emergencyRed.opacity(0.55)), style: StrokeStyle(lineWidth: 1.2, dash: [4, 3]))
            }

            // The selected aircraft's remaining route.
            if ac.callsign == selected, ac.routeIndex < ac.route.count {
                var routePath = Path()
                routePath.move(to: p)
                for rp in ac.route[ac.routeIndex...] {
                    routePath.addLine(to: point(east: rp.eastNM, north: rp.northNM))
                }
                // Drawn on top of procedure lines (an aircraft on an approach flies along one): a background-coloured
                // casing, then a bold dashed line in its own colour, then a diamond at each remaining fix.
                ctx.stroke(routePath, with: .color(theme.background), style: StrokeStyle(lineWidth: 5.5, lineCap: .round))
                ctx.stroke(routePath, with: .color(theme.route), style: StrokeStyle(lineWidth: 2.5, dash: [9, 5]))
                for rp in ac.route[ac.routeIndex...] {
                    let q = point(east: rp.eastNM, north: rp.northNM)
                    var diamond = Path()
                    diamond.move(to: CGPoint(x: q.x, y: q.y - 5))
                    diamond.addLine(to: CGPoint(x: q.x + 5, y: q.y))
                    diamond.addLine(to: CGPoint(x: q.x, y: q.y + 5))
                    diamond.addLine(to: CGPoint(x: q.x - 5, y: q.y))
                    diamond.closeSubpath()
                    ctx.fill(diamond, with: .color(theme.route))
                    ctx.stroke(diamond, with: .color(theme.background), lineWidth: 1)
                }
            }

            // Where the aircraft reaches its target level, and (selected, altitude picker open) where it would reach the
            // level under the mouse.
            if !handedOff {
                let levelText: (Double) -> String = { feet in
                    feet > Double(airport.transitionAltitudeFt) ? "FL\(Phraseology.pad3(Int((feet / 100).rounded())))" : "\(Int(feet.rounded())) ft"
                }
                if ac.callsign == selected,
                   let end = ac.levelPoint(reaching: ac.targetAltitudeFt, expedited: ac.expeditingAltitude) {
                    drawLevelMark(ctx, at: point(east: end.eastNM, north: end.northNM), bearingDeg: end.bearingDeg,
                                  colour: trackColor, label: levelText(ac.targetAltitudeFt))
                }
                if ac.callsign == selected, controls.mode == .altitude, let hover = controls.hoverAltitude,
                   abs(Double(hover) - ac.targetAltitudeFt) > 50,
                   let end = ac.levelPoint(reaching: Double(hover), expedited: false) {
                    drawLevelMark(ctx, at: point(east: end.eastNM, north: end.northNM), bearingDeg: end.bearingDeg,
                                  colour: theme.warning, label: levelText(Double(hover)), dashed: true)
                }
            }

            // Velocity vector: where the aircraft will be in one minute (not for aircraft handed off).
            let ahead = LocalProjection.offset(bearingDeg: ac.headingDeg, distanceNM: ac.speedKt / 60)
            var vector = Path()
            vector.move(to: p)
            vector.addLine(to: point(east: ac.eastNM + ahead.east, north: ac.northNM + ahead.north))
            if !handedOff { ctx.stroke(vector, with: .color(trackColor.opacity(0.7)), lineWidth: 1) }

            // Position symbol; filled in the aircraft's colour when it has one, even while selected.
            let symbol = CGRect(x: p.x - 4, y: p.y - 4, width: 8, height: 8)
            if let marker { ctx.fill(Path(symbol), with: .color(marker)) }
            ctx.stroke(Path(symbol), with: .color(trackColor), lineWidth: 1.5)

            // Tag: a box with callsign, speed and altitude (and the last instructions), joined to the symbol by a
            // leader line. Drag the box to move it.
            let lines = tagLines(ac)
            let box = tagFrame(ac, size: size)
            if !box.insetBy(dx: -3, dy: -3).contains(p) {
                let nearest = CGPoint(x: min(max(p.x, box.minX), box.maxX), y: min(max(p.y, box.minY), box.maxY))
                var leader = Path()
                leader.move(to: p)
                leader.addLine(to: nearest)
                ctx.stroke(leader, with: .color(trackColor.opacity(0.6)), lineWidth: 1)
            }
            ctx.fill(Path(roundedRect: box, cornerRadius: 3), with: .color(theme.panel.opacity(handedOff ? 0.5 : 0.82)))
            var boxColour = (ac.callsign == selected || worst[ac.callsign] != nil) ? trackColor : (marker ?? trackColor)
            if emergency != nil { boxColour = Self.emergencyRed }
            ctx.stroke(Path(roundedRect: box, cornerRadius: 3), with: .color(boxColour.opacity(handedOff ? 0.5 : 0.85)),
                       lineWidth: ac.callsign == selected ? 1.6 : 1)
            if let marker {
                // A bar down the left edge of the tag in the aircraft's colour.
                ctx.fill(Path(CGRect(x: box.minX, y: box.minY + 1, width: 3, height: box.height - 2)), with: .color(marker))
            }
            // Airborne on runway heading and still waiting for a vector: that line in the warning colour.
            let unvectored = ac.onRunwayHeading && ac.groundPhase == nil
            for (i, line) in lines.enumerated() {
                let font = Font.ui(size: i == 2 ? 10 : 11, design: .monospaced)
                var colour = i == 2 ? trackColor.opacity(0.7) : trackColor
                if unvectored && line == "RWY HDG" { colour = theme.warning }
                ctx.draw(Text(line).font(font).foregroundColor(colour),
                         at: CGPoint(x: box.minX + 5, y: box.minY + 3 + CGFloat(i) * 13 * UIScale.factor), anchor: .topLeading)
            }
        }
    }
}
