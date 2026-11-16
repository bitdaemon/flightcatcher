import Foundation

/// Point-mass aircraft in local coordinates (nautical miles east and north of the airport reference point).
/// It flies toward target heading, altitude and speed at fixed rates, can follow a route of fixes, and can fly an
/// ILS approach to a landing or a go-around. Ground speed equals indicated speed (no wind).
/// The rates and approach thresholds are placeholders until OpenAP performance data is used.
public struct Aircraft: Equatable, Identifiable {
    public var id: String { callsign }
    public var callsign: String
    public var eastNM: Double
    public var northNM: Double
    public var headingDeg: Double
    public var altitudeFt: Double
    public var speedKt: Double

    public var targetHeadingDeg: Double
    public var targetAltitudeFt: Double
    public var targetSpeedKt: Double
    /// Direction forced by the last heading instruction; nil means the shorter way. Cleared when the turn completes.
    public var targetTurn: TurnDirection?

    public var turnRateDegPerSec: Double
    public var climbRateFpm: Double
    public var descentRateFpm: Double
    public var accelerationKtPerSec: Double

    /// ICAO type designator, if the aircraft has a type (see `AircraftCatalog`).
    public var typeCode: String?
    public var type: AircraftType? { typeCode.flatMap { AircraftCatalog.type(code: $0) } }

    /// Gives the aircraft the type's turn, climb, descent and acceleration rates.
    public mutating func applyType(_ type: AircraftType) {
        typeCode = type.code
        turnRateDegPerSec = type.turnRateDegPerSec
        climbRateFpm = type.climbRateFpm
        descentRateFpm = type.descentRateFpm
        accelerationKtPerSec = type.accelerationKtPerSec
    }

    /// Set by an expedited instruction and cleared when its target is reached.
    public private(set) var expeditingAltitude = false
    public private(set) var expeditingHeading = false
    public private(set) var expeditingSpeed = false
    static let expediteAltitudeFactor = 1.6
    static let expediteTurnFactor = 1.5
    static let expediteSpeedFactor = 2.0

    /// Active route (STAR, then approach legs). The aircraft is flying toward `route[routeIndex]`.
    public var route: [RoutePoint] = []
    public var routeIndex: Int = 0
    /// The STAR or SID the aircraft was given when it appeared (nil for hand-placed aircraft).
    public var procedureId: String?
    /// Lowest level this aircraft may be assigned; set by the simulation from the airport elevation.
    public var levelFloorFt: Int = CommandLimits.minimumLevelFt
    /// Lower floor that applies once the aircraft is cleared for an approach.
    public var approachLevelFloorFt: Int = CommandLimits.minimumLevelFt
    public var effectiveLevelFloorFt: Int { approach == nil ? levelFloorFt : min(levelFloorFt, approachLevelFloorFt) }
    public var approach: ApproachClearance?
    public private(set) var landed = false
    /// A random event decided at spawn and not yet carried out (see `PlannedEvent`).
    public var plannedEvent: PlannedEvent?
    /// Set once the aircraft has declared an emergency.
    public var emergency: EmergencyKind?
    private var pendingEvents: [AircraftEvent] = []

    /// Set while a departure is on the ground: holding short, lined up, or on the take-off roll. Nil in the air.
    public var groundPhase: GroundPhase?
    /// Set for departures, from the holding point until they are handed off.
    public var departure: DepartureInfo?
    public var isOnGround: Bool { groundPhase != nil }
    /// An arrival handed to the tower: it stays on the scope until it lands, but no longer takes instructions.
    /// A go-around hands it back.
    public var handedToTower = false

    /// "Cross FIX at ALTITUDE". `seen` becomes true once the fix has been found on the remaining route.
    public struct Crossing: Equatable {
        public var fix: String
        public var altitudeFt: Double
        public var seen = false
        public var checked = false
    }
    public private(set) var crossing: Crossing?

    /// Inside this distance before the threshold the approach must be stable, or the aircraft goes around.
    static let stableGateNM = 2.5
    static let maxStableSpeedKt = 190.0
    /// While still intercepting, the stable gate only applies this close to the centreline: an aircraft cleared from
    /// far off to the side, level with or behind the threshold, is not on the final approach yet.
    static let gateCorridorNM = 1.0

