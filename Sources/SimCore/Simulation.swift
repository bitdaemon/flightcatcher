import Foundation

/// One line on the radio, or a simulation notice.
public struct RadioMessage: Equatable, Identifiable {
    public enum Speaker: Equatable { case controller, pilot, system }
    public let id: Int
    public let tick: Int
    public let speaker: Speaker
    public let text: String
    /// The aircraft this call is to or from, when there is one; the UI uses it to highlight the selected aircraft's calls.
    public var callsign: String? = nil
    /// What kind of notable call this is (refusal, emergency, go-around...), for the radio window's tag column.
    public var tag: RadioTag? = nil
    /// Controller calls: the instruction as it would be typed on the command bar ("aal123 d70 s180"). For a chain,
    /// the whole chain is on its first call and the others have none.
    public var code: String? = nil
}

/// A label for the calls that matter, shown in the radio window between the callsign and the message.
public enum RadioTag: String, Equatable, CaseIterable {
    case mayday = "MAYDAY", panPan = "PAN PAN", emergency = "EMERG"
    case lossOfSeparation = "LOSS", conflict = "CONFLICT"
    case goAround = "G/A", windshear = "WSHEAR"
    case refused = "REFUSED", unable = "UNABLE", high = "HIGH"
    /// A macro stopped because one of its steps was refused or the pilot was unable.
    case macro = "M!"

    public enum Severity: Equatable { case critical, warning }
    public var severity: Severity {
        switch self {
        case .mayday, .panPan, .emergency, .lossOfSeparation: return .critical
        default: return .warning
        }
    }
}

/// What is occupying a runway, for the runway display.
public enum RunwayUse: Equatable {
    case departing(callsign: String)
    case landing(callsign: String, nm: Double)
}

public enum IssueResult: Equatable {
    case accepted(delaySeconds: Int)
    case refused(String)
}

/// Deterministic, UI-free simulation. One call to `tick()` advances one second of simulated time.
/// Nothing in here may read the wall clock, use global randomness or touch the UI.
public final class Simulation {
    public let seed: UInt64
    public let transitionAltitudeFt: Int
    public let airport: AirportPackage?
    public private(set) var tickCount: Int = 0
    public private(set) var aircraft: [Aircraft] = []
    public private(set) var radioLog: [RadioMessage] = []
    /// Current conflicts, most serious first: actual losses of separation, then predicted ones by time to loss.
    public private(set) var conflicts: [Conflict] = []
    /// Number of separate losses of separation so far (a pair counts once per occurrence).
    public private(set) var lossOfSeparationCount = 0
    /// Departures that flew out of the area without being handed off.
    public private(set) var missedHandoffs = 0
    /// Departures that get this far from the airport without a handoff are removed and counted as missed.
    /// The player's airspace: a circle around the airport reference point, up to a ceiling. Arrivals are handed in
    /// where their STAR enters it; departures must be handed off before they leave it.
    public var areaRadiusNM = 40.0
    public var areaCeilingFt = 15000
    private var alertedKinds: [String: Conflict.Kind] = [:]

    // MARK: Score state
    /// The session's score. Starts with the simulation; `endSession` closes it for the debrief.
    public private(set) var score = ScoreCard()
    private var nextScoreID = 0
    /// Where and when each arrival was handed in (or placed), for its efficiency.
    private var arrivalStart: [String: (tick: Int, east: Double, north: Double)] = [:]
    private var instructionCounts: [String: Int] = [:]
    private var lastInstructionTick: [String: Int] = [:]
    /// Seconds each current loss of separation has lasted, by conflict id.
    private var lossSeconds: [String: Int] = [:]
    private var holdingSince: [String: Int] = [:]
    private var runwayHeadingPenalised: Set<String> = []
    private var emergencySince: [String: Int] = [:]
    private var emergencyChecked: Set<String> = []
    private var rateSeconds = 0
    private var rateSum = 0.0

    /// Current wind (one wind for the whole airspace; stronger aloft).
    public private(set) var wind: Wind = .calm
    /// Runways the wind currently allows, and the reason for each closed one.
    public private(set) var runwayStatuses: [RunwayStatus] = []
    public var openRunways: Set<String> { Set(runwayStatuses.filter(\.isOpen).map(\.id)) }
    private var weatherRng: SeededRNG
    private let windDrifts: Bool
    /// Where the wind comes from; see `WeatherMode`.
    public var weatherMode: WeatherMode = .random
    /// The wind the live observation asks for; the actual wind eases toward it a little each minute.
    private var windTarget: Wind?
    /// The last live observation received.
    public private(set) var liveReport: WeatherReport?

    private struct PendingCommand {
        var executeAtTick: Int
        var callsign: String
        var command: Command
        var readback: String
    }

    private var pending: [PendingCommand] = []

    /// The latest accepted instructions per callsign, oldest first (at most `historyLimit` each).
    public private(set) var commandHistory: [String: [CommandRecord]] = [:]
    public static let historyLimit = 12
    private var nextRecordID = 0

    private func recordCommand(_ issued: IssuedCommand, executeAtTick: Int) {
        var list = commandHistory[issued.callsign] ?? []
        list.append(CommandRecord(id: nextRecordID, callsign: issued.callsign, command: issued.command,
                                  issuedTick: tickCount, executeAtTick: executeAtTick))
        nextRecordID += 1
        if list.count > Self.historyLimit { list.removeFirst(list.count - Self.historyLimit) }
        commandHistory[issued.callsign] = list
    }

    /// Random traffic. Off by default so tests and scripted scenarios stay in control of the aircraft.
    public var traffic = TrafficSettings() {
        didSet { if traffic.enabled && !oldValue.enabled { queuedArrivals = max(queuedArrivals, 1) } }
    }
    private var trafficRng: SeededRNG
    /// Moves the traffic rates inside their ranges. Its own sequence, so fixed-rate traffic is unchanged by it.
    private var rateRng: SeededRNG
    /// Arrivals and departures per hour in use now, inside the ranges in `traffic`.
    public private(set) var arrivalRatePerHour: Double = 0
    public private(set) var departureRatePerHour: Double = 0
    /// Where the rates are heading.
    public private(set) var arrivalTargetPerHour: Double = 0
    public private(set) var departureTargetPerHour: Double = 0
    private var nextRateChangeTick = 0
    private var ratesStarted = false
    /// Random events (go-arounds, windshear, emergencies): percentages of arrivals. Off by default.
    public var events = EventSettings()
    private var eventRng: SeededRNG
    private var queuedArrivals = 0
    private var nextMessageID = 0
    private var rng: SeededRNG
    private var digest: UInt64 = 0xCBF2_9CE4_8422_2325 // FNV-1a offset basis
    private let projection: LocalProjection?
    private var fixIndex: [String: (east: Double, north: Double)] = [:]

    /// `initialWind` overrides the randomly chosen starting wind; `windDrifts: false` freezes it (used by tests).
    /// Without airport data there are no runways, so the wind stays calm.
    public init(seed: UInt64, transitionAltitudeFt: Int = 5000, airport: AirportPackage? = nil,
                initialWind: Wind? = nil, windDrifts: Bool = true) {
        self.seed = seed
        self.transitionAltitudeFt = transitionAltitudeFt
        self.airport = airport
        self.rng = SeededRNG(seed: seed)
        self.weatherRng = SeededRNG(seed: seed ^ 0x5EA7_4E12_D00D_F00D)
        self.trafficRng = SeededRNG(seed: seed ^ 0x7AF1_C5EE_D0F1_2B3D)
        self.eventRng = SeededRNG(seed: seed ^ 0x3E0E_17AC_91D5_6B21)
        self.rateRng = SeededRNG(seed: seed ^ 0x51C3_D7A0_9E37_79B9)
        self.windDrifts = windDrifts
        if let airport {
            let proj = airport.referenceProjection
            projection = proj
            for fix in airport.fixes {
                let p = proj.nm(lat: fix.lat, lon: fix.lon)
                fixIndex[fix.id] = (p.east, p.north)
            }
        } else {
            projection = nil
        }

        if let airport, !airport.runways.isEmpty {
            if let initialWind {
                wind = initialWind
            } else {
                // A playable start: within 40 degrees of a runway heading, 6 to 20 kt.
                let runway = airport.runways[Int(weatherRng.next() % UInt64(airport.runways.count))]
                wind = Wind(fromDeg: runway.trueBearingDeg + unitWeather() * 80 - 40, speedKt: 6 + unitWeather() * 14)
            }
            runwayStatuses = evaluateRunways(for: wind, previouslyOpen: Set(airport.runways.map(\.id)))
        }
    }

    // MARK: Weather

    private func unitWeather() -> Double { Double(weatherRng.next() >> 11) / Double(1 << 53) }

    private func evaluateRunways(for wind: Wind, previouslyOpen: Set<String>) -> [RunwayStatus] {
        guard let airport else { return [] }
        var statuses = airport.runways.map { runway -> RunwayStatus in
            let c = wind.components(runwayBearingDeg: runway.trueBearingDeg)
            // The limits are judged on the gusts; the runway in use is chosen on the mean wind.
            let g = wind.components(runwayBearingDeg: runway.trueBearingDeg, gusts: true)
            let margin = previouslyOpen.contains(runway.id) ? 0 : WindLimits.reopenMarginKt
            let tailwind = max(0, -g.head)
            let gusty = wind.isGusting ? " (gusts)" : ""
            var reason = ""
            if tailwind > WindLimits.maxTailwindKt - margin {
                reason = "tailwind \(Int(tailwind.rounded())) kt" + gusty
            } else if g.cross > WindLimits.maxCrosswindKt - margin {
                reason = "crosswind \(Int(g.cross.rounded())) kt" + gusty
            }
            return RunwayStatus(id: runway.id, isOpen: reason.isEmpty, headwindKt: c.head, crosswindKt: c.cross, reason: reason)
        }
        // As at a real airport, only one direction of a strip is in use: the one facing the wind. Ties (calm) go to
        // the runway listed first, and the direction in use only changes when the other end is clearly better.
        for i in statuses.indices {
            guard let j = statuses.firstIndex(where: { $0.id == Self.oppositeRunway(statuses[i].id) }), j > i,
                  statuses[i].isOpen, statuses[j].isOpen else { continue }
            var keepFirst = statuses[i].headwindKt >= statuses[j].headwindKt
            let firstWas = previouslyOpen.contains(statuses[i].id)
            let secondWas = previouslyOpen.contains(statuses[j].id)
            if firstWas != secondWas,
               abs(statuses[i].headwindKt - statuses[j].headwindKt) <= WindLimits.directionChangeKt {
                keepFirst = firstWas
            }
            let loser = keepFirst ? j : i
            statuses[loser].isOpen = false
            statuses[loser].reason = "runway \(statuses[keepFirst ? i : j].id) in use"
        }
        return statuses
    }

    /// Random walk of the wind once a minute. A change is only accepted if at least one runway stays usable,
    /// so the game never ends up with nowhere to land.
    private func driftWind() {
        guard airport != nil, weatherMode != .fixed else { return }
        let candidate: Wind
        if weatherMode == .live, let target = windTarget {
            candidate = Self.easeWind(wind, toward: target)
            if candidate == wind { return }
        } else {
            guard windDrifts else { return }
            candidate = Wind(fromDeg: wind.fromDeg + unitWeather() * 8 - 4,
                             speedKt: min(25, max(2, wind.speedKt + unitWeather() * 2 - 1)))
        }
        let before = openRunways
        let statuses = evaluateRunways(for: candidate, previouslyOpen: before)
        guard statuses.contains(where: \.isOpen) else { return }
        wind = candidate
        runwayStatuses = statuses
        for status in statuses {
            if before.contains(status.id) && !status.isOpen {
                log(.system, "Runway \(status.id) closed: \(status.reason)")
            } else if !before.contains(status.id) && status.isOpen {
                log(.system, "Runway \(status.id) open again")
            }
        }
    }

