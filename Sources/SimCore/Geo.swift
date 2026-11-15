import Foundation

/// Flat-earth projection around an origin, in nautical miles. Good enough for a terminal area.
public struct LocalProjection {
    public let originLat: Double
    public let originLon: Double

    public init(originLat: Double, originLon: Double) {
        self.originLat = originLat
        self.originLon = originLon
    }

    /// Position relative to the origin: east and north in nautical miles.
    public func nm(lat: Double, lon: Double) -> (east: Double, north: Double) {
        let east = (lon - originLon) * cos(originLat * .pi / 180) * 60
        let north = (lat - originLat) * 60
        return (east, north)
    }

    /// Displacement for a distance along a true bearing: east and north in nautical miles.
    public static func offset(bearingDeg: Double, distanceNM: Double) -> (east: Double, north: Double) {
        let b = bearingDeg * .pi / 180
        return (sin(b) * distanceNM, cos(b) * distanceNM)
    }
}