    public init(callsign: String, eastNM: Double, northNM: Double,
                headingDeg: Double, altitudeFt: Double, speedKt: Double,
                turnRateDegPerSec: Double = 3,
                climbRateFpm: Double = 2000,
                descentRateFpm: Double = 1800,
                accelerationKtPerSec: Double = 1) {
        self.callsign = callsign
        self.eastNM = eastNM
        self.northNM = northNM
        self.headingDeg = headingDeg
        self.altitudeFt = altitudeFt
        self.speedKt = speedKt
        self.targetHeadingDeg = headingDeg
        self.targetAltitudeFt = altitudeFt
        self.targetSpeedKt = speedKt
        self.turnRateDegPerSec = turnRateDegPerSec
        self.climbRateFpm = climbRateFpm
        self.descentRateFpm = descentRateFpm
        self.accelerationKtPerSec = accelerationKtPerSec
    }

    // MARK: Commands

    /// Set a new target from an ATC command (called after the pilot delay).
    public mutating func apply(_ command: Command) {
        switch command {
        case .descend(let feet), .climb(let feet):
            targetAltitudeFt = Double(feet)
            expeditingAltitude = false
        case .cross(let fix, let feet):
            crossing = Crossing(fix: fix, altitudeFt: Double(feet))
        case .heading(let degrees, let turn):
            targetHeadingDeg = Double(degrees % 360)
            targetTurn = turn
            expeditingHeading = false
            crossing = nil
            route = []
            routeIndex = 0
            departure?.vectored = true
            if let phase = approach?.phase, phase != .intercepting { approach = nil }
        case .speed(let knots):
            targetSpeedKt = Double(knots)
            expeditingSpeed = false
        case .expedite(let inner):
            apply(inner)
            switch inner {
            case .descend, .climb: expeditingAltitude = true
            case .heading: expeditingHeading = true
            case .speed: expeditingSpeed = true
            default: break
            }
        case .maintain:
            maintainPresent()
        case .lineUp:
            if groundPhase == .holdingShort { groundPhase = .linedUp }
        case .takeoff:
            if groundPhase == .holdingShort || groundPhase == .linedUp { groundPhase = .takeoffRoll }
        case .handoff:
            if departure != nil { departure?.handedOff = true } else { handedToTower = true }
        case .approach, .visualApproach, .direct, .route, .joinApproach, .resumeNavigation:
            break // need airport data: the simulation sets the route and calls clearForApproach
        }
    }

    /// Drop every standing instruction and keep flying as now: heading, altitude and speed stay at their present values.
    /// An approach still being intercepted is cancelled; one already established is left to `Command.refusal`.
    public mutating func maintainPresent() {
        targetHeadingDeg = headingDeg
        targetTurn = nil
        targetAltitudeFt = altitudeFt
        targetSpeedKt = speedKt
        expeditingAltitude = false
        expeditingHeading = false
        expeditingSpeed = false
        crossing = nil
        route = []
        routeIndex = 0
        if approach?.phase == .intercepting { approach = nil }
    }

    /// Replace the route and fly it from its first point. An approach already being flown (localiser or glideslope)
    /// is abandoned; one that is still intercepting is kept.
    public mutating func setRoute(_ points: [RoutePoint]) {
        route = points
        routeIndex = 0
        departure?.vectored = true
        targetTurn = nil
        if let phase = approach?.phase, phase != .intercepting { approach = nil }
    }

    /// Cleared for the ILS. `extraRoute` joins the approach legs onto the end of a route being flown.
    public mutating func clearForApproach(_ ils: ILSGeometry, extraRoute: [RoutePoint]) {
        approach = ApproachClearance(ils: ils, phase: .intercepting)
        if !extraRoute.isEmpty { route += extraRoute }
    }

    public mutating func drainEvents() -> [AircraftEvent] {
        let events = pendingEvents
        pendingEvents = []
        return events
    }

    // MARK: Geometry helpers

    static func normalized(_ degrees: Double) -> Double {
        let r = degrees.truncatingRemainder(dividingBy: 360)
        return r < 0 ? r + 360 : r
    }

    public static func bearingDeg(eastNM: Double, northNM: Double) -> Double {
        normalized(atan2(eastNM, northNM) * 180 / .pi)
    }

    /// Signed turn from one heading to another, in (-180, 180]. Positive is a right turn; exactly 180 turns right.
    static func signedTurn(from: Double, to: Double) -> Double {
        var d = (to - from).truncatingRemainder(dividingBy: 360)
        if d > 180 { d -= 360 } else if d <= -180 { d += 360 }
        return d
    }

    // MARK: One second of flight