    /// One minute of easing toward a live wind: up to 10 degrees, 2 kt of speed and 2 kt of gust speed, so the runway in
    /// use changes gradually rather than at once.
    static func easeWind(_ current: Wind, toward target: Wind) -> Wind {
        func step(_ from: Double, _ to: Double, _ limit: Double) -> Double { from + max(-limit, min(limit, to - from)) }
        let turn = max(-10, min(10, Aircraft.signedTurn(from: current.fromDeg, to: target.fromDeg)))
        let speed = step(current.speedKt, target.speedKt, 2)
        let gust = step(current.gustKt, target.gustKt, 2)
        return Wind(fromDeg: current.fromDeg + turn, speedKt: speed, gustKt: gust)
    }

    /// A live observation. The wind eases toward it; with `immediately` it is adopted at once, which is for the start
    /// of a session. Nothing is adopted that would leave no usable runway.
    public func setLiveWeather(_ report: WeatherReport, immediately: Bool = false) {
        liveReport = report
        let target = Wind(fromDeg: report.fromDeg ?? wind.fromDeg, speedKt: report.speedKt, gustKt: report.gustKt)
        windTarget = target
        guard immediately, let airport else { return }
        let statuses = evaluateRunways(for: target, previouslyOpen: Set(airport.runways.map(\.id)))
        guard statuses.contains(where: \.isOpen) else { return }
        wind = target
        runwayStatuses = statuses
    }

    /// A procedure is available when at least one runway it serves is open (all of them if it names none).
    public func isAvailable(_ procedure: Procedure) -> Bool {
        guard airport != nil, !procedure.runways.isEmpty else { return true }
        let open = openRunways
        return procedure.runways.contains(where: open.contains)
    }

    public func closedReason(runway: String) -> String? {
        guard let status = runwayStatuses.first(where: { $0.id == runway }), !status.isOpen else { return nil }
        return status.reason
    }

    /// Simulated seconds since start.
    public var elapsedSeconds: Int { tickCount }

    // MARK: Airport data

    public func routePoints(for legs: [Leg]) -> [RoutePoint] {
        legs.compactMap { leg in
            guard let p = fixIndex[leg.fixId] else { return nil }
            return RoutePoint(id: leg.fixId, eastNM: p.east, northNM: p.north,
                              altitude: leg.altitude, maxSpeedKt: leg.maxSpeedKt)
        }
    }

    public func ilsGeometry(runway id: String) -> ILSGeometry? {
        guard let airport, let projection,
              let rwy = airport.runways.first(where: { $0.id == id }),
              let ils = rwy.ils else { return nil }
        let t = projection.nm(lat: rwy.thresholdLat, lon: rwy.thresholdLon)
        return ILSGeometry(runwayId: id, thresholdEastNM: t.east, thresholdNorthNM: t.north,
                           courseDeg: rwy.trueBearingDeg, glidepathDeg: ils.glidepathDeg,
                           thresholdElevationFt: Double(rwy.thresholdElevationFt),
                           thresholdCrossingHeightFt: Double(ils.thresholdCrossingHeightFt))
    }

    /// The geometry to fly to a runway: its ILS where there is one, otherwise a visual approach on the extended
    /// centreline with a 3 degree path and a 50 ft threshold crossing height.
    public func approachGeometry(runway id: String) -> ILSGeometry? {
        if let ils = ilsGeometry(runway: id) { return ils }
        guard let airport, let projection,
              let rwy = airport.runways.first(where: { $0.id == id }) else { return nil }
        let t = projection.nm(lat: rwy.thresholdLat, lon: rwy.thresholdLon)
        return ILSGeometry(runwayId: id, thresholdEastNM: t.east, thresholdNorthNM: t.north,
                           courseDeg: rwy.trueBearingDeg, glidepathDeg: 3.0,
                           thresholdElevationFt: Double(rwy.thresholdElevationFt),
                           thresholdCrossingHeightFt: 50, isVisual: true)
    }

    /// The final approach geometry for an approach procedure: the runway's ILS for an ILS approach; for RNAV, the
    /// runway's centreline with the published path angle (3 degrees if none) and the ILS threshold crossing height
    /// where the runway has one, else 50 ft. RNAV finals are imported only when lined up with the runway.
    public func approachGeometry(procedure: Procedure) -> ILSGeometry? {
        guard let runway = procedure.runways.first else { return nil }
        if procedure.finalApproachType == .ils { return ilsGeometry(runway: runway) }
        guard let airport, let projection,
              let rwy = airport.runways.first(where: { $0.id == runway }) else { return nil }
        let t = projection.nm(lat: rwy.thresholdLat, lon: rwy.thresholdLon)
        return ILSGeometry(runwayId: runway, thresholdEastNM: t.east, thresholdNorthNM: t.north,
                           courseDeg: rwy.trueBearingDeg, glidepathDeg: procedure.glidepathDeg ?? 3.0,
                           thresholdElevationFt: Double(rwy.thresholdElevationFt),
                           thresholdCrossingHeightFt: Double(rwy.ils?.thresholdCrossingHeightFt ?? 50))
    }

    /// True when the runway exists but has no ILS, so an approach to it is visual.
    public func isVisualRunway(_ id: String) -> Bool {
        airport?.runways.first(where: { $0.id == id }).map { $0.ils == nil } ?? false
    }

    /// The approach that starts at `fix` for the runway, if the airport data has one.
    private func approachLegs(runway: String, after fix: String) -> [RoutePoint] {
        guard let airport,
              let proc = airport.procedures.first(where: {
                  $0.kind == .approach && $0.finalApproachType == .ils && $0.runways.contains(runway) && $0.legs.first?.fixId == fix
              }) else { return [] }
        return routePoints(for: Array(proc.legs.dropFirst()))
    }

    /// Every fix identifier of the loaded airport.
    public var fixIdentifiers: Set<String> { Set(fixIndex.keys) }

    /// The route for "direct to `fix`": the rest of the current route from that fix if it is on it, else the tail of
    /// a STAR (then an approach) that contains it, else just the fix.
    private func directRoute(for ac: Aircraft, to fix: String) -> [RoutePoint] {
        if ac.routeIndex < ac.route.count,
           let i = ac.route[ac.routeIndex...].firstIndex(where: { $0.id == fix }) {
            return Array(ac.route[i...])
        }
        guard let airport else { return [] }
        // A departure goes straight to the fix; STAR and approach tails are for arrivals.
        if ac.departure != nil { return routePoints(for: [Leg(fixId: fix)]) }
        let preferredRunway = ac.approach?.ils.runwayId
        func tail(_ kind: ProcedureKind) -> [RoutePoint]? {
            for proc in airport.procedures where proc.kind == kind && isAvailable(proc) {
                if kind == .approach, let r = preferredRunway, !proc.runways.contains(r) { continue }
                if let i = proc.legs.firstIndex(where: { $0.fixId == fix }) {
                    return routePoints(for: Array(proc.legs[i...]))
                }
            }
            return nil
        }
        return tail(.star) ?? tail(.approach) ?? routePoints(for: [Leg(fixId: fix)])
    }

    // MARK: Spawning

    /// Restarts the traffic generator's random sequence (the app uses this for a fixed or fresh traffic seed).
    public func reseedTraffic(_ seed: UInt64) {
        trafficRng = SeededRNG(seed: seed ^ 0x7AF1_C5EE_D0F1_2B3D)
        rateRng = SeededRNG(seed: seed ^ 0x51C3_D7A0_9E37_79B9)
        ratesStarted = false
    }

    private enum SpawnOutcome { case spawned, blocked, impossible }

    /// Poisson arrivals: each second there is a chance of `arrivalsPerHour / 3600`. An arrival that cannot enter
    /// because the entry is crowded waits in a short queue.
    private func spawnTraffic() {
        let roll = TrafficPlanner.unit(&trafficRng)
        updateTrafficRates()
        guard traffic.enabled, airport != nil else { return }
        if roll < arrivalRatePerHour / 3600 { queuedArrivals += 1 }
        if departureRatePerHour > 0, TrafficPlanner.unit(&trafficRng) < departureRatePerHour / 3600 {
            spawnDeparture()
        }
        guard queuedArrivals > 0 else { return }
        switch spawnArrival() {
        case .spawned: queuedArrivals -= 1
        case .blocked: queuedArrivals = min(queuedArrivals, 4)
        case .impossible: queuedArrivals = 0
        }
    }

    // MARK: Traffic rates

    /// Once a second: a fixed range gives its single value. A range lets the rate glide toward a target inside it; a
    /// new target comes at a random interval set by `traffic.variation`, at most `jump` of the range width away.
    private func updateTrafficRates() {
        let a = traffic.arrivalRange, d = traffic.departureRange
        guard traffic.isVariable else {
            arrivalRatePerHour = a.lowerBound; arrivalTargetPerHour = a.lowerBound
            departureRatePerHour = d.lowerBound; departureTargetPerHour = d.lowerBound
            ratesStarted = false
            return
        }
        let v = traffic.variation
        if !ratesStarted {
            arrivalTargetPerHour = pickRate(in: a, from: nil, jump: 1)
            departureTargetPerHour = pickRate(in: d, from: nil, jump: 1)
            arrivalRatePerHour = arrivalTargetPerHour
            departureRatePerHour = departureTargetPerHour
            nextRateChangeTick = tickCount + rateInterval(v)
            ratesStarted = true
        } else if tickCount >= nextRateChangeTick {
            arrivalTargetPerHour = pickRate(in: a, from: arrivalRatePerHour, jump: v.jump)
            departureTargetPerHour = pickRate(in: d, from: departureRatePerHour, jump: v.jump)
            nextRateChangeTick = tickCount + rateInterval(v)
        }
        // The player may have moved a range: keep everything inside it.
        arrivalTargetPerHour = min(max(arrivalTargetPerHour, a.lowerBound), a.upperBound)
        departureTargetPerHour = min(max(departureTargetPerHour, d.lowerBound), d.upperBound)
        let k = min(1, 3 / v.easeSeconds)
        arrivalRatePerHour = min(max(arrivalRatePerHour + (arrivalTargetPerHour - arrivalRatePerHour) * k, a.lowerBound), a.upperBound)
        departureRatePerHour = min(max(departureRatePerHour + (departureTargetPerHour - departureRatePerHour) * k, d.lowerBound), d.upperBound)
    }

    private func unitRate() -> Double { Double(rateRng.next() >> 11) / Double(1 << 53) }

    private func rateInterval(_ v: TrafficVariation) -> Int {
        Int(v.intervalSeconds.lowerBound + unitRate() * (v.intervalSeconds.upperBound - v.intervalSeconds.lowerBound))
    }

    private func pickRate(in range: ClosedRange<Double>, from current: Double?, jump: Double) -> Double {
        let width = range.upperBound - range.lowerBound
        let u = unitRate()
        guard width > 0 else { return range.lowerBound }
        guard let current else { return range.lowerBound + u * width }
        let lo = max(range.lowerBound, current - jump * width)
        let hi = min(range.upperBound, current + jump * width)
        return lo + u * (hi - lo)
    }

    /// "ARR 22/h ↑  DEP 9/h ↓" for the info panel; empty when traffic is off.
    public var trafficRatesText: String {
        guard traffic.enabled else { return "" }
        func part(_ label: String, _ rate: Double, _ target: Double) -> String {
            let arrow = target - rate > 0.5 ? " ↑" : (target - rate < -0.5 ? " ↓" : "")
            return "\(label) \(Int(rate.rounded()))/h\(arrow)"
        }
        return part("ARR", arrivalRatePerHour, arrivalTargetPerHour) + "  " + part("DEP", departureRatePerHour, departureTargetPerHour)
    }

