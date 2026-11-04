import CurbCore
import Foundation
import SwiftData
import UIKit
import UserNotifications

/// Saving signs and starting/ending parking sessions. Everything stays on the device.
@MainActor
enum ParkingService {
    struct ParkOutcome {
        let session: ParkingSession
        let remindersScheduled: Int
        /// False when reminders were needed but notifications are turned off.
        let notificationsAllowed: Bool
    }

    static func saveSign(_ reading: SignReading, location: LocationFix?, in context: ModelContext, now: Date) -> SavedSign {
        let sign = SavedSign(createdAt: now, rules: reading.parse.rules,
                             panelText: reading.panels.joined(separator: "\n"),
                             photoJPEG: Thumbnail.jpeg(from: reading.ocrImage), location: location)
        context.insert(sign)
        try? context.save()
        return sign
    }

    /// Starts a session at `sign` if parking is allowed at `now`. Ends any other active session first.
    /// `scheduleReminders: false` skips the notification permission prompt (debug screenshots only).
    static func park(at sign: SavedSign, location: LocationFix?, in context: ModelContext, now: Date,
                     scheduleReminders: Bool = true) async -> ParkOutcome? {
        let rules = sign.rules
        let verdict = RuleEngine.evaluate(rules: rules, arrival: now, calendar: .boston, permitZone: nil)
        guard verdict.isCanPark else { return nil }

        let active = (try? context.fetch(FetchDescriptor<ParkingSession>(predicate: #Predicate { $0.endedAt == nil }))) ?? []
        active.forEach { end($0, in: context, now: now) }

        let session = ParkingSession(startedAt: now, moveBy: verdict.moveBy, sign: sign, location: location ?? sign.fix)
        context.insert(session)

        let plan = ReminderPlanner.plan(rules: rules, verdict: verdict, now: now, calendar: .boston)
        var allowed = true
        if !plan.isEmpty, scheduleReminders {
            allowed = await ReminderScheduler.requestPermission()
            if allowed { session.notificationIDs = await ReminderScheduler.schedule(plan, sessionID: session.id) }
        }
        try? context.save()
        return ParkOutcome(session: session, remindersScheduled: session.notificationIDs.count, notificationsAllowed: allowed)
    }

    static func end(_ session: ParkingSession, in context: ModelContext, now: Date) {
        ReminderScheduler.cancel(session.notificationIDs)
        session.endedAt = now
        try? context.save()
    }

    static func delete(_ sign: SavedSign, in context: ModelContext, now: Date) {
        for session in sign.sessions where session.endedAt == nil { end(session, in: context, now: now) }
        context.delete(sign)
        try? context.save()
    }
}

/// Local notifications for move-by reminders.
enum ReminderScheduler {
    static func requestPermission() async -> Bool {
        let center = UNUserNotificationCenter.current()
        switch await center.notificationSettings().authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            return false
        default:
            return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        }
    }

    /// Returns the identifiers of the requests that were added.
    static func schedule(_ plan: [PlannedReminder], sessionID: UUID) async -> [String] {
        let center = UNUserNotificationCenter.current()
        var ids: [String] = []
        for reminder in plan {
            let interval = reminder.fireDate.timeIntervalSinceNow
            guard interval > 0 else { continue }
            let content = UNMutableNotificationContent()
            content.title = reminder.title
            content.body = reminder.body
            content.sound = .default
            let id = "parking-\(sessionID.uuidString)-\(reminder.minutesBefore)"
            let request = UNNotificationRequest(identifier: id, content: content,
                                                trigger: UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false))
            do {
                try await center.add(request)
                ids.append(id)
            } catch {
                continue
            }
        }
        return ids
    }

    static func cancel(_ ids: [String]) {
        guard !ids.isEmpty else { return }
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ids)
        center.removeDeliveredNotifications(withIdentifiers: ids)
    }
}

/// Shows reminders as banners even while CurbLens is open.
final class ForegroundNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }
}

/// Small JPEG of the sign crop for the saved-signs list (keeps the store small).
enum Thumbnail {
    static func jpeg(from image: CGImage, maxSide: CGFloat = 800) -> Data? {
        let width = CGFloat(image.width), height = CGFloat(image.height)
        let scale = min(1, maxSide / max(width, height))
        let size = CGSize(width: (width * scale).rounded(), height: (height * scale).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            UIImage(cgImage: image).draw(in: CGRect(origin: .zero, size: size))
        }
        return resized.jpegData(compressionQuality: 0.7)
    }
}