    public mutating func advance(seconds: Double, wind: Wind = .calm) {
        if let phase = groundPhase {
            advanceOnGround(phase, seconds: seconds)
            return
        }
        if let d = departure, altitudeFt < d.fieldElevationFt + 400 {
            targetHeadingDeg = headingDeg // runway heading until 400 ft above the field
            targetTurn = nil
        } else {
            guideLateral()
        }
        guideCrossing()

        // Heading: the commanded direction if there is one, otherwise the shorter way. Limited by turn rate.
        let turn: Double
        switch targetTurn {
        case .right?: turn = Self.normalized(targetHeadingDeg - headingDeg)
        case .left?: turn = -Self.normalized(headingDeg - targetHeadingDeg)
        case nil: turn = Self.signedTurn(from: headingDeg, to: targetHeadingDeg)
        }
        let maxTurn = turnRateDegPerSec * (expeditingHeading ? Self.expediteTurnFactor : 1) * seconds
        if abs(turn) <= maxTurn {
            headingDeg = targetHeadingDeg
            targetTurn = nil
        } else {
            headingDeg += turn > 0 ? maxTurn : -maxTurn
        }
        headingDeg = Self.normalized(headingDeg)
        if headingDeg == targetHeadingDeg { expeditingHeading = false }

        // Altitude (on the glidepath it follows the beam instead).
        if approach?.phase != .glideslope {
            let altDelta = targetAltitudeFt - altitudeFt
            let maxAlt = (altDelta > 0 ? climbRateFpm : descentRateFpm) / 60 * seconds * (expeditingAltitude ? Self.expediteAltitudeFactor : 1)
            altitudeFt = abs(altDelta) <= maxAlt ? targetAltitudeFt : altitudeFt + (altDelta > 0 ? maxAlt : -maxAlt)
        }
        if altitudeFt == targetAltitudeFt { expeditingAltitude = false }

        // Speed.
        let spdDelta = targetSpeedKt - speedKt
        let maxSpd = accelerationKtPerSec * (expeditingSpeed ? Self.expediteSpeedFactor : 1) * seconds
        speedKt = abs(spdDelta) <= maxSpd ? targetSpeedKt : speedKt + (spdDelta > 0 ? maxSpd : -maxSpd)
        if speedKt == targetSpeedKt { expeditingSpeed = false }

        // Position.
        let d = LocalProjection.offset(bearingDeg: headingDeg, distanceNM: speedKt / 3600 * seconds)
        let w = wind.vectorKt(atAltitudeFt: altitudeFt)
        eastNM += d.east + w.east / 3600 * seconds
        northNM += d.north + w.north / 3600 * seconds

        if var d = departure, !d.checkedIn, altitudeFt >= d.fieldElevationFt + 1500 {
            d.checkedIn = true
            departure = d
            pendingEvents.append(.checkedIn(passingFt: Int((altitudeFt / 100).rounded()) * 100,
                                            climbingToFt: d.initialAltitudeFt, sid: d.sid))
        }
        updateApproachAfterMove()
    }

    /// Take-off roll: accelerate along the runway heading, then leave the ground at the rotation speed.
    private mutating func advanceOnGround(_ phase: GroundPhase, seconds: Double) {
        guard phase == .takeoffRoll, let d = departure else { return }
        speedKt += max(2.0, accelerationKtPerSec * 3) * seconds
        let o = LocalProjection.offset(bearingDeg: headingDeg, distanceNM: speedKt / 3600 * seconds)
        eastNM += o.east
        northNM += o.north
        if speedKt >= d.rotateSpeedKt {
            groundPhase = nil
            targetAltitudeFt = Double(d.initialAltitudeFt)
            targetSpeedKt = min(Double(type?.maxSpeedKt ?? 250), 250)
            targetHeadingDeg = headingDeg
            targetTurn = nil
            pendingEvents.append(.tookOff(runway: d.runway))
        }
    }

    // MARK: Crossing restrictions