    private func spawnArrival() -> SpawnOutcome {
        guard let airport else { return .impossible }
        let stars = airport.procedures.filter { $0.kind == .star && $0.legs.count >= 2 && isAvailable($0) }
        let eligible = TrafficPlanner.eligibleTypes(traffic)
        guard !eligible.isEmpty else { return .impossible }
        let type = TrafficPlanner.pick(eligible.map { ($0, $0.share) }, roll: TrafficPlanner.unit(&trafficRng))
        if stars.isEmpty { return spawnFeederArrival(type: type) }
        let first = Int(trafficRng.next() % UInt64(stars.count))
        for k in 0..<stars.count {
            let star = stars[(first + k) % stars.count]
            let points = routePoints(for: star.legs)
            guard points.count == star.legs.count, let entry = areaEntry(points) else { continue }
            // Handover level: the next fix's published altitude if it has one, else 11,000 ft, never above the ceiling.
            let leg = star.legs[entry.next]
            var altitude = leg.altitude.map { Double($0.upperFeet ?? $0.feet) } ?? 11000
            altitude = min(altitude, Double(areaCeilingFt))
            altitude = (altitude / 1000).rounded(.down) * 1000
            altitude = max(Double(max(4000, levelFloorFt)), min(altitude, Double(type.ceilingFt - 1000)))
            let crowded = aircraft.contains { other in
                let dx = other.eastNM - entry.east
                let dy = other.northNM - entry.north
                return (dx * dx + dy * dy).squareRoot() < 7 && abs(other.altitudeFt - altitude) < 3000
            }
            if crowded { continue }
            var speed = Double(leg.maxSpeedKt ?? (altitude > 10000 ? 280 : 250))
            speed = max(Double(type.minSpeedKt + 20), min(speed, Double(type.maxSpeedKt)))
            let callsign = TrafficPlanner.callsign(for: type, country: airport.country, rng: &trafficRng, taken: Set(aircraft.map(\.callsign)))
            if place(callsign: callsign, procedure: star, points: points, east: entry.east, north: entry.north,
                     nextIndex: entry.next, altitudeFt: altitude, speedKt: speed, type: type, requireClear: false) {
                if let ac = aircraft.last {
                    log(.pilot, Phraseology.approachCheckIn(for: ac, facility: approachFacility, altitudeFt: Int(altitude),
                                                            transitionAltitudeFt: transitionAltitudeFt), callsign: callsign)
                }
                return .spawned
            }
        }
        return .blocked
    }

    /// Field elevation used for the vectoring floor: the airport elevation, else the highest runway threshold.
    public var fieldElevationFt: Int {
        airport?.elevationFt ?? airport?.runways.map(\.thresholdElevationFt).max() ?? 0
    }

    /// Lowest level the controller can assign here.
    /// Lowest level once cleared for an approach.
    public var approachLevelFloorFt: Int { CommandLimits.approachFloorFt(fieldElevationFt: fieldElevationFt) }

    public var levelFloorFt: Int { CommandLimits.floorFt(fieldElevationFt: fieldElevationFt) }

    public func spawn(_ aircraft: Aircraft) {
        var aircraft = aircraft
        aircraft.levelFloorFt = levelFloorFt
        aircraft.approachLevelFloorFt = approachLevelFloorFt
        self.aircraft.append(aircraft)
        if aircraft.departure == nil { arrivalStart[aircraft.callsign] = (tickCount, aircraft.eastNM, aircraft.northNM) }
    }

    // MARK: Test spawner (troubleshooting)

    /// East and north (NM) of a runway threshold, or of the airport centre (the scope origin) when `runway` is nil.
    public func referencePoint(runway: String?) -> (east: Double, north: Double) {
        guard let airport, let projection, let runway,
              let r = airport.runways.first(where: { $0.id == runway }) else { return (0, 0) }
        return projection.nm(lat: r.thresholdLat, lon: r.thresholdLon)
    }

    /// Places an arrival-style aircraft exactly as described, for troubleshooting. It has no route or procedure and
    /// flies the given heading, altitude and speed until instructed. A blank or taken callsign becomes TST1, TST2, ...
    /// A nil or unknown type code picks the first catalogue type that can fly IFR. Returns the callsign used.
    @discardableResult
    public func spawnTest(_ spec: TestSpawn) -> String {
        let type = spec.typeCode.flatMap { code in AircraftCatalog.all.first { $0.code == code } }
            ?? AircraftCatalog.all.first { $0.code == "B738" }
            ?? AircraftCatalog.all.first { $0.canFlyIFR }
        let taken = Set(aircraft.map(\.callsign))
        var callsign = (spec.callsign ?? "").trimmingCharacters(in: .whitespaces).uppercased()
        if callsign.isEmpty || taken.contains(callsign) {
            var n = 1
            while taken.contains("TST\(n)") { n += 1 }
            callsign = "TST\(n)"
        }
        let heading = ((spec.headingDeg.truncatingRemainder(dividingBy: 360)) + 360).truncatingRemainder(dividingBy: 360)
        let altitude = max(0, spec.altitudeFt)
        let speed = max(60, spec.speedKt)
        var ac = Aircraft(callsign: callsign, eastNM: spec.eastNM, northNM: spec.northNM,
                          headingDeg: heading, altitudeFt: altitude, speedKt: speed)
        if let type { ac.applyType(type) }
        spawn(ac)
        let summary = "pos \(String(format: "%.1f,%.1f", spec.eastNM, spec.northNM)), hdg \(Int(heading.rounded())), "
            + "alt \(Int(altitude.rounded())), spd \(Int(speed.rounded())), type \(type?.code ?? "?")"
        debug("spawn", callsign, "test aircraft placed: \(summary)")
        log(.system, "Test aircraft \(callsign) placed (\(summary))", callsign: callsign)
        return callsign
    }

    /// Removes an aircraft at once, with its queued commands and history. For the test spawner; returns false if there
    /// is no such aircraft. Nothing is said on the radio about a landing or handoff.
    @discardableResult
    public func removeAircraft(callsign: String) -> Bool {
        guard aircraft.contains(where: { $0.callsign == callsign }) else { return false }
        aircraft.removeAll { $0.callsign == callsign }
        pending.removeAll { $0.callsign == callsign }
        macroRuns[callsign] = nil
        commandHistory[callsign] = nil
        approachTraces[callsign] = nil
        debug("spawn", callsign, "aircraft deleted")
        log(.system, "\(callsign) deleted", callsign: callsign)
        return true
    }

    /// A type and callsign for hand-placed traffic, drawn like generated traffic: the type from the traffic
    /// settings, the airline from the airport's country. Uses the traffic generator's random sequence.
    public func randomArrivalIdentity() -> (callsign: String, type: AircraftType) {
        var pool = TrafficPlanner.eligibleTypes(traffic)
        if pool.isEmpty { pool = AircraftCatalog.all.filter(\.canFlyIFR) }
        let type = TrafficPlanner.pick(pool.map { ($0, $0.share) }, roll: TrafficPlanner.unit(&trafficRng))
        let callsign = TrafficPlanner.callsign(for: type, country: airport?.country, rng: &trafficRng,
                                               taken: Set(aircraft.map(\.callsign)))
        return (callsign, type)
    }


    // MARK: Arrivals without a STAR

    /// Initial approach fixes for airports with no STAR: the first fix of every approach to an open runway, at least
    /// 5 NM from the airport and inside the area. Falls back to all approaches if no runway is open.
    func feederFixes() -> [RoutePoint] {
        guard let airport else { return [] }
        func fixes(_ procs: [Procedure]) -> [RoutePoint] {
            var seen = Set<String>()
            return procs.compactMap { p -> RoutePoint? in
                guard let leg = p.legs.first, let point = routePoints(for: [leg]).first else { return nil }
                let d = hypot(point.eastNM, point.northNM)
                guard d >= 5, d < areaRadiusNM - 3, seen.insert(point.id).inserted else { return nil }
                return RoutePoint(id: point.id, eastNM: point.eastNM, northNM: point.northNM)
            }
        }
        let approaches = airport.procedures.filter { $0.kind == .approach }
        let open = fixes(approaches.filter(isAvailable))
        return open.isEmpty ? fixes(approaches) : open
    }

    /// An arrival at an airport with no STAR is handed in at the edge of the area, within 30 degrees either side of
    /// the line from the airport through an initial approach fix, flying direct to that fix.
    private func spawnFeederArrival(type: AircraftType) -> SpawnOutcome {
        guard let airport else { return .impossible }
        let fixes = feederFixes()
        guard !fixes.isEmpty else { return .impossible }
        var altitude = min(11000.0, Double(areaCeilingFt))
        altitude = (altitude / 1000).rounded(.down) * 1000
        altitude = max(Double(max(4000, levelFloorFt)), min(altitude, Double(type.ceilingFt - 1000)))
        let first = Int(trafficRng.next() % UInt64(fixes.count))
        for k in 0..<fixes.count {
            let fix = fixes[(first + k) % fixes.count]
            let bearing = Aircraft.bearingDeg(eastNM: fix.eastNM, northNM: fix.northNM) + (TrafficPlanner.unit(&trafficRng) * 60 - 30)
            let entry = LocalProjection.offset(bearingDeg: bearing, distanceNM: areaRadiusNM)
            let crowded = aircraft.contains { other in
                hypot(other.eastNM - entry.east, other.northNM - entry.north) < 7 && abs(other.altitudeFt - altitude) < 3000
            }
            if crowded { continue }
            let speed = max(Double(type.minSpeedKt + 20), min(250, Double(type.maxSpeedKt)))
            let callsign = TrafficPlanner.callsign(for: type, country: airport.country, rng: &trafficRng, taken: Set(aircraft.map(\.callsign)))
            let proc = Procedure(id: "DCT \(fix.id)", kind: .star, runways: [], legs: [Leg(fixId: fix.id)])
            if place(callsign: callsign, procedure: proc, points: [fix], east: entry.east, north: entry.north,
                     nextIndex: 0, altitudeFt: altitude, speedKt: speed, type: type, requireClear: false) {
                if let ac = aircraft.last {
                    log(.pilot, Phraseology.approachCheckIn(for: ac, facility: approachFacility, altitudeFt: Int(altitude),
                                                            transitionAltitudeFt: transitionAltitudeFt), callsign: callsign)
                }
                return .spawned
            }
        }
        return .blocked
    }

