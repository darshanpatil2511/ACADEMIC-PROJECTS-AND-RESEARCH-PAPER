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
