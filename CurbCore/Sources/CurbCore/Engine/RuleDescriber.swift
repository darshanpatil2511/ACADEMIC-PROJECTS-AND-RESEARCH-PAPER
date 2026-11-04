import Foundation

/// Plain-English descriptions of rules, for verdict reasons and the result screen.
public enum RuleDescriber {
    /// e.g. "Street cleaning 8:00 AM–12:00 PM, 2nd & 4th Tue, Apr 1–Nov 30 (tow zone)"
    public static func describe(_ rule: ParkingRule) -> String {
        var parts = [kindLabel(rule.kind)]
        parts.append(windowLabel(rule.window))
        if let days = dayLabel(rule.days) { parts.append(days) }
        var text = parts.joined(separator: " ")
        if let season = rule.season {
            text += ", " + seasonLabel(season)
        }
        if rule.towZone { text += " (tow zone)" }
        return text
    }

    /// Reason shown when this rule blocks parking right now.
    public static func reason(for rule: ParkingRule) -> String {
        describe(rule)
    }

    static func kindLabel(_ kind: RestrictionKind) -> String {
        switch kind {
        case .noParking: return "No parking"
        case .noStopping: return "No stopping"
        case .streetCleaning: return "Street cleaning"
        case .loadingZone: return "Loading zone"
        case let .timeLimit(minutes):
            if minutes % 60 == 0 {
                let hours = minutes / 60
                return "\(hours)-hour parking"
            }
            return "\(minutes)-minute parking"
        case let .permitOnly(zone):
            if let zone { return "Resident permit (\(zone)) only" }
            return "Resident permit only"
        case .snowEmergency: return "Snow emergency route"
        }
    }

    static func windowLabel(_ window: TimeWindow?) -> String {
        guard let window else { return "any time" }
        return "\(timeLabel(window.start))–\(timeLabel(window.end))"
    }

    static func timeLabel(_ time: TimeOfDay) -> String {
        let hour12 = time.hour % 12 == 0 ? 12 : time.hour % 12
        let suffix = time.hour < 12 ? "AM" : "PM"
        return String(format: "%d:%02d %@", hour12, time.minute, suffix)
    }

    static func dayLabel(_ days: DayRule) -> String? {
        switch days {
        case .everyDay:
            return nil
        case let .days(set):
            let sorted = set.sorted()
            if sorted == [.mon, .tue, .wed, .thu, .fri] { return "Mon–Fri" }
            if sorted == [.mon, .tue, .wed, .thu, .fri, .sat] { return "Mon–Sat" }
            if sorted.count == 6, let missing = Weekday.allCases.first(where: { !set.contains($0) }) {
                return "except \(missing.shortName)"
            }
            return sorted.map(\.shortName).joined(separator: ", ")
        case let .nthWeekday(ordinals, weekday):
            let ords = ordinals.sorted().map(ordinalLabel).joined(separator: " & ")
            return "\(ords) \(weekday.shortName)"
        }
    }

    static func ordinalLabel(_ n: Int) -> String {
        switch n {
        case 1: return "1st"
        case 2: return "2nd"
        case 3: return "3rd"
        default: return "\(n)th"
        }
    }

    static func seasonLabel(_ s: SeasonalRange) -> String {
        let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        func label(_ m: Int, _ d: Int) -> String {
            let name = (1...12).contains(m) ? months[m - 1] : "?"
            return "\(name) \(d)"
        }
        return "\(label(s.startMonth, s.startDay))–\(label(s.endMonth, s.endDay))"
    }
}
