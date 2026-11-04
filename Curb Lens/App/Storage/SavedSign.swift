import CoreLocation
import CurbCore
import Foundation
import SwiftData

/// A sign the user saved: what it says, where it is, which way the phone faced, and a small photo.
@Model
final class SavedSign {
    var id: UUID
    var createdAt: Date
    var latitude: Double?
    var longitude: Double?
    var accuracyMeters: Double?
    /// Compass heading (degrees, 0 = north) the camera faced when the sign was saved.
    var headingDegrees: Double?
    /// `[ParkingRule]` as JSON (`RuleArchive`).
    var rulesData: Data
    var panelText: String
    @Attribute(.externalStorage) var photoJPEG: Data?

    @Relationship(deleteRule: .nullify, inverse: \ParkingSession.sign)
    var sessions: [ParkingSession] = []

    init(createdAt: Date, rules: [ParkingRule], panelText: String, photoJPEG: Data?, location: LocationFix?) {
        self.id = UUID()
        self.createdAt = createdAt
        self.rulesData = (try? RuleArchive.encode(rules)) ?? Data()
        self.panelText = panelText
        self.photoJPEG = photoJPEG
        self.latitude = location?.latitude
        self.longitude = location?.longitude
        self.accuracyMeters = location?.accuracyMeters
        self.headingDegrees = location?.headingDegrees
    }

    var rules: [ParkingRule] { (try? RuleArchive.decode(rulesData)) ?? [] }

    /// First rule in plain English, e.g. "2-hour parking 8:00 AM–6:00 PM Mon–Fri".
    var title: String { rules.first.map(RuleDescriber.describe) ?? "Unreadable sign" }

    var coordinate: CLLocationCoordinate2D? {
        guard let latitude, let longitude else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var fix: LocationFix? {
        guard let latitude, let longitude else { return nil }
        return LocationFix(latitude: latitude, longitude: longitude, accuracyMeters: accuracyMeters ?? 0,
                           headingDegrees: headingDegrees)
    }

    func verdict(at date: Date) -> Verdict {
        RuleEngine.evaluate(rules: rules, arrival: date, calendar: .boston, permitZone: nil)
    }
}

/// "I parked here": when, where, the move-by time, and the reminders scheduled for it.
@Model
final class ParkingSession {
    var id: UUID
    var startedAt: Date
    var moveBy: Date?
    var latitude: Double?
    var longitude: Double?
    var notificationIDs: [String]
    /// Set when the user taps "I've left" (or parks somewhere else).
    var endedAt: Date?
    var sign: SavedSign?

    init(startedAt: Date, moveBy: Date?, sign: SavedSign, location: LocationFix?) {
        self.id = UUID()
        self.startedAt = startedAt
        self.moveBy = moveBy
        self.sign = sign
        self.latitude = location?.latitude
        self.longitude = location?.longitude
        self.notificationIDs = []
    }

    var coordinate: CLLocationCoordinate2D? {
        guard let latitude, let longitude else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}