    /// Start-up traffic at an airport with no STAR: aircraft between 5 NM beyond an initial approach fix and 3 NM inside
    /// the area edge, flying inbound direct to that fix, at 5,000 to 10,000 ft. Same spacing and conflict rules as on
    /// STARs.
    private func placeFeederStartTraffic(target: Int) -> Int {
        let fixes = feederFixes()
        guard !fixes.isEmpty else { return 0 }
        func roll(_ n: Int) -> Int { Int(trafficRng.next() % UInt64(max(n, 1))) }
        var placed = 0
        var attempts = 0
        while placed < target, attempts < target * 10 {
            attempts += 1
            let fix = fixes[roll(fixes.count)]
            let bearing = Aircraft.bearingDeg(eastNM: fix.eastNM, northNM: fix.northNM) + Double(roll(61) - 30)
            // Always beyond the fix, flying inbound: at least 5 NM further out than the fix, at most 3 NM inside the
            // area edge. A fix too close to the edge for that is skipped.
            let fixDistance = hypot(fix.eastNM, fix.northNM)
            let nearest = fixDistance + 5, farthest = areaRadiusNM - 3
            guard farthest > nearest else { continue }
            let distance = nearest + TrafficPlanner.unit(&trafficRng) * (farthest - nearest)
            let start = LocalProjection.offset(bearingDeg: bearing, distanceNM: distance)
            let identity = randomArrivalIdentity()
            let level = max(min(Double(5000 + roll(11) * 500), Double(identity.type.ceilingFt - 1000), Double(areaCeilingFt)), Double(levelFloorFt))
            let speed = max(Double(identity.type.minSpeedKt + 20), min(Double(240 - roll(3) * 10), Double(identity.type.maxSpeedKt)))
            let proc = Procedure(id: "DCT \(fix.id)", kind: .star, runways: [], legs: [Leg(fixId: fix.id)])
            guard place(callsign: identity.callsign, procedure: proc, points: [fix], east: start.east, north: start.north,
                        nextIndex: 0, altitudeFt: level, speedKt: speed, type: identity.type, requireClear: true) else { continue }
            if SeparationMonitor.evaluate(aircraft, wind: wind).isEmpty {
                placed += 1
            } else {
                aircraft.removeLast()
            }
        }
        return placed
    }

    // MARK: Start-up traffic

    /// Arrivals already in the sector when an airport is loaded: a random number of them (2 to 7 by default), on random
    /// STARs at random points, with levels and speeds inside each leg's limits. Each one keeps 10 NM or 2,000 ft from
    /// every other, and one that would give any predicted conflict is taken out again. Uses the traffic generator's
    /// random sequence, so a fixed traffic seed repeats the same start. Returns how many were placed.
    @discardableResult
    public func placeStartTraffic(counts: ClosedRange<Int> = 2...7) -> Int {
        guard let airport else { return 0 }
        let stars = airport.procedures.filter { $0.kind == .star && $0.legs.count >= 4 && isAvailable($0) }
        func roll(_ n: Int) -> Int { Int(trafficRng.next() % UInt64(max(n, 1))) }
        let hasStars = airport.procedures.contains { $0.kind == .star }
        if !hasStars {
            let target = counts.lowerBound + roll(counts.count)
            return placeFeederStartTraffic(target: target)
        }
        guard !stars.isEmpty else { return 0 }
        let target = counts.lowerBound + roll(counts.count)
        var placed = 0
        var attempts = 0
        while placed < target, attempts < target * 10 {
            attempts += 1
            let proc = stars[roll(stars.count)]
            let index = 1 + roll(proc.legs.count - 2) // not the first fix, not the last
            let leg = proc.legs[index]
            if let p = routePoints(for: [leg]).first, hypot(p.eastNM, p.northNM) > areaRadiusNM { continue }
            let identity = randomArrivalIdentity()

            var altitude = 9000 + (roll(6) - 2) * 500
            if let c = leg.altitude {
                switch c.kind {
                case .at: altitude = c.feet
                case .atOrBelow: altitude = c.feet - roll(4) * 500
                case .atOrAbove: altitude = c.feet + roll(4) * 500
                case .between:
                    let upper = max(c.upperFeet ?? c.feet, c.feet)
                    altitude = c.feet + roll((upper - c.feet) / 500 + 1) * 500
                }
            }
            let level = max(min(Double(altitude), Double(identity.type.ceilingFt - 1000), Double(areaCeilingFt)), Double(levelFloorFt))
            let base = leg.maxSpeedKt ?? 240
            let speed = max(Double(identity.type.minSpeedKt + 20), min(Double(base - roll(3) * 10), Double(identity.type.maxSpeedKt)))

            guard spawn(callsign: identity.callsign, procedure: proc.id, startIndex: index, altitudeFt: level,
                        speedKt: speed, type: identity.type, requireClear: true) else { continue }
            if SeparationMonitor.evaluate(aircraft, wind: wind).isEmpty {
                placed += 1
            } else {
                aircraft.removeLast() // would be in conflict at once or within the look-ahead
            }
        }
        return placed
    }

    // MARK: Departures

    /// The level in the flight plan. Placeholder until real flight plans exist: a level that suits the type, picked from
    /// the callsign (not from the random streams, so traffic stays the same as before).
    static func expectedLevel(callsign: String, type: AircraftType, initialFt: Int) -> Int {
        let ceiling = type.ceilingFt - 1000
        let options = [22000, 28000, 34000, 36000].filter { $0 <= ceiling }
        guard !options.isEmpty else { return max(initialFt, (ceiling / 1000) * 1000) }
        let sum = callsign.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return max(initialFt, options[sum % options.count])
    }

    /// SIDs usable from a runway.
    private func sids(for runway: String) -> [Procedure] {
        airport?.procedures.filter { $0.kind == .sid && $0.runways.contains(runway) && $0.legs.count >= 2 } ?? []
    }

    /// A new departure appears at the holding point of an open runway. At most three wait per runway. The wind decides
    /// the runway, not the SIDs: a runway with SIDs gives a random one; a runway without (radar-vector departures are
    /// not coded in the FAA data) means runway heading to the initial level, then the player's vectors.
    private func spawnDeparture() {
        guard let airport, let projection else { return }
        let eligible = TrafficPlanner.eligibleTypes(traffic)
        let runways = airport.runways.filter { openRunways.contains($0.id) }
        guard !eligible.isEmpty, !runways.isEmpty else { return }
        let runway = runways[Int(trafficRng.next() % UInt64(runways.count))]
        let waiting = aircraft.filter { $0.departure?.runway == runway.id && $0.groundPhase == .holdingShort }.count
        guard waiting < 3 else { return }
        let type = TrafficPlanner.pick(eligible.map { ($0, $0.share) }, roll: TrafficPlanner.unit(&trafficRng))
        let options = sids(for: runway.id)
        let sid = options.isEmpty ? nil : options[Int(trafficRng.next() % UInt64(options.count))]
        let points = sid.map { routePoints(for: $0.legs) } ?? []
        if sid != nil, points.isEmpty { return }
        let callsign = TrafficPlanner.callsign(for: type, country: airport.country, rng: &trafficRng,
                                               taken: Set(aircraft.map(\.callsign)))
        let threshold = projection.nm(lat: runway.thresholdLat, lon: runway.thresholdLon)
        let back = LocalProjection.offset(bearingDeg: runway.trueBearingDeg + 180, distanceNM: 0.1 + 0.05 * Double(waiting))
        let elevation = Double(runway.thresholdElevationFt)
        var ac = Aircraft(callsign: callsign, eastNM: threshold.east + back.east, northNM: threshold.north + back.north,
                          headingDeg: runway.trueBearingDeg, altitudeFt: elevation, speedKt: 0)
        ac.applyType(type)
        ac.targetSpeedKt = 0
        ac.route = points
        ac.routeIndex = 0
        ac.procedureId = sid?.id
        let initial = min(type.ceilingFt - 1000, max(3000, Int(((elevation + 2500) / 1000).rounded(.up)) * 1000))
        let rotate = type.approachSpeedKt + ((type.category == .light || type.category == .helicopter) ? 0 : 10)
        let expected = Self.expectedLevel(callsign: callsign, type: type, initialFt: initial)
        let handoffAt = min(expected, max(4000, Int(((elevation + 4000) / 1000).rounded(.up)) * 1000))
        ac.departure = DepartureInfo(runway: runway.id, sid: sid?.id ?? "", initialAltitudeFt: initial,
                                     fieldElevationFt: elevation, rotateSpeedKt: rotate,
                                     expectedLevelFt: expected, handoffAltitudeFt: max(initial, handoffAt))
        ac.departure?.exitFix = sid?.legs.last?.fixId ?? pickExitFix(runway: runway)
        ac.groundPhase = .holdingShort
        ac.levelFloorFt = levelFloorFt
        ac.approachLevelFloorFt = approachLevelFloorFt
        aircraft.append(ac)
        log(.pilot, "Holding point runway \(Phraseology.spokenRunway(runway.id)), ready for departure, \(Phraseology.spokenCallsign(ac))", callsign: ac.callsign)
    }

    /// An exit for a departure without a SID: a random fix between 60% and 130% of the area radius out, not within 45
    /// degrees of the final approach to its own runway (behind the departure, where the arrivals are). Falls back to
    /// the farthest fix. Nil when the airport has no fixes.
    private func pickExitFix(runway: Runway) -> String? {
        let finalBearing = runway.trueBearingDeg + 180
        let all = fixIndex.map { (id: $0.key, east: $0.value.east, north: $0.value.north) }.sorted { $0.id < $1.id }
        let candidates = all.filter { f in
            let d = hypot(f.east, f.north)
            let bearing = Aircraft.bearingDeg(eastNM: f.east, northNM: f.north)
            return d >= areaRadiusNM * 0.6 && d <= areaRadiusNM * 1.3
                && abs(Aircraft.signedTurn(from: finalBearing, to: bearing)) > 45
        }
        if !candidates.isEmpty { return candidates[Int(trafficRng.next() % UInt64(candidates.count))].id }
        return all.max { hypot($0.east, $0.north) < hypot($1.east, $1.north) }?.id
    }

    /// The route an aircraft rejoins on "resume own navigation": its assigned STAR or SID (or the fix of a direct-to-fix
    /// arrival), a departure's exit fix at the end, starting at the far end of the route segment nearest the aircraft.
    /// Empty when it has nothing to resume.
    func resumeRoute(for ac: Aircraft) -> [RoutePoint] {
        var points: [RoutePoint] = []
        if let id = ac.procedureId {
            if let proc = airport?.procedures.first(where: { $0.id == id }) {
                points = routePoints(for: proc.legs)
            } else if id.hasPrefix("DCT ") {
                points = routePoints(for: [Leg(fixId: String(id.dropFirst(4)))])
            }
        }
        if let exit = ac.departure?.exitFix, points.last?.id != exit {
            points += routePoints(for: [Leg(fixId: exit)])
        }
        guard points.count > 1 else { return points }
        // Nearest segment; rejoin at its far end.
        var best = 1
        var bestDistance = Double.infinity
        for k in 0..<(points.count - 1) {
            let a = points[k], b = points[k + 1]
            let dx = b.eastNM - a.eastNM, dy = b.northNM - a.northNM
            let length2 = dx * dx + dy * dy
            let t = length2 > 0 ? max(0, min(1, ((ac.eastNM - a.eastNM) * dx + (ac.northNM - a.northNM) * dy) / length2)) : 0
            let d = hypot(ac.eastNM - (a.eastNM + t * dx), ac.northNM - (a.northNM + t * dy))
            if d < bestDistance { bestDistance = d; best = k + 1 }
        }
        return Array(points[best...])
    }

    /// Position of a fix of the loaded airport, in local NM.
    public func fixPosition(_ id: String) -> (east: Double, north: Double)? { fixIndex[id] }

    /// The other end of the same strip: 28L is 10R.
    public static func oppositeRunway(_ id: String) -> String {
        let digits = String(id.prefix(while: { $0.isNumber }))
        let suffix = String(id.dropFirst(digits.count))
        guard let number = Int(digits) else { return id }
        var other = (number + 18) % 36
        if other == 0 { other = 36 }
        let flipped = suffix == "L" ? "R" : (suffix == "R" ? "L" : suffix)
        return (other < 10 ? "0" : "") + String(other) + flipped
    }

    /// True while a departure is lined up, rolling or just airborne on the runway (either end of the strip).
    public func runwayOccupied(_ runway: String, excluding callsign: String? = nil) -> Bool {
        let ends: Set<String> = [runway, Self.oppositeRunway(runway)]
        return aircraft.contains { ac in
            guard ac.callsign != callsign, let d = ac.departure, ends.contains(d.runway) else { return false }
            if let phase = ac.groundPhase { return phase == .linedUp || phase == .takeoffRoll }
            return ac.altitudeFt < d.fieldElevationFt + 150
        }
    }

