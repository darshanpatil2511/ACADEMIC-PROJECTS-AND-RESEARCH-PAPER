import Foundation

// JSON format (hand-writable, used by test fixtures and Dataset/labels.json):
//
//   {
//     "kind":   {"type": "streetCleaning"}            // or {"type":"timeLimit","minutes":120}
//                                                     // or {"type":"permitOnly","zone":"BACK BAY"}
//     "days":   {"nth": [2, 4], "weekday": "TUE"}     // or {"days":["MON","WED"]} or "everyDay" (default)
//     "window": {"start": "08:00", "end": "12:00"},   // omit for all day
//     "season": {"startMonth": 4, "startDay": 1, "endMonth": 11, "endDay": 30},  // omit for all year
//     "towZone": true,                                // default false
//     "residentExempt": true                          // "EXCEPT RESIDENT STICKER"; default false
//   }

/// Day of the week. Raw values match `Calendar` `.weekday` (Sunday = 1).
/// Encoded in JSON as "MON", "TUE", ...
public enum Weekday: Int, CaseIterable, Sendable, Comparable, Codable {
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

    /// Three-letter uppercase code used in JSON, e.g. "TUE".
    public var code: String { shortName.uppercased() }

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let n = try? c.decode(Int.self), let day = Weekday(rawValue: n) {
            self = day
            return
        }
        let text = try c.decode(String.self).uppercased()
        guard let day = Weekday.allCases.first(where: { text.hasPrefix($0.code) }) else {
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "Unknown weekday \(text)")
        }
        self = day
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(code)
    }
}

/// A wall-clock time, stored as minutes since midnight (0...1439). Encoded as "HH:mm".
public struct TimeOfDay: Hashable, Comparable, Sendable, Codable, CustomStringConvertible {
    /// Minutes since midnight, 0...1439.
    public var minutes: Int

    public init(minutes: Int) {
        self.minutes = ((minutes % 1440) + 1440) % 1440
    }

    public init(hour: Int, minute: Int = 0) {
        self.init(minutes: hour * 60 + minute)
    }

    /// 0...23
    public var hour: Int { minutes / 60 }
    /// 0...59
    public var minute: Int { minutes % 60 }

    public var description: String { String(format: "%02d:%02d", hour, minute) }

    public static func < (lhs: TimeOfDay, rhs: TimeOfDay) -> Bool { lhs.minutes < rhs.minutes }

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let n = try? c.decode(Int.self) {
            self.init(minutes: n)
            return
        }
        let text = try c.decode(String.self)
        let parts = text.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2, (0...24).contains(parts[0]), (0...59).contains(parts[1]) else {
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "Expected HH:mm, got \(text)")
        }
        self.init(hour: parts[0], minute: parts[1])
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(description)
    }
}

/// A daily time range. The end is exclusive: 8AM–12PM is active 8:00 through 11:59.
/// When `end <= start` the window runs overnight into the next day.
public struct TimeWindow: Codable, Hashable, Sendable {
    /// First minute the window is active.
    public var start: TimeOfDay
    /// First minute after the window (exclusive).
    public var end: TimeOfDay

    public init(start: TimeOfDay, end: TimeOfDay) {
        self.start = start
        self.end = end
    }

    /// True for windows like 10PM-6AM that cross midnight.
    public var isOvernight: Bool { end <= start }
}

/// Which days a rule applies to.
public enum DayRule: Hashable, Sendable, Codable {
    /// No day restriction on the sign.
    case everyDay
    /// e.g. MON-FRI, or EXCEPT SUNDAY (stored as the six other days).
    case days(Set<Weekday>)
    /// e.g. 2ND & 4TH TUE. Ordinals are 1...5, matching `Calendar` `.weekdayOrdinal`.
    case nthWeekday(ordinals: Set<Int>, weekday: Weekday)

    private enum CodingKeys: String, CodingKey { case days, nth, weekday }

    public init(from decoder: Decoder) throws {
        if let text = try? decoder.singleValueContainer().decode(String.self) {
            guard text == "everyDay" || text == "daily" else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                                                        debugDescription: "Unknown day rule \(text)"))
            }
            self = .everyDay
            return
        }
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let days = try c.decodeIfPresent(Set<Weekday>.self, forKey: .days) {
            self = .days(days)
            return
        }
        self = .nthWeekday(ordinals: try c.decode(Set<Int>.self, forKey: .nth),
                           weekday: try c.decode(Weekday.self, forKey: .weekday))
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .everyDay:
            var c = encoder.singleValueContainer()
            try c.encode("everyDay")
        case let .days(set):
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(set.sorted(), forKey: .days)
        case let .nthWeekday(ordinals, weekday):
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(ordinals.sorted(), forKey: .nth)
            try c.encode(weekday, forKey: .weekday)
        }
    }
}

