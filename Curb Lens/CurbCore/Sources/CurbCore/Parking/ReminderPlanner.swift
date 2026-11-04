import Foundation

/// One local notification to schedule for a parked car.
public struct PlannedReminder: Equatable, Sendable {
    public var fireDate: Date
    /// 30, 10 or 0: how long before the move-by time this fires.
    public var minutesBefore: Int
    public var title: String
    public var body: String
}

/// Works out when to remind the user to move their car. Pure: the app turns these into
/// `UNNotificationRequest`s.
public enum ReminderPlanner {
    /// Minutes before the move-by time to notify.
    public static let leadMinutes = [30, 10, 0]

    /// Reminders for a car parked under `rules` with `verdict`, dropping any whose time is not after `now`.
    /// Only `.canPark` with a move-by time produces reminders.
    public static func plan(rules: [ParkingRule], verdict: Verdict, now: Date, calendar: Calendar) -> [PlannedReminder] {
        guard case let .canPark(moveBy?, _) = verdict else { return [] }
        let reason = moveReason(rules: rules, moveBy: moveBy, calendar: calendar)
        return leadMinutes.compactMap { lead in
            let fire = moveBy.addingTimeInterval(TimeInterval(-lead * 60))
            guard fire > now else { return nil }
            let title = lead == 0 ? "Move your car now" : "Move your car in \(lead) min"
            let when = VerdictFormatter.relative(moveBy, now: fire, calendar: calendar)
            return PlannedReminder(fireDate: fire, minutesBefore: lead, title: title,
                                   body: "Move by \(when) · \(reason)")
        }
    }

    /// Why the car has to move at `moveBy`: a prohibiting rule that starts then ("Street cleaning starts
    /// (tow zone)"), otherwise the time limit that runs out ("2-hour limit ends").
    public static func moveReason(rules: [ParkingRule], moveBy: Date, calendar: Calendar) -> String {
        if let starting = rules.first(where: {
            RuleEngine.isProhibiting($0, permitZone: nil) && RuleEngine.isActive($0, at: moveBy, calendar: calendar)
        }) {
            return RuleDescriber.kindLabel(starting.kind) + " starts" + (starting.towZone ? " (tow zone)" : "")
        }
        if let limit = rules.compactMap({ rule -> Int? in
            if case let .timeLimit(minutes) = rule.kind { return minutes }
            return nil
        }).first {
            let label = limit % 60 == 0 ? "\(limit / 60)-hour" : "\(limit)-minute"
            return "\(label) limit ends"
        }
        return "Parking rules change"
    }
}