    /// Who is using each runway strip right now, keyed by the runway end they are using: a departure lined up, rolling or
    /// just airborne, or an arrival within `landingNM` of the threshold.
    public func runwayUses(landingNM: Double = 1.0) -> [String: RunwayUse] {
        var uses: [String: RunwayUse] = [:]
        for ac in aircraft {
            if let d = ac.departure {
                let busy: Bool
                if let phase = ac.groundPhase { busy = phase == .linedUp || phase == .takeoffRoll }
                else { busy = ac.altitudeFt < d.fieldElevationFt + 150 }
                if busy { uses[d.runway] = .departing(callsign: ac.callsign) }
            } else if let app = ac.approach, !ac.landed {
                let along = app.ils.position(eastNM: ac.eastNM, northNM: ac.northNM).along
                if along > 0, along <= landingNM {
                    if case .landing(_, let nm)? = uses[app.ils.runwayId], nm <= along { continue }
                    if case .departing? = uses[app.ils.runwayId] { continue }
                    uses[app.ils.runwayId] = .landing(callsign: ac.callsign, nm: along)
                }
            }
        }
        return uses
    }

    /// The nearest arrival cleared for this runway (or its other end) that is within `limit` NM of the threshold.
    private func arrivalOnFinal(_ runway: String, withinNM limit: Double) -> (callsign: String, nm: Double)? {
        let ends: Set<String> = [runway, Self.oppositeRunway(runway)]
        var best: (callsign: String, nm: Double)?
        for ac in aircraft {
            guard let app = ac.approach, ends.contains(app.ils.runwayId) else { continue }
            let along = app.ils.position(eastNM: ac.eastNM, northNM: ac.northNM).along
            if along > 0, along <= limit, along < (best?.nm ?? .infinity) { best = (ac.callsign, along) }
        }
        return best
    }

    private func moveToThreshold(_ index: Int) {
        guard let projection, let d = aircraft[index].departure,
              let runway = airport?.runways.first(where: { $0.id == d.runway }) else { return }
        let p = projection.nm(lat: runway.thresholdLat, lon: runway.thresholdLon)
        aircraft[index].eastNM = p.east
        aircraft[index].northNM = p.north
    }

    /// Put an aircraft on a STAR (or any procedure) at the leg `startIndex`, heading for the next fix.
    @discardableResult
    public func spawn(callsign: String, procedure id: String, startIndex: Int = 0,
                      altitudeFt: Double, speedKt: Double, type: AircraftType? = nil,
                      requireClear: Bool = false) -> Bool {
        guard let airport, let proc = airport.procedures.first(where: { $0.id == id }) else { return false }
        let points = routePoints(for: proc.legs)
        guard startIndex >= 0, startIndex < points.count else { return false }
        let start = points[startIndex]
        return place(callsign: callsign, procedure: proc, points: points, east: start.eastNM, north: start.northNM,
                     nextIndex: startIndex + 1, altitudeFt: altitudeFt, speedKt: speedKt, type: type, requireClear: requireClear)
    }

    /// Name the pilots call the player by: "Boston Approach".
    public var approachFacility: String {
        guard let airport else { return "Approach" }
        return "\(airport.city ?? airport.name) Approach"
    }

    /// Where an aircraft flying this route first comes inside the area, and the index of the route point after that.
    /// A route that starts inside begins at its first fix. Nil if the route never comes inside.
    func areaEntry(_ points: [RoutePoint]) -> (next: Int, east: Double, north: Double)? {
        let r = areaRadiusNM
        guard let firstInside = points.firstIndex(where: { hypot($0.eastNM, $0.northNM) <= r }) else { return nil }
        if firstInside == 0 { return (1, points[0].eastNM, points[0].northNM) }
        let a = points[firstInside - 1], b = points[firstInside]
        let dx = b.eastNM - a.eastNM, dy = b.northNM - a.northNM
        let qa = dx * dx + dy * dy
        guard qa > 0 else { return (firstInside, b.eastNM, b.northNM) }
        let qb = 2 * (a.eastNM * dx + a.northNM * dy)
        let qc = a.eastNM * a.eastNM + a.northNM * a.northNM - r * r
        let disc = max(0, qb * qb - 4 * qa * qc)
        let t = min(1, max(0, (-qb - disc.squareRoot()) / (2 * qa)))
        return (firstInside, a.eastNM + t * dx, a.northNM + t * dy)
    }

    /// Puts an aircraft at a position on a procedure's route, heading for the point at `nextIndex`.
    private func place(callsign: String, procedure proc: Procedure, points: [RoutePoint], east: Double, north: Double,
                       nextIndex: Int, altitudeFt: Double, speedKt: Double, type: AircraftType?, requireClear: Bool) -> Bool {
        let start = RoutePoint(id: "", eastNM: east, northNM: north)
        if requireClear {
            // Never create traffic on top of other traffic: 10 NM or 2,000 ft from every existing aircraft.
            for other in aircraft {
                let d = hypot(other.eastNM - start.eastNM, other.northNM - start.northNM)
                if d < 10 && abs(other.altitudeFt - altitudeFt) < 2000 { return false }
            }
        }
        var heading = 0.0
        if nextIndex < points.count {
            let next = points[nextIndex]
            heading = Aircraft.bearingDeg(eastNM: next.eastNM - start.eastNM, northNM: next.northNM - start.northNM)
        }
        var ac = Aircraft(callsign: callsign, eastNM: start.eastNM, northNM: start.northNM,
                          headingDeg: heading, altitudeFt: altitudeFt, speedKt: speedKt)
        if let type { ac.applyType(type) }
        ac.route = points
        ac.procedureId = proc.id
        ac.routeIndex = min(nextIndex, points.count)
        ac.levelFloorFt = levelFloorFt
        ac.approachLevelFloorFt = approachLevelFloorFt
        ac.plannedEvent = planEvent()
        aircraft.append(ac)
        arrivalStart[callsign] = (tickCount, east, north)
        return true
    }

    /// Rolls the random event for a new arrival. Uses its own random sequence, so turning events on or off never
    /// changes the traffic that is generated.
    private func planEvent() -> PlannedEvent? {
        let e = events
        guard e.pilotGoAroundPercent + e.windshearPercent + e.emergencyPercent > 0 else { return nil }
        let roll = TrafficPlanner.unit(&eventRng) * 100
        let detail = TrafficPlanner.unit(&eventRng)
        if roll < e.pilotGoAroundPercent {
            let reasons = ["pilot's decision, not stable", "pilot's decision, no visual references", "pilot's decision, not comfortable with the approach"]
            let reason = reasons[Int(eventRng.next() % UInt64(reasons.count))]
            return .pilotGoAround(reason: reason, triggerNM: 1.0 + detail * 2.0)
        }
        if roll < e.pilotGoAroundPercent + e.windshearPercent {
            return .windshear(triggerNM: 1.5 + detail * 2.5)
        }
        if roll < e.pilotGoAroundPercent + e.windshearPercent + e.emergencyPercent {
            let kinds = EmergencyKind.allCases
            let kind = kinds[Int(eventRng.next() % UInt64(kinds.count))]
            return .emergency(kind: kind, atTick: tickCount + 60 + Int(detail * 240))
        }
        return nil
    }

    /// Carries out an aircraft's planned event when its trigger is reached.
    private func processPlannedEvent(_ i: Int) {
        guard let plan = aircraft[i].plannedEvent else { return }
        let ac = aircraft[i]
        func alongFinal() -> Double? {
            guard let app = ac.approach, app.phase == .glideslope, ac.departure == nil else { return nil }
            return app.ils.position(eastNM: ac.eastNM, northNM: ac.northNM).along
        }
        switch plan {
        case .pilotGoAround(let reason, let nm):
            guard let along = alongFinal(), along > 0, along <= nm else { return }
            aircraft[i].plannedEvent = nil
            aircraft[i].abortApproach(reason: reason)
        case .windshear(let nm):
            guard let along = alongFinal(), along > 0, along <= nm else { return }
            aircraft[i].plannedEvent = nil
            log(.pilot, "Windshear alert, \(Phraseology.spokenCallsign(ac))", callsign: ac.callsign, tag: .windshear)
            aircraft[i].abortApproach(reason: "windshear on final")
        case .emergency(let kind, let tick):
            guard tickCount >= tick, !ac.landed else { return }
            aircraft[i].plannedEvent = nil
            aircraft[i].emergency = kind
            let word = kind.urgencyWord
            log(.pilot, "\(word) \(word) \(word), \(Phraseology.spokenCallsign(ac)), \(kind.phrase), \(kind.request)",
                callsign: ac.callsign, tag: word == "MAYDAY" ? .mayday : .panPan)
            log(.system, "\(ac.callsign) declares an emergency: \(kind.phrase)", callsign: ac.callsign, tag: .emergency)
        }
    }

    // MARK: Commands

    // MARK: Debug log

    /// Turns the debug log on. Off by default; while off nothing is recorded and nothing is formatted.
    public var debugEnabled = false
    /// The latest entries, oldest first (at most `debugLimit`).
    public private(set) var debugLog: [DebugEntry] = []
    public static let debugLimit = 2000
    /// Called with every new entry, for writing to a file.
    public var debugSink: ((DebugEntry) -> Void)?
    private var nextDebugID = 0
    private var approachTraces: [String: ApproachTrace] = [:]
    /// Seconds an aircraft cleared for an approach, with no route left, has been unable to capture it, and which have
    /// already said so on the radio.
    private var interceptStall: [String: Int] = [:]
    private var interceptCalled: Set<String> = []
    /// How long a pilot waits before saying the intercept does not work from here.
    static let interceptStallCallSeconds = 20
    /// Aircraft established on the localiser but too high for the glideslope, and which have already said so.
    private var highStall: [String: Int] = [:]
    private var highCalled: Set<String> = []
    /// How long an aircraft is too high before its pilot says so.
    static let highCallSeconds = 5

    /// A free-text line from the app, for example the start of a session.
    public func debugNote(_ category: String, _ message: String) { debug(category, nil, message) }

    public func clearDebugLog() { debugLog.removeAll() }

    func debug(_ category: String, _ callsign: String?, _ message: @autoclosure () -> String) {
        guard debugEnabled else { return }
        let entry = DebugEntry(id: nextDebugID, tick: tickCount, category: category, callsign: callsign, message: message())
        nextDebugID += 1
        debugLog.append(entry)
        if debugLog.count > Self.debugLimit { debugLog.removeFirst(debugLog.count - Self.debugLimit) }
        debugSink?(entry)
    }

    /// One line of state for an aircraft: where it is, what it has been told, what is still queued.
    private func debugState(_ ac: Aircraft) -> String {
        var parts = ["pos \(String(format: "%.1f", ac.eastNM)),\(String(format: "%.1f", ac.northNM))",
                     "hdg \(Int(ac.headingDeg.rounded()))->\(Int(ac.targetHeadingDeg.rounded()))",
                     "alt \(Int(ac.altitudeFt.rounded()))->\(Int(ac.targetAltitudeFt.rounded()))",
                     "spd \(Int(ac.speedKt.rounded()))->\(Int(ac.targetSpeedKt.rounded()))"]
        if ac.routeIndex < ac.route.count {
            parts.append("route \(ac.route.count - ac.routeIndex) left, next \(ac.route[ac.routeIndex].id)")
        } else {
            parts.append("no route")
        }
        let queued = pending.filter { $0.callsign == ac.callsign }.count
        if queued > 0 { parts.append("\(queued) queued") }
        return parts.joined(separator: ", ")
    }

