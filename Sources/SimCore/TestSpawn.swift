import Foundation

/// A hand-placed aircraft for troubleshooting: where it is (east and north of the scope origin, NM), which way it
/// points and how high and fast it is flying. Used by the test spawner panel.
public struct TestSpawn: Equatable {
    public var callsign: String?
    public var typeCode: String?
    public var eastNM: Double
    public var northNM: Double
    public var headingDeg: Double
    public var altitudeFt: Double
    public var speedKt: Double

    public init(callsign: String? = nil, typeCode: String? = nil, eastNM: Double, northNM: Double,
                headingDeg: Double, altitudeFt: Double, speedKt: Double) {
        self.callsign = callsign
        self.typeCode = typeCode
        self.eastNM = eastNM
        self.northNM = northNM
        self.headingDeg = headingDeg
        self.altitudeFt = altitudeFt
        self.speedKt = speedKt
    }
}