    /// Holds the present level until the descent (or climb) to the crossing level must start to be there at the fix.
    private mutating func guideCrossing() {
        guard var c = crossing, approach?.phase != .glideslope else { return }
        guard routeIndex < route.count, let k = route[routeIndex...].firstIndex(where: { $0.id == c.fix }) else {
            if c.seen { crossing = nil } // route replaced or abandoned
            return
        }
        c.seen = true
        var distance = ((route[routeIndex].eastNM - eastNM) * (route[routeIndex].eastNM - eastNM)
                        + (route[routeIndex].northNM - northNM) * (route[routeIndex].northNM - northNM)).squareRoot()
        var i = routeIndex
        while i < k {
            let dx = route[i + 1].eastNM - route[i].eastNM
            let dy = route[i + 1].northNM - route[i].northNM
            distance += (dx * dx + dy * dy).squareRoot()
            i += 1
        }
        let delta = c.altitudeFt - altitudeFt
        if abs(delta) <= 50 {
            targetAltitudeFt = c.altitudeFt
        } else {
            let rate = (delta > 0 ? climbRateFpm : descentRateFpm) / 60 // ft per second
            let needed = abs(delta) / rate
            let available = distance / max(speedKt, 1) * 3600
            if !c.checked {
                c.checked = true
                if available < needed - 15 {
                    pendingEvents.append(.crossingUnable(fix: c.fix, altitudeFt: Int(c.altitudeFt)))
                }
            }
            targetAltitudeFt = available <= needed + 8 ? c.altitudeFt : altitudeFt
        }
        crossing = c
    }

    // MARK: Lateral guidance

    private mutating func guideLateral() {
        if let app = approach {
            let p = app.ils.position(eastNM: eastNM, northNM: northNM)
            if app.phase == .intercepting, canCaptureLocaliser(app.ils, along: p.along, cross: p.cross) {
                approach?.phase = .localiser
                route = []
                routeIndex = 0
                pendingEvents.append(.established(runway: app.ils.runwayId))
            }
            if approach?.phase != .intercepting {
                // Steer onto the course: up to 30 degrees of intercept, 40 degrees per NM of offset.
                let offset = max(-30, min(30, p.cross * 40))
                targetHeadingDeg = Self.normalized(app.ils.courseDeg - offset)
                targetTurn = nil
                return
            }
        }
        guideAlongRoute()
    }

    /// Captures when close enough to start the turn onto the course, closing on it, and not too steep.
    private func canCaptureLocaliser(_ ils: ILSGeometry, along: Double, cross: Double) -> Bool {
        captureBlock(ils, along: along, cross: cross) == nil
    }

    /// Why the localiser cannot be captured right now, or nil when it can. This is the capture rule itself, so the
    /// debug log, the pilot's call and the aircraft always agree.
    private func captureBlock(_ ils: ILSGeometry, along: Double, cross: Double) -> CaptureBlock? {
        func f(_ value: Double) -> String { String(format: "%.1f", value) }
        if along <= Self.stableGateNM {
            return CaptureBlock(kind: .insideGate,
                                text: "inside the \(f(Self.stableGateNM)) NM gate, \(f(along)) NM from the threshold")
        }
        if along >= 30 {
            return CaptureBlock(kind: .tooFar, text: "too far out, \(f(along)) NM from the threshold (limit 30)")
        }
        let delta = abs(Self.signedTurn(from: headingDeg, to: ils.courseDeg))
        if delta > 60 {
            return CaptureBlock(kind: .headingOff,
                                text: "heading \(Int(headingDeg.rounded())) is \(Int(delta.rounded())) degrees off the course \(Int(ils.courseDeg.rounded())) (limit 60)")
        }
        let h = headingDeg * .pi / 180
        let c = ils.courseDeg * .pi / 180
        let towardRight = sin(h) * cos(c) - cos(h) * sin(c) // velocity component to the right of the course
        if !(cross * towardRight < 0 || abs(cross) < 0.05) {
            return CaptureBlock(kind: .notClosing, text: "not closing on the course, \(f(abs(cross))) NM off it and moving away")
        }
        let radius = (speedKt / 3600) / (turnRateDegPerSec * .pi / 180)
        let lead = radius * (1 - cos(delta * .pi / 180)) + 0.1
        if abs(cross) > lead {
            return CaptureBlock(kind: .offCourse, text: "\(f(abs(cross))) NM off the course, turn starts within \(f(lead)) NM")
        }
        return nil
    }

    /// For the debug log: why an arrival cleared for an approach has not captured the localiser yet. Nil when it is not
    /// intercepting or can capture now.
    public func captureBlocker() -> String? {
        guard let app = approach, app.phase == .intercepting else { return nil }
        let p = app.ils.position(eastNM: eastNM, northNM: northNM)
        return captureBlock(app.ils, along: p.along, cross: p.cross)?.text
    }

    /// The kind of reason, for the pilot's call.
    public func captureBlockKind() -> CaptureBlockKind? {
        guard let app = approach, app.phase == .intercepting else { return nil }
        let p = app.ils.position(eastNM: eastNM, northNM: northNM)
        return captureBlock(app.ils, along: p.along, cross: p.cross)?.kind
    }