    /// Logs approach progress for one aircraft: phase changes, why it has not captured yet (when that changes), a state
    /// line every 30 s while intercepting, and a warning if it is still intercepting after two minutes.
    /// A pilot cleared for an approach who cannot capture it from where they are (too far off the course, too close,
    /// too far out) and is not flying a route that will bring them there says so once, rather than flying on silently.
    private func checkInterceptStall(_ ac: Aircraft) {
        guard let app = ac.approach, app.phase == .intercepting, ac.departure == nil,
              !ac.route.indices.contains(ac.routeIndex), let blocker = ac.captureBlocker(),
              let kind = ac.captureBlockKind() else {
            interceptStall[ac.callsign] = nil
            if ac.approach == nil { interceptCalled.remove(ac.callsign) }
            return
        }
        let waited = (interceptStall[ac.callsign] ?? 0) + 1
        interceptStall[ac.callsign] = waited
        guard waited >= Self.interceptStallCallSeconds, !interceptCalled.contains(ac.callsign) else { return }
        interceptCalled.insert(ac.callsign)
        debug("approach", ac.callsign, "pilot reports unable to intercept: \(blocker)")
        let runway = Phraseology.spokenRunway(app.ils.runwayId)
        let along = app.ils.position(eastNM: ac.eastNM, northNM: ac.northNM).along
        let reason: String
        switch kind {
        case .insideGate:
            reason = "we're too close to make the approach, request vectors for another"
        case .tooFar:
            reason = "we're \(Int(along.rounded())) miles out, we'll need a vector"
        case .headingOff, .notClosing, .offCourse:
            let heading = Int(ac.headingDeg.rounded())
            reason = "we're heading \(Phraseology.spokenDigits(Phraseology.pad3(heading == 0 ? 360 : heading))), we'll need a vector"
        }
        log(.pilot, "Unable to intercept the localiser runway \(runway), \(reason), \(Phraseology.spokenCallsign(ac))",
            callsign: ac.callsign, tag: .unable)
    }

    /// An aircraft established on the localiser but more than 300 ft above the glidepath outside the final gate cannot
    /// capture the glideslope, so the pilot asks for a lower level, once.
    private func checkAboveGlidepath(_ ac: Aircraft) {
        guard let app = ac.approach, app.phase == .localiser, ac.departure == nil else {
            highStall[ac.callsign] = nil
            if ac.approach == nil { highCalled.remove(ac.callsign) }
            return
        }
        let p = app.ils.position(eastNM: ac.eastNM, northNM: ac.northNM)
        let beam = app.ils.glidepathAltitudeFt(distanceNM: max(p.along, 0))
        guard p.along > Aircraft.stableGateNM + 0.5, ac.altitudeFt > beam + 300 else {
            highStall[ac.callsign] = nil
            return
        }
        let waited = (highStall[ac.callsign] ?? 0) + 1
        highStall[ac.callsign] = waited
        guard waited >= Self.highCallSeconds, !highCalled.contains(ac.callsign) else { return }
        highCalled.insert(ac.callsign)
        let above = Int((ac.altitudeFt - beam).rounded())
        debug("approach", ac.callsign, "pilot reports above the glidepath: \(above) ft high, \(String(format: "%.1f", p.along)) NM out")
        log(.pilot, "We're above the glidepath, request lower, \(Phraseology.spokenCallsign(ac))", callsign: ac.callsign, tag: .high)
    }

    private func traceApproach(_ ac: Aircraft) {
        guard debugEnabled else { return }
        guard let app = ac.approach else {
            if let trace = approachTraces.removeValue(forKey: ac.callsign) {
                debug("approach", ac.callsign, "approach ended in phase \(trace.phase) after \(tickCount - trace.clearedAtTick) s")
            }
            return
        }
        let blocker = ac.captureBlocker() ?? ""
        guard var trace = approachTraces[ac.callsign] else {
            approachTraces[ac.callsign] = ApproachTrace(phase: app.phase, blocker: blocker, clearedAtTick: tickCount,
                                                        blockerSinceTick: tickCount)
            debug("approach", ac.callsign, "cleared runway \(app.ils.runwayId), phase \(app.phase); \(debugState(ac))")
            return
        }
        if trace.phase != app.phase {
            debug("approach", ac.callsign, "phase \(trace.phase) -> \(app.phase); \(debugState(ac))")
            trace.phase = app.phase
            trace.blocker = ""
            trace.blockerSinceTick = tickCount
        }
        if app.phase == .intercepting, ac.route.indices.contains(ac.routeIndex) {
            // Still flying route fixes towards the final (a STAR or the approach's transition): not capturing yet is
            // expected, so no "not captured" or "STALLED" lines; the wait starts when the route runs out.
            trace.routeTick = tickCount
            trace.blocker = ""
        } else if app.phase == .intercepting {
            // Log when the kind of blocker changes, not on every second its numbers move (heading 96, 99, 102...).
            let kind = blocker.filter { !$0.isNumber && $0 != "." }
            if kind != trace.blocker {
                debug("approach", ac.callsign, blocker.isEmpty ? "can capture now" : "not captured: \(blocker)")
                trace.blocker = kind
                trace.blockerSinceTick = tickCount
            }
            let waited = tickCount - max(trace.clearedAtTick, trace.routeTick ?? trace.clearedAtTick)
            if waited > 0, waited % 30 == 0 {
                let p = app.ils.position(eastNM: ac.eastNM, northNM: ac.northNM)
                debug("state", ac.callsign,
                      "intercepting \(waited) s, along \(String(format: "%.1f", p.along)) cross \(String(format: "%.1f", p.cross)); \(debugState(ac))")
            }
            if waited >= 120, waited % 60 == 0 {
                debug("approach", ac.callsign, "STALLED, still not captured after \(waited) s: \(blocker.isEmpty ? "no blocker found" : blocker)")
            }
        }
        approachTraces[ac.callsign] = trace
    }

    /// Send an instruction. The controller call goes out now; the pilot reads back and starts complying after a delay.
    /// An instruction from the player cancels a macro running on that aircraft: the player has taken over.
    public func issue(_ issued: IssuedCommand) -> IssueResult {
        if macroRuns[issued.callsign] != nil {
            stopMacro(issued.callsign, reason: "manual instruction", flagged: false)
        }
        let result = issueChecked(issued)
        switch result {
        case .accepted(let delay):
            debug("cmd", issued.callsign, "accepted \(issued.command), carried out in \(delay) s")
            instructionCounts[issued.callsign, default: 0] += 1
            lastInstructionTick[issued.callsign] = tickCount
            score.instructions += 1
        case .refused(let reason):
            debug("cmd", issued.callsign, "REFUSED \(issued.command): \(reason)")
            if aircraft.contains(where: { $0.callsign == issued.callsign }) {
                addScore(.refused, callsign: issued.callsign)
            }
        }
        return result
    }

    private func issueChecked(_ issued: IssuedCommand) -> IssueResult {
        var issued = issued
        // "Cleared approach" to a runway without an ILS becomes a visual approach.
        if case .approach(let runway) = issued.command, isVisualRunway(runway) {
            issued.command = .visualApproach(runway: runway)
        }
        guard let ac = aircraft.first(where: { $0.callsign == issued.callsign }) else {
            return .refused("no such aircraft")
        }
        // "p exit": direct to the departure's exit fix.
        if case .direct(let fix) = issued.command, fix == Command.exitFixToken {
            guard let exit = ac.departure?.exitFix else { return .refused("\(ac.callsign) has no exit fix") }
            issued.command = .direct(fix: exit)
        }
        if let reason = issued.command.refusal(for: ac) { return .refused(reason) }
        switch issued.command {
        case .approach(let runway):
            if ilsGeometry(runway: runway) == nil { return .refused("no ILS data for runway \(runway)") }
            if let reason = closedReason(runway: runway) { return refuseClosed(runway, reason, callsign: issued.callsign) }
        case .visualApproach(let runway):
            if approachGeometry(runway: runway) == nil { return .refused("no such runway \(runway)") }
            if let reason = closedReason(runway: runway) { return refuseClosed(runway, reason, callsign: issued.callsign) }
        case .direct(let fix):
            if fixIndex[fix] == nil { return .refused("unknown fix \(fix)") }
        case .resumeNavigation:
            if resumeRoute(for: ac).isEmpty { return .refused("\(ac.callsign) has no route to resume") }
        case .route(let fixes):
            if let bad = fixes.first(where: { fixIndex[$0] == nil }) { return .refused("unknown fix \(bad)") }
        case .cross(let fix, _):
            if fixIndex[fix] == nil { return .refused("unknown fix \(fix)") }
            if !fixWillBeOnRoute(ac, fix) { return .refused("\(fix) is not on the route") }
        case .lineUp, .takeoff:
            guard let runway = ac.departure?.runway else { return .refused("not a departure") }
            if let reason = closedReason(runway: runway) { return refuseClosed(runway, reason, callsign: issued.callsign) }
            if runwayOccupied(runway, excluding: ac.callsign) {
                return refuseRunway("runway \(runway) is occupied", callsign: issued.callsign)
            }
            if case .takeoff = issued.command, let traffic = arrivalOnFinal(runway, withinNM: 4) {
                return refuseRunway("\(traffic.callsign) is on final, \(String(format: "%.1f", traffic.nm)) NM", callsign: issued.callsign)
            }
        case .joinApproach(let procedure, let runway, _):
            guard let proc = airport?.procedures.first(where: { $0.id == procedure && $0.kind == .approach }) else {
                return .refused("unknown approach \(procedure)")
            }
            if approachGeometry(procedure: proc) == nil {
                return .refused("no \(proc.finalApproachType.spoken) data for runway \(runway)")
            }
            if let reason = closedReason(runway: runway) { return refuseClosed(runway, reason, callsign: issued.callsign) }
        default:
            break
        }

        var controllerCall = Phraseology.controllerCall(issued.command, for: ac, transitionAltitudeFt: transitionAltitudeFt)
        if case .takeoff = issued.command { controllerCall = Phraseology.takeoffCall(for: ac, wind: wind, transitionAltitudeFt: transitionAltitudeFt) }
        log(.controller, controllerCall, callsign: issued.callsign,
            code: Command.chainCode(callsign: issued.callsign, commands: [issued.command]))
        var delay = 3 + Int(rng.next() % 4) // 3 to 6 seconds
        // Instructions to one aircraft are carried out in the order they were given.
        if let latest = pending.filter({ $0.callsign == issued.callsign }).map(\.executeAtTick).max() {
            delay = max(delay, latest - tickCount)
        }
        pending.append(PendingCommand(
            executeAtTick: tickCount + delay,
            callsign: issued.callsign,
            command: issued.command,
            readback: Phraseology.readback(issued.command, for: ac, transitionAltitudeFt: transitionAltitudeFt)))
        recordCommand(issued, executeAtTick: tickCount + delay)
        return .accepted(delaySeconds: delay)
    }

    /// True if the fix is on the aircraft's remaining route, or on a route it has been told to fly but not yet started.
    private func fixWillBeOnRoute(_ ac: Aircraft, _ fix: String) -> Bool {
        var latestRoute: [String]?
        for p in pending where p.callsign == ac.callsign {
            switch p.command {
            case .direct(let f): latestRoute = [f]
            case .route(let fs): latestRoute = fs
            case .joinApproach(let procedure, _, _):
                latestRoute = airport?.procedures.first(where: { $0.id == procedure })?.legs.map(\.fixId) ?? []
            default: break
            }
        }
        if let latestRoute { return latestRoute.contains(fix) }
        guard ac.routeIndex < ac.route.count else { return false }
        return ac.route[ac.routeIndex...].contains { $0.id == fix }
    }

