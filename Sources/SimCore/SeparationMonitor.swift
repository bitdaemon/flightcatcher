import Foundation

/// Radar separation minima used by the monitor. Placeholders until the real minima are coded.
public enum SeparationMinima {
    public static let lateralNM = 3.0
    public static let verticalFt = 1000.0
    /// How far ahead the straight-line prediction looks.
    public static let lookaheadSeconds = 120
    /// Parallel approaches, both aircraft established on approaches to different, parallel runways (courses within
    /// 5 degrees). Approximations of the FAA rules, not the full set:
    /// runways at least this far apart (4,300 ft) are flown as independent approaches: no minimum between the pair.
    public static let independentParallelSpacingNM = 4300.0 / 6076.0
    /// closer runways are dependent approaches: this diagonal distance instead of the normal lateral minimum.
    public static let dependentParallelDiagonalNM = 1.5
    public static let parallelCourseToleranceDeg = 5.0
}

public struct Conflict: Equatable, Identifiable {
    public enum Kind: Int, Equatable { case predicted = 0, loss = 1 }

    /// Callsigns in alphabetical order, so a pair has one identity.
    public var first: String
    public var second: String
    public var kind: Kind
    /// Seconds until separation is lost (0 when already lost).
    public var secondsToLoss: Int
    /// Current separation.
    public var lateralNM: Double
    public var verticalFt: Double

    public var id: String { first + "/" + second }

    public init(first: String, second: String, kind: Kind, secondsToLoss: Int, lateralNM: Double, verticalFt: Double) {
        self.first = first
        self.second = second
        self.kind = kind
        self.secondsToLoss = secondsToLoss
        self.lateralNM = lateralNM
        self.verticalFt = verticalFt
    }
}

/// Pure separation check. Separation is lost when two aircraft are closer than the lateral minimum AND the
/// vertical minimum at the same time. The prediction flies each aircraft straight on its current heading and speed,
/// with altitude moving toward its target at the climb or descent rate, so it ignores turns that are still to come.
public enum SeparationMonitor {
    public static func evaluate(_ aircraft: [Aircraft],
                                wind: Wind = .calm,
                                lateralNM: Double = SeparationMinima.lateralNM,
                                verticalFt: Double = SeparationMinima.verticalFt,
                                lookaheadSeconds: Int = SeparationMinima.lookaheadSeconds) -> [Conflict] {
        var result: [Conflict] = []
        let live = aircraft.filter { !$0.landed && !$0.isOnGround }
        for i in live.indices {
            for j in live.indices where j > i {
                let (a, b) = live[i].callsign < live[j].callsign ? (live[i], live[j]) : (live[j], live[i])
                if let conflict = check(a, b, wind: wind, lateralNM: lateralNM, verticalFt: verticalFt, lookahead: lookaheadSeconds) {
                    result.append(conflict)
                }
            }
        }
        return result.sorted {
            if $0.kind != $1.kind { return $0.kind.rawValue > $1.kind.rawValue }
            if $0.secondsToLoss != $1.secondsToLoss { return $0.secondsToLoss < $1.secondsToLoss }
            return $0.id < $1.id
        }
    }

    /// The lateral minimum for a pair established on parallel approaches: 0 for independent runways, the dependent
    /// diagonal for closer ones, nil when the normal minima apply.
    static func parallelApproachMinimum(_ a: Aircraft, _ b: Aircraft) -> Double? {
        guard let x = a.approach, let y = b.approach, x.phase != .intercepting, y.phase != .intercepting,
              x.ils.runwayId != y.ils.runwayId else { return nil }
        var diff = abs(x.ils.courseDeg - y.ils.courseDeg).truncatingRemainder(dividingBy: 360)
        if diff > 180 { diff = 360 - diff }
        guard diff <= SeparationMinima.parallelCourseToleranceDeg else { return nil }
        let spacing = abs(x.ils.position(eastNM: y.ils.thresholdEastNM, northNM: y.ils.thresholdNorthNM).cross)
        return spacing >= SeparationMinima.independentParallelSpacingNM ? 0 : SeparationMinima.dependentParallelDiagonalNM
    }

    private static func check(_ a: Aircraft, _ b: Aircraft, wind: Wind, lateralNM: Double, verticalFt: Double,
                              lookahead: Int) -> Conflict? {
        var lateralNM = lateralNM
        if let parallel = parallelApproachMinimum(a, b) {
            if parallel == 0 { return nil }
            lateralNM = parallel
        }
        let now = separation(a, b, wind: wind, after: 0)
        if now.lateral < lateralNM && now.vertical < verticalFt {
            return Conflict(first: a.callsign, second: b.callsign, kind: .loss, secondsToLoss: 0,
                            lateralNM: now.lateral, verticalFt: now.vertical)
        }
        guard lookahead > 0 else { return nil }
        for t in 1...lookahead {
            let s = separation(a, b, wind: wind, after: Double(t))
            if s.lateral < lateralNM && s.vertical < verticalFt {
                return Conflict(first: a.callsign, second: b.callsign, kind: .predicted, secondsToLoss: t,
                                lateralNM: now.lateral, verticalFt: now.vertical)
            }
        }
        return nil
    }

    private static func separation(_ a: Aircraft, _ b: Aircraft, wind: Wind, after t: Double) -> (lateral: Double, vertical: Double) {
        let pa = position(a, wind: wind, after: t)
        let pb = position(b, wind: wind, after: t)
        let lateral = ((pa.east - pb.east) * (pa.east - pb.east) + (pa.north - pb.north) * (pa.north - pb.north)).squareRoot()
        return (lateral, abs(pa.altitude - pb.altitude))
    }

    /// Where an aircraft will be after `t` seconds. An aircraft with route fixes ahead (and not established on an
    /// approach) is moved along them, turning at each fix, then straight on along the last leg; others fly straight
    /// on their heading. Turns are taken as instant. Altitude moves toward the target at the climb or descent rate.
    static func position(_ ac: Aircraft, wind: Wind, after t: Double) -> (east: Double, north: Double, altitude: Double) {
        let delta = ac.targetAltitudeFt - ac.altitudeFt
        let rate = (delta >= 0 ? ac.climbRateFpm : ac.descentRateFpm) / 60 * t
        let altitude = ac.altitudeFt + (delta >= 0 ? min(rate, delta) : max(-rate, delta))
        let w = wind.vectorKt(atAltitudeFt: ac.altitudeFt)
        var east = ac.eastNM, north = ac.northNM
        var heading = ac.headingDeg
        var left = ac.speedKt / 3600 * t
        let followsRoute = ac.routeIndex < ac.route.count && (ac.approach == nil || ac.approach?.phase == .intercepting)
        if followsRoute, left > 0 {
            for point in ac.route[ac.routeIndex...] {
                let dx = point.eastNM - east, dy = point.northNM - north
                let d = (dx * dx + dy * dy).squareRoot()
                guard d > 1e-6 else { continue }
                heading = atan2(dx, dy) * 180 / .pi
                if d >= left {
                    east += dx / d * left
                    north += dy / d * left
                    left = 0
                    break
                }
                east = point.eastNM
                north = point.northNM
                left -= d
            }
        }
        if left > 0 {
            let rad = heading * .pi / 180
            east += sin(rad) * left
            north += cos(rad) * left
        }
        return (east + w.east / 3600 * t, north + w.north / 3600 * t, altitude)
    }
}