    private mutating func guideAlongRoute() {
        guard !route.isEmpty else { return }
        var steps = 0
        while routeIndex < route.count, steps < 4 {
            steps += 1
            let fix = route[routeIndex]
            let toE = fix.eastNM - eastNM
            let toN = fix.northNM - northNM
            let distance = (toE * toE + toN * toN).squareRoot()
            var passed: Bool
            if routeIndex + 1 < route.count {
                // Start the turn early by the distance the turn needs.
                let next = route[routeIndex + 1]
                let radius = (speedKt / 3600) / (turnRateDegPerSec * .pi / 180)
                let nowBearing = Self.bearingDeg(eastNM: toE, northNM: toN)
                let nextBearing = Self.bearingDeg(eastNM: next.eastNM - fix.eastNM, northNM: next.northNM - fix.northNM)
                let delta = abs(Self.signedTurn(from: nowBearing, to: nextBearing))
                passed = distance <= max(0.15, radius * tan(min(delta, 150) * .pi / 360))
            } else {
                passed = distance <= 0.3
            }
            if !passed, distance < 1.5 {
                // Safety net: close to the fix and already moving away from it.
                let h = headingDeg * .pi / 180
                if sin(h) * toE + cos(h) * toN < 0 { passed = true }
            }
            if passed {
                if let c = crossing, c.fix == fix.id {
                    targetAltitudeFt = c.altitudeFt // over the fix: whatever is left is flown now
                    crossing = nil
                }
                routeIndex += 1
            } else { break }
        }
        if routeIndex >= route.count {
            if approach == nil, let last = route.last {
                let rounded = Int(headingDeg.rounded()) % 360
                pendingEvents.append(.routeEnded(fix: last.id, headingDeg: rounded == 0 ? 360 : rounded))
            }
            crossing = nil
            route = []
            routeIndex = 0
            targetHeadingDeg = headingDeg // end of route: hold the present heading
            targetTurn = nil
            return
        }
        let fix = route[routeIndex]
        targetHeadingDeg = Self.bearingDeg(eastNM: fix.eastNM - eastNM, northNM: fix.northNM - northNM)
        targetTurn = nil
    }

    // MARK: Glidepath, landing and go-around

    private mutating func updateApproachAfterMove() {
        guard let app = approach else { return }
        let ils = app.ils
        let p = ils.position(eastNM: eastNM, northNM: northNM)
        let beam = ils.glidepathAltitudeFt(distanceNM: max(p.along, 0))

        // Glidepath capture from below, or from just above.
        if app.phase == .localiser, p.along > 0 {
            let diff = beam - altitudeFt
            if diff <= 50, diff >= -300 { approach?.phase = .glideslope }
        }

        if approach?.phase == .glideslope {
            let diff = beam - altitudeFt
            altitudeFt = abs(diff) <= 60 ? beam : altitudeFt + max(-40, min(40, diff))
            targetAltitudeFt = altitudeFt
            let limit: Double
            if let vapp = type?.approachSpeedKt {
                limit = p.along > 8 ? vapp + 45 : (p.along > 5 ? vapp + 25 : vapp + 5)
            } else {
                limit = p.along > 8 ? 180.0 : (p.along > 5 ? 160.0 : 140.0)
            }
            targetSpeedKt = min(targetSpeedKt, limit)

            if p.along <= 0 {
                landed = true
                approach = nil
                pendingEvents.append(.landed(runway: ils.runwayId))
                return
            }
        }

        // Stable approach gate: once established, or while intercepting only when actually on the final approach
        // (near the centreline, not past the threshold).
        let onFinal = approach?.phase != .intercepting || (abs(p.cross) <= Self.gateCorridorNM && p.along > -0.5)
        if p.along <= Self.stableGateNM, onFinal {
            if approach?.phase != .glideslope {
                let above = Int((altitudeFt - beam).rounded())
                goAround(reason: above > 300 ? "\(above) ft above the glidepath inside \(Self.stableGateNM) NM"
                                             : "not established inside \(Self.stableGateNM) NM")
            } else if speedKt > Self.maxStableSpeedKt {
                goAround(reason: "unstable, \(Int(speedKt.rounded())) kt inside \(Self.stableGateNM) NM")
            }
        }
    }