    private func refuseRunway(_ text: String, callsign: String? = nil) -> IssueResult {
        log(.system, "Unable: " + text, callsign: callsign, tag: .refused)
        return .refused(text)
    }

    private func refuseClosed(_ runway: String, _ reason: String, callsign: String? = nil) -> IssueResult {
        let text = "runway \(runway) is closed: \(reason)"
        log(.system, "Unable: " + text, callsign: callsign, tag: .refused)
        return .refused(text)
    }

    /// Re-evaluates separation and logs a line the first time a pair becomes predicted or lost.
    private func updateConflicts() {
        conflicts = SeparationMonitor.evaluate(aircraft, wind: wind)
        var current: [String: Conflict.Kind] = [:]
        for c in conflicts {
            current[c.id] = c.kind
            // Two arrivals both handed to the tower are the tower's to separate (on final it works to reduced
            // spacing): still shown on the scope, but no points and not counted as your loss.
            let withTower = isWithTower(c.first) && isWithTower(c.second)
            let before = alertedKinds[c.id]
            if before == nil || (before == .predicted && c.kind == .loss) {
                switch c.kind {
                case .predicted:
                    if withTower { break }
                    log(.system, "CONFLICT \(c.first) / \(c.second): separation lost in \(c.secondsToLoss) s on current tracks", tag: .conflict)
                    addScore(.conflictAlert, detail: "\(c.first) / \(c.second)")
                case .loss:
                    if withTower {
                        log(.system, "\(c.first) / \(c.second) closer than \(Int(SeparationMinima.lateralNM)) NM on final, both with the tower (not counted)")
                        break
                    }
                    lossOfSeparationCount += 1
                    log(.system, "LOSS OF SEPARATION \(c.first) / \(c.second): \(String(format: "%.1f", c.lateralNM)) NM, \(Int(c.verticalFt.rounded())) ft", tag: .lossOfSeparation)
                    score.losses += 1
                    addScore(.lossOfSeparation, detail: "\(c.first) / \(c.second)")
                }
            }
            // A loss that goes on keeps costing points, until both aircraft are with the tower.
            if c.kind == .loss, !withTower {
                let seconds = (lossSeconds[c.id] ?? 0) + 1
                lossSeconds[c.id] = seconds
                if seconds % ScoreRules.lossStepSeconds == 0 {
                    addScore(.lossContinues, detail: "\(c.first) / \(c.second), \(seconds) s")
                }
            }
        }
        lossSeconds = lossSeconds.filter { current[$0.key] == .loss }
        alertedKinds = current
    }

    private func isWithTower(_ callsign: String) -> Bool {
        aircraft.first { $0.callsign == callsign }?.handedToTower ?? false
    }

    /// After a chain was sent: its controller calls to `callsign` since message `id` share one code, shown on the first.
    public func labelChain(callsign: String, afterMessageID id: Int, code: String) {
        let calls = radioLog.indices.filter {
            radioLog[$0].id > id && radioLog[$0].speaker == .controller && radioLog[$0].callsign == callsign
        }
        guard let first = calls.first else { return }
        for i in calls { radioLog[i].code = nil }
        radioLog[first].code = code
    }

    private func log(_ speaker: RadioMessage.Speaker, _ text: String, callsign: String? = nil, tag: RadioTag? = nil,
                     code: String? = nil) {
        radioLog.append(RadioMessage(id: nextMessageID, tick: tickCount, speaker: speaker, text: text, callsign: callsign,
                                     tag: tag, code: code))
        nextMessageID += 1
        if radioLog.count > 200 { radioLog.removeFirst(radioLog.count - 200) }
    }

    private func mix(_ value: UInt64) {
        digest = (digest ^ value) &* 0x0000_0100_0000_01B3
    }

    // MARK: Score

    private func addScore(_ kind: ScoreKind, points: Int? = nil, callsign: String? = nil, detail: String = "") {
        guard score.endTick == nil else { return }
        let value = points ?? ScoreRules.points[kind] ?? 0
        let event = ScoreEvent(id: nextScoreID, tick: tickCount, kind: kind, points: value, callsign: callsign,
                               detail: detail.isEmpty ? (callsign ?? "") : detail)
        nextScoreID += 1
        score.add(event)
        if abs(value) >= ScoreRules.announceAtPoints { log(.system, event.text, callsign: callsign) }
    }

    /// A handoff that the pilot has acted on. A departure scores its handoff and, if cleared to its plan level, a
    /// bonus. An arrival scores its tower handoff and an efficiency bonus from its time since hand-in.
    private func scoreHandoff(_ ac: Aircraft) {
        if let d = ac.departure {
            score.departuresHandled += 1
            addScore(.departureHandoff, callsign: ac.callsign)
            if Int(ac.targetAltitudeFt.rounded()) >= d.expectedLevelFt { addScore(.departureAtPlanLevel, callsign: ac.callsign) }
            if let exit = d.exitFix, let p = fixIndex[exit] {
                let onRoute = ac.routeIndex < ac.route.count && ac.route[ac.routeIndex...].contains { $0.id == exit }
                let toExit = Aircraft.bearingDeg(eastNM: p.east - ac.eastNM, northNM: p.north - ac.northNM)
                let off = abs(Aircraft.signedTurn(from: ac.headingDeg, to: toExit))
                let close = hypot(p.east - ac.eastNM, p.north - ac.northNM) < 3
                if onRoute || close || off <= ScoreRules.exitAlignedDeg {
                    addScore(.exitDirection, callsign: ac.callsign, detail: "\(ac.callsign) towards \(exit)")
                } else if off > ScoreRules.exitWrongWayDeg {
                    addScore(.exitWrongWay, callsign: ac.callsign, detail: "\(ac.callsign), \(Int(off.rounded()))\u{00B0} off \(exit)")
                }
            }
            return
        }
        score.arrivalsHandled += 1
        addScore(.arrivalHandoff, callsign: ac.callsign)
        guard let start = arrivalStart[ac.callsign], let app = ac.approach else { return }
        let distance = hypot(start.east - app.ils.thresholdEastNM, start.north - app.ils.thresholdNorthNM)
        let clean = ScoreRules.cleanSeconds(distanceNM: distance)
        let actual = tickCount - start.tick
        let bonus = ScoreRules.efficiencyBonus(actualSeconds: Double(actual), cleanSeconds: clean)
        score.arrivals.append(ArrivalTiming(callsign: ac.callsign, actualSeconds: actual, cleanSeconds: Int(clean.rounded()),
                                            bonus: bonus, instructions: instructionCounts[ac.callsign] ?? 0))
        if bonus > 0 { addScore(.efficiency, points: bonus, callsign: ac.callsign) }
    }

    /// Time-based rules, the traffic-rate average for the multiplier, and a chart sample each minute.
    private func updateScoreEachSecond() {
        guard score.endTick == nil else { return }
        for ac in aircraft {
            // Departures kept at the holding point.
            if ac.groundPhase == .holdingShort || ac.groundPhase == .linedUp {
                let since = holdingSince[ac.callsign] ?? tickCount
                holdingSince[ac.callsign] = since
                let waited = tickCount - since
                if waited > ScoreRules.departureGraceSeconds, (waited - ScoreRules.departureGraceSeconds) % 60 == 0 {
                    addScore(.departureDelay, callsign: ac.callsign)
                }
            } else {
                holdingSince[ac.callsign] = nil
            }
            // Runway-heading departures left without a vector.
            if ac.onRunwayHeading, !ac.isOnGround, !runwayHeadingPenalised.contains(ac.callsign),
               hypot(ac.eastNM, ac.northNM) > ScoreRules.runwayHeadingLimitNM {
                runwayHeadingPenalised.insert(ac.callsign)
                addScore(.runwayHeadingUnvectored, callsign: ac.callsign)
            }
            // Emergencies with no instruction for two minutes.
            if ac.emergency != nil, !ac.handedToTower, !emergencyChecked.contains(ac.callsign) {
                let since = emergencySince[ac.callsign] ?? tickCount
                emergencySince[ac.callsign] = since
                if tickCount - since >= ScoreRules.emergencyWaitSeconds {
                    emergencyChecked.insert(ac.callsign)
                    if (lastInstructionTick[ac.callsign] ?? -1) < since {
                        addScore(.emergencyIgnored, callsign: ac.callsign)
                    }
                }
            }
        }
        if traffic.enabled {
            rateSeconds += 1
            rateSum += arrivalRatePerHour + departureRatePerHour
        }
        if (tickCount - score.startTick) % 60 == 0 {
            updateScoreMultiplier()
            score.samples.append(ScoreSample(minute: (tickCount - score.startTick) / 60, rawScore: score.raw,
                                             arrivalsPerHour: arrivalRatePerHour, departuresPerHour: departureRatePerHour))
        }
    }

    private func updateScoreMultiplier() {
        score.multiplier = ScoreMultiplier.value(averageRatePerHour: rateSeconds > 0 ? rateSum / Double(rateSeconds) : nil,
                                                 variable: traffic.isVariable, variation: traffic.variation,
                                                 events: events, liveWeather: weatherMode == .live, gusting: wind.isGusting)
    }

    /// Ends the session: no more points, multiplier settled. Returns the card for the debrief.
    @discardableResult
    public func endSession() -> ScoreCard {
        if score.endTick == nil {
            updateScoreMultiplier()
            let minute = (tickCount - score.startTick + 59) / 60
            if score.samples.last?.minute != minute {
                score.samples.append(ScoreSample(minute: minute, rawScore: score.raw,
                                                 arrivalsPerHour: arrivalRatePerHour, departuresPerHour: departureRatePerHour))
            }
            score.endTick = tickCount
        }
        return score
    }

    /// Carries on after a debrief: points count again from now.
    public func resumeSession() {
        score.endTick = nil
    }

    // MARK: Macros

    /// Macros running now, by callsign. At most one per aircraft.
    public private(set) var macroRuns: [String: MacroRun] = [:]
    /// A step that waits longer than this for its trigger stops the macro. Placeholder value.
    public var macroStepTimeoutSeconds = 300

    /// Starts a macro on an aircraft, replacing any macro it was running. A first step without a trigger is sent at
    /// once. Returns why the macro cannot run, or nil.
    @discardableResult
    public func assignMacro(_ macro: CompiledMacro, to callsign: String) -> String? {
        guard let ac = aircraft.first(where: { $0.callsign == callsign }) else { return "no such aircraft" }
        if ac.handedToTower { return "\(callsign) is with the tower" }
        let phase = MacroPhase.of(ac)
        if phase != macro.phase { return "\(macro.name) is a \(macro.phase.label.lowercased()) macro, \(callsign) is \(phase == .arrival ? "an" : "a") \(phase.label.lowercased())" }
        if macro.steps.isEmpty { return "\(macro.name) has no steps" }
        if macroRuns[callsign] != nil { stopMacro(callsign, reason: "replaced by \(macro.name)", flagged: false) }
        macroRuns[callsign] = MacroRun(macro: macro, stepStartTick: tickCount, lastTarget: currentTarget(ac))
        debug("macro", callsign, "started \(macro.name), \(macro.steps.count) steps")
        log(.system, "\(callsign) macro \(macro.name) started", callsign: callsign)
        advanceMacro(callsign)
        return nil
    }

    /// Cancels the aircraft's macro (command bar `mac-`, ring). Returns false if it had none.
    @discardableResult
    public func cancelMacro(callsign: String) -> Bool {
        guard macroRuns[callsign] != nil else { return false }
        stopMacro(callsign, reason: "cancelled", flagged: false)
        return true
    }

