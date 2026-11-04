import Foundation

/// Day of the week. Raw values match `Calendar` `.weekday` (Sunday = 1).
public enum Weekday: Int, Codable, CaseIterable, Sendable, Comparable {
    case sun = 1, mon, tue, wed, thu, fri, sat

    public static func < (lhs: Weekday, rhs: Weekday) -> Bool { lhs.rawValue < rhs.rawValue }

    /// Short English label, e.g. "Tue".
    public var shortName: String {
        switch self {
        case .sun: return "Sun"
        case .mon: return "Mon"
        case .tue: return "Tue"
        case .wed: return "Wed"
        case .thu: return "Thu"
        case .fri: return "Fri"
        case .sat: return "Sat"
        }
    }
}

/// A wall-clock time, stored as minutes since midnight (0...1439).
public struct TimeOfDay: Codable, Hashable, Comparable, Sendable {
    public var minutes: Int

    public init(minutes: Int) {
        self.minutes = ((minutes % 1440) + 1440) % 1440
    }

    public init(hour: Int, minute: Int = 0) {
        self.init(minutes: hour * 60 + minute)
    }

    public var hour: Int { minutes / 60 }
    public var minute: Int { minutes % 60 }

    public static func < (lhs: TimeOfDay, rhs: TimeOfDay) -> Bool { lhs.minutes < rhs.minutes }
}

/// A daily time range. The end is exclusive: 8AM–12PM is active 8:00 through 11:59.
/// When `end <= start` the window runs overnight into the next day.
public struct TimeWindow: Codable, Hashable, Sendable {
    public var start: TimeOfDay
    public var end: TimeOfDay

    public init(start: TimeOfDay, end: TimeOfDay) {
        self.start = start
        self.end = end
    }

    public var isOvernight: Bool { end <= start }
}

/// Which days a rule applies to.
public enum DayRule: Codable, Hashable, Sendable {
    /// No day restriction on the sign.
    case everyDay
    /// e.g. MON-FRI, or EXCEPT SUNDAY (stored as the six other days).
    case days(Set<Weekday>)
    /// e.g. 2ND & 4TH TUE. Ordinals are 1...5, matching `Calendar` `.weekdayOrdinal`.
    case nthWeekday(ordinals: Set<Int>, weekday: Weekday)
}

/// A date range within the year, inclusive at both ends. May wrap the year (DEC 1 - MAR 31).
public struct SeasonalRange: Codable, Hashable, Sendable {
    public var startMonth: Int, startDay: Int
    public var endMonth: Int, endDay: Int

    public init(startMonth: Int, startDay: Int, endMonth: Int, endDay: Int) {
        self.startMonth = startMonth
        self.startDay = startDay
        self.endMonth = endMonth
        self.endDay = endDay
    }

    /// True when the given month/day falls inside the range.
    public func contains(month: Int, day: Int) -> Bool {
        let value = month * 100 + day
        let start = startMonth * 100 + startDay
        let end = endMonth * 100 + endDay
        if start <= end {
            return value >= start && value <= end
        }
        return value >= start || value <= end   // wraps the new year
    }
}

/// What a sign panel restricts.
public enum RestrictionKind: Codable, Hashable, Sendable {
    case noParking, noStopping, streetCleaning, loadingZone
    /// "2 HOUR PARKING" -> timeLimit(minutes: 120)
    case timeLimit(minutes: Int)
    /// "RESIDENT PERMIT ONLY"; zone is nil when the sign names no district.
    case permitOnly(zone: String?)
    /// Applies only when the city declares a snow emergency.
    case snowEmergency
}

/// One rule, usually parsed from one panel of a sign.
public struct ParkingRule: Codable, Hashable, Sendable {
    public var kind: RestrictionKind
    public var days: DayRule
    /// nil means all day.
    public var window: TimeWindow?
    /// nil means all year.
    public var season: SeasonalRange?
    public var towZone: Bool
    /// The panel text the rule came from.
    public var sourceText: String

    public init(kind: RestrictionKind, days: DayRule, window: TimeWindow?,
                season: SeasonalRange?, towZone: Bool, sourceText: String) {
        self.kind = kind
        self.days = days
        self.window = window
        self.season = season
        self.towZone = towZone
        self.sourceText = sourceText
    }
}

/// The answer to "can I park here right now, and until when?"
public enum Verdict: Codable, Hashable, Sendable {
    /// moveBy is nil when nothing forces a move within the 8-day horizon.
    case canPark(moveBy: Date?, notes: [String])
    /// allowedFrom is nil when parking never becomes allowed within the horizon.
    case cannotPark(reason: String, allowedFrom: Date?)
    case unreadable(reason: String)

    public var isCanPark: Bool {
        if case .canPark = self { return true }
        return false
    }

    public var moveBy: Date? {
        if case let .canPark(moveBy, _) = self { return moveBy }
        return nil
    }
}