/// A date range within the year, inclusive at both ends. May wrap the year (DEC 1 - MAR 31).
public struct SeasonalRange: Codable, Hashable, Sendable {
    /// First day of the season (inclusive).
    public var startMonth: Int, startDay: Int
    /// Last day of the season (inclusive).
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
public enum RestrictionKind: Hashable, Sendable, Codable {
    case noParking, noStopping, streetCleaning, loadingZone
    /// "2 HOUR PARKING" -> timeLimit(minutes: 120)
    case timeLimit(minutes: Int)
    /// "RESIDENT PERMIT ONLY"; zone is nil when the sign names no district.
    case permitOnly(zone: String?)
    /// Applies only when the city declares a snow emergency.
    case snowEmergency

    private enum CodingKeys: String, CodingKey { case type, minutes, zone }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decode(String.self, forKey: .type)
        switch type {
        case "noParking": self = .noParking
        case "noStopping": self = .noStopping
        case "streetCleaning": self = .streetCleaning
        case "loadingZone": self = .loadingZone
        case "snowEmergency": self = .snowEmergency
        case "timeLimit": self = .timeLimit(minutes: try c.decode(Int.self, forKey: .minutes))
        case "permitOnly": self = .permitOnly(zone: try c.decodeIfPresent(String.self, forKey: .zone))
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: c, debugDescription: "Unknown kind \(type)")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .noParking: try c.encode("noParking", forKey: .type)
        case .noStopping: try c.encode("noStopping", forKey: .type)
        case .streetCleaning: try c.encode("streetCleaning", forKey: .type)
        case .loadingZone: try c.encode("loadingZone", forKey: .type)
        case .snowEmergency: try c.encode("snowEmergency", forKey: .type)
        case let .timeLimit(minutes):
            try c.encode("timeLimit", forKey: .type)
            try c.encode(minutes, forKey: .minutes)
        case let .permitOnly(zone):
            try c.encode("permitOnly", forKey: .type)
            try c.encodeIfPresent(zone, forKey: .zone)
        }
    }
}

/// One rule, usually parsed from one panel of a sign.
public struct ParkingRule: Hashable, Sendable, Codable {
    /// What the rule restricts.
    public var kind: RestrictionKind
    /// Which days it applies to (for overnight windows: the day the window starts).
    public var days: DayRule
    /// nil means all day.
    public var window: TimeWindow?
    /// nil means all year.
    public var season: SeasonalRange?
    /// The panel says TOW ZONE.
    public var towZone: Bool
    /// "EXCEPT RESIDENT STICKER": the rule doesn't apply to cars with a resident permit.
    public var residentExempt: Bool
    /// The panel text the rule came from.
    public var sourceText: String

    public init(kind: RestrictionKind, days: DayRule, window: TimeWindow?,
                season: SeasonalRange?, towZone: Bool, residentExempt: Bool = false, sourceText: String) {
        self.kind = kind
        self.days = days
        self.window = window
        self.season = season
        self.towZone = towZone
        self.residentExempt = residentExempt
        self.sourceText = sourceText
    }

    /// The same rule with `sourceText` cleared, for comparing what rules mean rather than where they came from.
    public var withoutSource: ParkingRule {
        var copy = self
        copy.sourceText = ""
        return copy
    }

    private enum CodingKeys: String, CodingKey { case kind, days, window, season, towZone, residentExempt, sourceText }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = try c.decode(RestrictionKind.self, forKey: .kind)
        days = try c.decodeIfPresent(DayRule.self, forKey: .days) ?? .everyDay
        window = try c.decodeIfPresent(TimeWindow.self, forKey: .window)
        season = try c.decodeIfPresent(SeasonalRange.self, forKey: .season)
        towZone = try c.decodeIfPresent(Bool.self, forKey: .towZone) ?? false
        residentExempt = try c.decodeIfPresent(Bool.self, forKey: .residentExempt) ?? false
        sourceText = try c.decodeIfPresent(String.self, forKey: .sourceText) ?? ""
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(kind, forKey: .kind)
        try c.encode(days, forKey: .days)
        try c.encodeIfPresent(window, forKey: .window)
        try c.encodeIfPresent(season, forKey: .season)
        try c.encode(towZone, forKey: .towZone)
        if residentExempt { try c.encode(true, forKey: .residentExempt) }
        try c.encode(sourceText, forKey: .sourceText)
    }
}

/// The answer to "can I park here right now, and until when?"
public enum Verdict: Codable, Hashable, Sendable {
    /// moveBy is nil when nothing forces a move within the 8-day horizon.
    case canPark(moveBy: Date?, notes: [String])
    /// allowedFrom is nil when parking never becomes allowed within the horizon.
    case cannotPark(reason: String, allowedFrom: Date?)
    case unreadable(reason: String)

    /// True for `.canPark`.
    public var isCanPark: Bool {
        if case .canPark = self { return true }
        return false
    }

    /// The move-by time of a `.canPark` verdict, if any.
    public var moveBy: Date? {
        if case let .canPark(moveBy, _) = self { return moveBy }
        return nil
    }
}
