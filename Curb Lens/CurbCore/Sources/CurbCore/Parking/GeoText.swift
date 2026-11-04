import Foundation

/// Compass and distance helpers for saved signs. Plain doubles so CurbCore needs no CoreLocation.
public enum GeoText {
    private static let points = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]

    /// 8-point compass name for a heading in degrees (0 = north, clockwise). Any value is normalized.
    public static func cardinal(_ degrees: Double) -> String {
        let normalized = (degrees.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
        let index = Int((normalized / 45).rounded()) % points.count
        return points[index]
    }

    /// Great-circle (haversine) distance in meters.
    public static func distanceMeters(lat1: Double, lon1: Double, lat2: Double, lon2: Double) -> Double {
        let earthRadius = 6_371_000.0
        let dLat = (lat2 - lat1) * .pi / 180
        let dLon = (lon2 - lon1) * .pi / 180
        let a = sin(dLat / 2) * sin(dLat / 2)
            + cos(lat1 * .pi / 180) * cos(lat2 * .pi / 180) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * earthRadius * asin(min(1, a.squareRoot()))
    }

    /// How far the back camera points above (+) or below (−) the horizon, in degrees, from a CoreMotion
    /// gravity vector in device coordinates. The back camera looks along the device's −z axis, so its
    /// "up" component is gravity.z (normalized): upright portrait = 0°, flat screen-up = −90°.
    public static func cameraPitchDegrees(gravityX: Double, gravityY: Double, gravityZ: Double) -> Double {
        let length = (gravityX * gravityX + gravityY * gravityY + gravityZ * gravityZ).squareRoot()
        guard length > 0 else { return 0 }
        return asin(max(-1, min(1, gravityZ / length))) * 180 / .pi
    }

    /// "camera 12° up", "camera 8° down", "camera level" (within 2°).
    public static func pitchLabel(degrees: Double) -> String {
        let rounded = Int(degrees.magnitude.rounded())
        if rounded < 2 { return "camera level" }
        return "camera \(rounded)° \(degrees > 0 ? "up" : "down")"
    }

    /// "12 m", "1.4 km"
    public static func distanceLabel(meters: Double) -> String {
        if meters < 1_000 { return "\(Int(meters.rounded())) m" }
        return String(format: "%.1f km", (meters / 100).rounded(.down) / 10)
    }
}

/// How a saved sign's rules are stored (SwiftData keeps them as one JSON blob).
public enum RuleArchive {
    public static func encode(_ rules: [ParkingRule]) throws -> Data {
        try JSONEncoder().encode(rules)
    }

    public static func decode(_ data: Data) throws -> [ParkingRule] {
        try JSONDecoder().decode([ParkingRule].self, from: data)
    }
}