    /// Where the aircraft will be when it reaches `levelFt` at its current speed, on its route (or straight along its
    /// heading when it has none), and the direction it is flying there. Nil when it is already at that level, on the
    /// ground or on the glidepath. `expedited` uses the faster expedite rate.
    public func levelPoint(reaching levelFt: Double, expedited: Bool) -> (eastNM: Double, northNM: Double, bearingDeg: Double)? {
        guard !isOnGround, approach?.phase != .glideslope else { return nil }
        let delta = levelFt - altitudeFt
        guard abs(delta) > 50 else { return nil }
        let rateFpm = (delta > 0 ? climbRateFpm : descentRateFpm) * (expedited ? Self.expediteAltitudeFactor : 1)
        guard rateFpm > 0 else { return nil }
        var remaining = speedKt * (abs(delta) / rateFpm) / 60 // NM flown while changing level
        var east = eastNM
        var north = northNM
        var bearing = route.indices.contains(routeIndex) ? headingDeg : targetHeadingDeg
        var i = routeIndex
        while remaining > 0, i < route.count {
            let dx = route[i].eastNM - east
            let dy = route[i].northNM - north
            let leg = (dx * dx + dy * dy).squareRoot()
            if leg > 0 { bearing = Self.bearingDeg(eastNM: dx, northNM: dy) }
            if leg >= remaining {
                let f = leg > 0 ? remaining / leg : 0
                return (east + dx * f, north + dy * f, bearing)
            }
            east = route[i].eastNM
            north = route[i].northNM
            remaining -= leg
            i += 1
        }
        let step = LocalProjection.offset(bearingDeg: bearing, distanceNM: remaining)
        return (east + step.east, north + step.north, bearing)
    }

    /// Break off the approach, for example because the runway is occupied.
    public mutating func abortApproach(reason: String) { goAround(reason: reason) }

    private mutating func goAround(reason: String) {
        handedToTower = false
        let course = approach?.ils.courseDeg ?? headingDeg
        // Missed approach altitude: about 2500 ft above the field, in whole thousands, never below 3000 ft.
        let field = approach?.ils.thresholdElevationFt ?? 0
        let missedAltitude = max(3000.0, ((field + 2500) / 1000).rounded(.up) * 1000)
        pendingEvents.append(.wentAround(reason: reason))
        approach = nil
        route = []
        routeIndex = 0
        targetHeadingDeg = Self.normalized(course)
        targetTurn = nil
        targetAltitudeFt = missedAltitude
        targetSpeedKt = 200
    }

    // MARK: Callsign parts and labels

    public var callsignLetters: String { String(callsign.prefix(while: { $0.isLetter })) }
    public var callsignNumber: String { String(callsign.drop(while: { $0.isLetter })) }
    public var radioName: String? { RadioNames.table[callsignLetters.uppercased()] }

    /// Top line of the track label.
    public var labelTop: String { callsign }

    /// Bottom line: speed in knots, then altitude in hundreds of feet, both three digits ("220 070").
    public var labelBottom: String {
        if let phase = groundPhase { return "\(phase.label) \(departure?.runway ?? "")" }
        let text = "\(Phraseology.pad3(Int(speedKt.rounded()))) \(Phraseology.pad3(Int((altitudeFt / 100).rounded())))"
        return handedToTower ? text + " TWR" : text
    }

    /// A departure without a SID that has not yet been given a heading, direct or route: it flies runway heading.
    public var onRunwayHeading: Bool {
        guard let d = departure, d.sid.isEmpty, !d.vectored, !d.handedOff else { return false }
        return true
    }

    /// Short navigation status for the aircraft list: next fix, ILS?, LOC, G/S, HDG, or RWYHDG.
    public var navLabel: String {
        if let phase = groundPhase { return phase.label }
        if onRunwayHeading { return "RWYHDG" }
        if handedToTower { return "TWR" }
        if let phase = approach?.phase {
            if phase == .glideslope { return "G/S" }
            if phase == .localiser { return "LOC" }
        }
        if routeIndex < route.count { return route[routeIndex].id }
        return approach != nil ? "ILS" : "HDG"
    }
}

/// Radio telephony names by ICAO airline designator, taken from `AirlineTable`.
public enum RadioNames {
    public static let table: [String: String] = AirlineTable.radioNames
}

/// Why an aircraft cleared for an approach cannot capture the localiser from where it is.
public enum CaptureBlockKind: Equatable {
    case insideGate, tooFar, headingOff, notClosing, offCourse
}

struct CaptureBlock {
    let kind: CaptureBlockKind
    let text: String
}
