import Foundation

/// A fix on an aircraft's active route, already projected into local coordinates.
public struct RoutePoint: Equatable {
    public var id: String
    public var eastNM: Double
    public var northNM: Double
    public var altitude: AltitudeConstraint?
    public var maxSpeedKt: Int?

    public init(id: String, eastNM: Double, northNM: Double,
                altitude: AltitudeConstraint? = nil, maxSpeedKt: Int? = nil) {
        self.id = id
        self.eastNM = eastNM
        self.northNM = northNM
        self.altitude = altitude
        self.maxSpeedKt = maxSpeedKt
    }
}

/// Localiser and glidepath for one runway, in local coordinates.
public struct ILSGeometry: Equatable {
    public var runwayId: String
    public var thresholdEastNM: Double
    public var thresholdNorthNM: Double
    /// True bearing of the landing direction.
    public var courseDeg: Double
    public var glidepathDeg: Double
    public var thresholdElevationFt: Double
    public var thresholdCrossingHeightFt: Double
    /// True for a visual approach to a runway without an ILS: the same geometry built from the runway itself.
    public var isVisual: Bool

    public init(runwayId: String, thresholdEastNM: Double, thresholdNorthNM: Double, courseDeg: Double,
                glidepathDeg: Double, thresholdElevationFt: Double, thresholdCrossingHeightFt: Double,
                isVisual: Bool = false) {
        self.isVisual = isVisual
        self.runwayId = runwayId
        self.thresholdEastNM = thresholdEastNM
        self.thresholdNorthNM = thresholdNorthNM
        self.courseDeg = courseDeg
        self.glidepathDeg = glidepathDeg
        self.thresholdElevationFt = thresholdElevationFt
        self.thresholdCrossingHeightFt = thresholdCrossingHeightFt
    }

    /// `along`: NM before the threshold measured on the final course (positive on the approach side).
    /// `cross`: NM right of the course line, looking along the landing direction.
    public func position(eastNM: Double, northNM: Double) -> (along: Double, cross: Double) {
        let re = eastNM - thresholdEastNM
        let rn = northNM - thresholdNorthNM
        let c = courseDeg * .pi / 180
        let along = -(re * sin(c) + rn * cos(c))
        let cross = re * cos(c) - rn * sin(c)
        return (along, cross)
    }

    /// Glidepath height above sea level at a distance before the threshold.
    public func glidepathAltitudeFt(distanceNM: Double) -> Double {
        thresholdElevationFt + thresholdCrossingHeightFt + tan(glidepathDeg * .pi / 180) * distanceNM * 6076.115
    }
}

public enum ApproachPhase: Equatable {
    case intercepting // cleared, flying heading or route toward the localiser
    case localiser    // established on the localiser, not yet on the glidepath
    case glideslope   // established on both
}

public struct ApproachClearance: Equatable {
    public var ils: ILSGeometry
    public var phase: ApproachPhase
}

/// Where a departing aircraft is before it is airborne.
public enum GroundPhase: Equatable {
    case holdingShort, linedUp, takeoffRoll

    /// Three-letter label for tags and the aircraft list.
    public var label: String {
        switch self {
        case .holdingShort: return "HLD"
        case .linedUp: return "LUP"
        case .takeoffRoll: return "ROL"
        }
    }
}

/// What a departure needs to know: its runway, SID, first level, and where it is in the handover.
public struct DepartureInfo: Equatable {
    public var runway: String
    /// Procedure identifier of the assigned SID.
    public var sid: String
    public var initialAltitudeFt: Int
    public var fieldElevationFt: Double
    /// Speed at which the aircraft leaves the ground.
    public var rotateSpeedKt: Double
    public var checkedIn = false
    public var handedOff = false
    /// Set once the player gives a heading, direct or route. A departure without a SID flies runway heading until then.
    public var vectored = false
    /// Level in the flight plan: where the next sector expects the aircraft to be climbing to.
    public var expectedLevelFt: Int
    /// The aircraft must be at least this high, and cleared at least this high, before it can be handed off.
    public var handoffAltitudeFt: Int

    public init(runway: String, sid: String, initialAltitudeFt: Int, fieldElevationFt: Double, rotateSpeedKt: Double,
                expectedLevelFt: Int? = nil, handoffAltitudeFt: Int? = nil) {
        self.expectedLevelFt = expectedLevelFt ?? 24000
        self.handoffAltitudeFt = handoffAltitudeFt ?? initialAltitudeFt
        self.runway = runway
        self.sid = sid
        self.initialAltitudeFt = initialAltitudeFt
        self.fieldElevationFt = fieldElevationFt
        self.rotateSpeedKt = rotateSpeedKt
    }
}

/// Things the simulation reports to the radio log.
public enum AircraftEvent: Equatable {
    case established(runway: String)
    case landed(runway: String)
    case wentAround(reason: String)
    /// The last fix of a route was passed with no approach clearance; the aircraft holds its heading.
    case routeEnded(fix: String, headingDeg: Int)
    /// A crossing restriction cannot be met at normal rates.
    case crossingUnable(fix: String, altitudeFt: Int)
    /// A departure left the ground.
    case tookOff(runway: String)
    /// A departure passed 1500 ft above the field and calls the departure controller.
    case checkedIn(passingFt: Int, climbingToFt: Int, sid: String)
}
