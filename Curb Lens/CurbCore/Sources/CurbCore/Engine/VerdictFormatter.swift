import Foundation

/// What the result screen shows for a verdict. Pure text, so it is unit-testable and UI-free.
public struct VerdictPresentation: Equatable, Sendable {
    public enum Tone: Sendable { case go, stop, unknown }

    public var tone: Tone
    /// "You can park", "No parking now", "Couldn't read this sign"
    public var title: String
    /// "Move by tomorrow at 9:00 AM", "Allowed from today at 12:00 PM"
    public var detail: String
    public var notes: [String]
}

/// Turns verdicts and dates into short, plain-English text using relative day words.
public enum VerdictFormatter {
    public static func present(_ verdict: Verdict, now: Date, calendar: Calendar) -> VerdictPresentation {
        switch verdict {
        case let .canPark(moveBy, notes):
            let detail = moveBy.map { "Move by \(relative($0, now: now, calendar: calendar))" }
                ?? "No time limit in the next 8 days"
            return VerdictPresentation(tone: .go, title: "You can park", detail: detail, notes: notes)
        case let .cannotPark(reason, allowedFrom):
            let when = allowedFrom.map { "Allowed from \(relative($0, now: now, calendar: calendar))" }
                ?? "Not allowed in the next 8 days"
            return VerdictPresentation(tone: .stop, title: "No parking now", detail: "\(when) · \(reason)", notes: [])
        case let .unreadable(reason):
            return VerdictPresentation(tone: .unknown, title: "Couldn't read this sign", detail: reason, notes: [])
        }
    }

    /// "today at 12:00 PM", "tomorrow at 9:00 AM", "Mon at 9:00 AM", "Tue Nov 24 at 8:00 AM".
    public static func relative(_ date: Date, now: Date, calendar: Calendar) -> String {
        let time = format(date, "h:mm a", calendar: calendar)
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now),
                                           to: calendar.startOfDay(for: date)).day ?? 0
        switch days {
        case 0: return "today at \(time)"
        case 1: return "tomorrow at \(time)"
        case 2...6: return "\(format(date, "EEE", calendar: calendar)) at \(time)"
        default: return "\(format(date, "EEE MMM d", calendar: calendar)) at \(time)"
        }
    }

    private static func format(_ date: Date, _ pattern: String, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = pattern
        return formatter.string(from: date)
    }
}

extension RuleEngine {
    /// Whether to show a "Tow zone" badge: a tow-zone rule is in force now, or is the one that
    /// starts at the move-by time.
    public static func towZoneApplies(rules: [ParkingRule], verdict: Verdict, at now: Date,
                                      calendar: Calendar) -> Bool {
        let moments = [now] + [verdict.moveBy].compactMap { $0 }
        return rules.contains { rule in
            rule.towZone && moments.contains { isActive(rule, at: $0, calendar: calendar) }
        }
    }
}