    private func stopMacro(_ callsign: String, reason: String, flagged: Bool) {
        guard let run = macroRuns.removeValue(forKey: callsign) else { return }
        debug("macro", callsign, "stopped \(run.macro.name) at step \(run.stepIndex + 1)/\(run.macro.steps.count): \(reason)")
        log(.system, "\(callsign) macro \(run.macro.name) stopped: \(reason)", callsign: callsign, tag: flagged ? .macro : nil)
    }

    private func currentTarget(_ ac: Aircraft) -> String? {
        ac.routeIndex < ac.route.count ? ac.route[ac.routeIndex].id : nil
    }

    private func triggerFired(_ trigger: MacroTrigger?, run: MacroRun, ac: Aircraft) -> Bool {
        guard let trigger else { return true }
        switch trigger {
        case .altitude(let comparison, let feet): return comparison.holds(ac.altitudeFt, feet)
        case .speed(let comparison, let knots): return comparison.holds(ac.speedKt, knots)
        case .atFix(let fix):
            // Passed: the fix was the route target last tick and no longer is, or the aircraft is over it.
            if run.lastTarget == fix && currentTarget(ac) != fix { return true }
            guard let p = fixIndex[fix] else { return false }
            let dx = ac.eastNM - p.east, dy = ac.northNM - p.north
            return (dx * dx + dy * dy).squareRoot() <= 1.0
        }
    }

    /// Sends the next step if its trigger has fired. At most one step per call, so each step is its own transmission.
    private func advanceMacro(_ callsign: String) {
        guard var run = macroRuns[callsign] else { return }
        guard let ac = aircraft.first(where: { $0.callsign == callsign }) else {
            macroRuns[callsign] = nil
            return
        }
        if ac.emergency != nil { return stopMacro(callsign, reason: "emergency", flagged: false) }
        if ac.handedToTower || ac.departure?.handedOff == true { return stopMacro(callsign, reason: "handed off", flagged: false) }
        guard let step = run.nextStep else { macroRuns[callsign] = nil; return }

        if triggerFired(step.trigger, run: run, ac: ac) {
            // Check the whole step before sending any of it, so a step is sent whole or not at all where possible.
            for command in step.commands {
                if let reason = command.refusal(for: ac) {
                    return stopMacro(callsign, reason: "step \(run.stepIndex + 1) refused, \(reason)", flagged: true)
                }
            }
            for command in step.commands {
                if case .refused(let reason) = issueChecked(IssuedCommand(callsign: callsign, command: command)) {
                    debug("cmd", callsign, "REFUSED \(command) (macro \(run.macro.name)): \(reason)")
                    return stopMacro(callsign, reason: "step \(run.stepIndex + 1) refused, \(reason)", flagged: true)
                }
                debug("cmd", callsign, "accepted \(command) (macro \(run.macro.name) step \(run.stepIndex + 1))")
            }
            run.stepIndex += 1
            run.stepStartTick = tickCount
            if run.stepIndex >= run.macro.steps.count {
                macroRuns[callsign] = nil
                debug("macro", callsign, "\(run.macro.name) complete")
                return
            }
        } else if tickCount - run.stepStartTick > macroStepTimeoutSeconds {
            return stopMacro(callsign, reason: "step \(run.stepIndex + 1) waited over \(macroStepTimeoutSeconds / 60) min for \(step.trigger?.tagLabel ?? "its trigger")", flagged: false)
        }
        run.lastTarget = currentTarget(ac)
        macroRuns[callsign] = run
    }

    private func runMacros() {
        for callsign in macroRuns.keys.sorted() { advanceMacro(callsign) }
    }

    // MARK: Tick

    /// Advance one second.
    public func tick() {
        tickCount += 1
        spawnTraffic()
        if tickCount % 60 == 0 { driftWind() }

        // Pilots act on instructions once their delay has passed.
        let due = pending.filter { $0.executeAtTick <= tickCount }
        pending.removeAll { $0.executeAtTick <= tickCount }
        for p in due {
            guard let i = aircraft.firstIndex(where: { $0.callsign == p.callsign }) else {
                debug("cmd", p.callsign, "DROPPED \(p.command): the aircraft is no longer there")
                continue
            }
            switch p.command {
            case .approach(let runway), .visualApproach(let runway):
                guard let ils = approachGeometry(runway: runway) else {
                    debug("cmd", p.callsign, "DROPPED \(p.command): no approach geometry for runway \(runway)")
                    continue
                }
                let onRoute = aircraft[i].routeIndex < aircraft[i].route.count
                let extra = onRoute ? approachLegs(runway: runway, after: aircraft[i].route.last?.id ?? "") : []
                debug("cmd", p.callsign, "approach runway \(runway): on a route \(onRoute), \(extra.count) approach legs added after \(aircraft[i].route.last?.id ?? "-")")
                aircraft[i].clearForApproach(ils, extraRoute: extra)
            case .direct(let fix):
                aircraft[i].setRoute(directRoute(for: aircraft[i], to: fix))
            case .resumeNavigation:
                let route = resumeRoute(for: aircraft[i])
                aircraft[i].setRoute(route)
                if let next = route.first {
                    log(.system, "\(p.callsign) resumes own navigation, next \(next.id)", callsign: p.callsign)
                }
            case .route(let fixes):
                aircraft[i].setRoute(routePoints(for: fixes.map { Leg(fixId: $0) }))
            case .lineUp:
                moveToThreshold(i)
                aircraft[i].apply(p.command)
            case .takeoff:
                if let runway = aircraft[i].departure?.runway, runwayOccupied(runway, excluding: p.callsign) {
                    debug("cmd", p.callsign, "DROPPED take-off clearance: runway \(runway) is occupied")
                    continue
                }
                aircraft[i].apply(p.command)
            case .joinApproach(let procedure, let runway, _):
                guard let proc = airport?.procedures.first(where: { $0.id == procedure }),
                      let ils = approachGeometry(procedure: proc) else {
                    debug("cmd", p.callsign, "DROPPED \(p.command): no geometry for runway \(runway) or no procedure \(procedure)")
                    continue
                }
                aircraft[i].setRoute(routePoints(for: proc.legs))
                aircraft[i].clearForApproach(ils, extraRoute: [])
            default:
                aircraft[i].apply(p.command)
            }
            debug("cmd", p.callsign, "applied \(p.command); \(debugState(aircraft[i]))")
            log(.pilot, p.readback, callsign: p.callsign)
            if case .handoff = p.command {
                log(.system, aircraft[i].departure == nil ? "\(p.callsign) handed to tower, stays on the scope until landed"
                                                          : "\(p.callsign) handed off", callsign: p.callsign)
                scoreHandoff(aircraft[i])
            }
        }

        for i in aircraft.indices {
            aircraft[i].advance(seconds: 1, wind: wind)
            traceApproach(aircraft[i])
            checkInterceptStall(aircraft[i])
            checkAboveGlidepath(aircraft[i])
            processPlannedEvent(i)
            // An arrival close to the threshold goes around if a departure is on the runway.
            if let app = aircraft[i].approach, aircraft[i].departure == nil {
                let along = app.ils.position(eastNM: aircraft[i].eastNM, northNM: aircraft[i].northNM).along
                if along > 0, along <= 1.5, runwayOccupied(app.ils.runwayId) {
                    aircraft[i].abortApproach(reason: "runway \(app.ils.runwayId) occupied")
                }
            }
            for event in aircraft[i].drainEvents() {
                let ac = aircraft[i]
                debug("event", ac.callsign, "\(event)")
                switch event {
                case .established(let runway):
                    log(.system, "\(ac.callsign) established on the localiser, runway \(runway)", callsign: ac.callsign)
                case .landed(let runway):
                    log(.system, "\(ac.callsign) landed runway \(runway)", callsign: ac.callsign)
                    addScore(.landed, callsign: ac.callsign)
                    if ac.emergency != nil { addScore(.emergencyLanded, callsign: ac.callsign) }
                    if macroRuns[ac.callsign] != nil { stopMacro(ac.callsign, reason: "landed", flagged: false) }
                case .routeEnded(let fix, let heading):
                    log(.pilot, Phraseology.routeEnded(fix: fix, headingDeg: heading, for: ac), callsign: ac.callsign)
                    if ac.departure == nil { addScore(.routeEndedNoClearance, callsign: ac.callsign, detail: "\(ac.callsign) at \(fix)") }
                case .crossingUnable(let fix, let feet):
                    log(.pilot, Phraseology.crossingUnable(fix: fix, altitudeFt: feet, for: ac,
                                                           transitionAltitudeFt: transitionAltitudeFt), callsign: ac.callsign, tag: .unable)
                    if macroRuns[ac.callsign] != nil { stopMacro(ac.callsign, reason: "pilot unable to cross \(fix)", flagged: true) }
                case .tookOff(let runway):
                    log(.system, "\(ac.callsign) airborne runway \(runway)", callsign: ac.callsign)
                case .checkedIn(let passing, let climbing, let sid):
                    log(.pilot, Phraseology.departureCheckIn(for: ac, passingFt: passing, climbingToFt: climbing, sid: sid,
                                                             transitionAltitudeFt: transitionAltitudeFt,
                                                             exitFix: ac.departure?.exitFix), callsign: ac.callsign)
                case .wentAround(let reason):
                    log(.pilot, "Going around, \(Phraseology.spokenCallsign(ac))", callsign: ac.callsign, tag: .goAround)
                    log(.system, "\(ac.callsign) go-around: \(reason)", callsign: ac.callsign, tag: .goAround)
                    if ScoreRules.isControllerGoAround(reason: reason) {
                        score.controllerGoArounds += 1
                        addScore(.goAroundCaused, callsign: ac.callsign, detail: "\(ac.callsign), \(reason)")
                    }
                    if macroRuns[ac.callsign] != nil { stopMacro(ac.callsign, reason: "go-around", flagged: false) }
                }
            }
        }
        // Departures that flew out of the area without a handoff.
        for ac in aircraft {
            guard let d = ac.departure, !d.handedOff, !ac.isOnGround,
                  (ac.eastNM * ac.eastNM + ac.northNM * ac.northNM).squareRoot() > areaRadiusNM else { continue }
            missedHandoffs += 1
            log(.system, "\(ac.callsign) left the area without a handoff", callsign: ac.callsign)
            score.missedHandoffs += 1
            addScore(.missedHandoff, callsign: ac.callsign)
        }
        func isGone(_ ac: Aircraft) -> Bool {
            if ac.landed { return true }
            guard let d = ac.departure, !ac.isOnGround else { return false }
            return d.handedOff || (ac.eastNM * ac.eastNM + ac.northNM * ac.northNM).squareRoot() > areaRadiusNM
        }
        for gone in aircraft where isGone(gone) { commandHistory[gone.callsign] = nil }
        aircraft.removeAll(where: isGone)
        runMacros()
        updateConflicts()
        updateScoreEachSecond()

        // Placeholder for the real update order: weather, schedule, ghosts, conflicts.
        mix(rng.next())
        mix(UInt64(lossOfSeparationCount))
        mix(UInt64(bitPattern: Int64((wind.fromDeg * 100).rounded())))
        mix(UInt64(bitPattern: Int64((wind.speedKt * 100).rounded())))
        for a in aircraft {
            mix(UInt64(bitPattern: Int64((a.eastNM * 1000).rounded())))
            mix(UInt64(bitPattern: Int64((a.northNM * 1000).rounded())))
            mix(UInt64(bitPattern: Int64(a.altitudeFt.rounded())))
        }
    }

    public func run(seconds: Int) {
        for _ in 0..<seconds { tick() }
    }

    /// Hash of everything that has happened so far. Two runs with the same seed and inputs must match.
    public var stateDigest: UInt64 { digest }
}
