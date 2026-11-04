import Foundation

extension Calendar {
    /// Gregorian calendar pinned to Boston time. Inject this into all CurbCore date logic.
    public static var boston: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/New_York") ?? .current
        cal.locale = Locale(identifier: "en_US_POSIX")
        return cal
    }
}

/// Decides whether rules are in force at a given moment and turns a set of rules into a `Verdict`.
///
/// The engine never reads the clock: callers pass the arrival time and calendar in.
public enum RuleEngine {
    /// How far ahead `evaluate` simulates.
    public static let horizonMinutes = 8 * 24 * 60

    /// Note added when a sign has a snow-emergency panel.
    public static let snowEmergencyNote = "Tow zone during declared snow emergencies"

    // MARK: - isActive

    /// True when `rule` is in force at `date`.
    ///
    /// For overnight windows (e.g. 10PM–6AM) the day and season checks apply to the
    /// day the window starts, so "FRI 10PM–6AM" covers Saturday 3AM but not Friday 3AM.
    public static func isActive(_ rule: ParkingRule, at date: Date, calendar: Calendar) -> Bool {
        isActive(rule, in: MinuteContext(date: date, calendar: calendar))
    }

    static func isActive(_ rule: ParkingRule, in ctx: MinuteContext) -> Bool {
        guard let window = rule.window else {
            return applies(rule, on: ctx.today)
        }
        let now = ctx.today.minuteOfDay
        if !window.isOvernight {
            return now >= window.start.minutes && now < window.end.minutes && applies(rule, on: ctx.today)
        }
        if now >= window.start.minutes {
            return applies(rule, on: ctx.today)          // evening part, window started today
        }
        if now < window.end.minutes {
            return applies(rule, on: ctx.yesterday)      // early-morning part, started yesterday
        }
        return false
    }

    /// Day and season check for one calendar day.
    private static func applies(_ rule: ParkingRule, on day: DayInfo) -> Bool {
        if let season = rule.season, !season.contains(month: day.month, day: day.day) {
            return false
        }
        switch rule.days {
        case .everyDay:
            return true
        case let .days(set):
            return set.contains(day.weekday)
        case let .nthWeekday(ordinals, weekday):
            return day.weekday == weekday && ordinals.contains(day.weekdayOrdinal)
        }
    }

    // MARK: - evaluate

    /// Turns a sign's rules into a verdict by simulating minute by minute from `arrival`
    /// for up to `horizonMinutes`.
    ///
    /// - A prohibiting rule active at arrival gives `.cannotPark`, with `allowedFrom` set to the
    ///   first minute no prohibiting rule is active.
    /// - Otherwise the first minute a prohibiting rule becomes active, or the minute after any
    ///   time-limit counter fills up, is `moveBy`. Counters only advance while their rule is active,
    ///   so a 2-hour limit started at 7PM pauses overnight and finishes the next morning.
    /// - Snow-emergency rules and permit rules with an unknown `permitZone` add notes instead of blocking.
    public static func evaluate(rules: [ParkingRule], arrival: Date, calendar: Calendar,
                                permitZone: String?) -> Verdict {
        guard !rules.isEmpty else {
            return .unreadable(reason: "No parking rules were found on this sign.")
        }

        let start = truncatedToMinute(arrival, calendar: calendar)
        let notes = self.notes(for: rules, permitZone: permitZone)
        let prohibiting = rules.filter { isProhibiting($0, permitZone: permitZone) }
        let limits: [(rule: ParkingRule, limit: Int)] = rules.compactMap { rule in
            if case let .timeLimit(minutes) = rule.kind, minutes > 0 { return (rule, minutes) }
            return nil
        }

        let arrivalCtx = MinuteContext(date: start, calendar: calendar)
        if let blocking = prohibiting.first(where: { isActive($0, in: arrivalCtx) }) {
            let allowedFrom = firstMinute(after: start, calendar: calendar) { ctx in
                !prohibiting.contains { isActive($0, in: ctx) }
            }
            return .cannotPark(reason: RuleDescriber.reason(for: blocking), allowedFrom: allowedFrom)
        }

        var counters = Array(repeating: 0, count: limits.count)
        for step in 0..<horizonMinutes {
            let date = start.addingTimeInterval(TimeInterval(step * 60))
            let ctx = MinuteContext(date: date, calendar: calendar)

            if step > 0, prohibiting.contains(where: { isActive($0, in: ctx) }) {
                return .canPark(moveBy: date, notes: notes)
            }
            for (index, entry) in limits.enumerated() where isActive(entry.rule, in: ctx) {
                counters[index] += 1
                if counters[index] >= entry.limit {
                    // The car has used its full allowance by the end of this minute.
                    return .canPark(moveBy: date.addingTimeInterval(60), notes: notes)
                }
            }
        }
        return .canPark(moveBy: nil, notes: notes)
    }

    // MARK: - Helpers

    static func isProhibiting(_ rule: ParkingRule, permitZone: String?) -> Bool {
        switch rule.kind {
        case .noParking, .noStopping, .streetCleaning, .loadingZone:
            return true
        case let .permitOnly(zone):
            guard let permitZone else { return false }          // unknown permit: note only
            guard let zone else { return false }                // sign names no district: any permit
            return normalizedZone(zone) != normalizedZone(permitZone)
        case .timeLimit, .snowEmergency:
            return false
        }
    }

    private static func notes(for rules: [ParkingRule], permitZone: String?) -> [String] {
        var notes: [String] = []
        if rules.contains(where: { $0.kind == .snowEmergency }) {
            notes.append(snowEmergencyNote)
        }
        if permitZone == nil {
            for rule in rules {
                guard case .permitOnly = rule.kind else { continue }
                let note = "Resident permit required: \(RuleDescriber.describe(rule))"
                if !notes.contains(note) { notes.append(note) }
            }
        }
        return notes
    }

    private static func normalizedZone(_ zone: String) -> String {
        zone.uppercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).joined(separator: " ")
    }

    private static func truncatedToMinute(_ date: Date, calendar: Calendar) -> Date {
        let comps = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return calendar.date(from: comps) ?? date
    }

    /// First minute in (start, start + horizon] where `predicate` holds.
    private static func firstMinute(after start: Date, calendar: Calendar,
                                    where predicate: (MinuteContext) -> Bool) -> Date? {
        for step in 1...horizonMinutes {
            let date = start.addingTimeInterval(TimeInterval(step * 60))
            if predicate(MinuteContext(date: date, calendar: calendar)) { return date }
        }
        return nil
    }
}

// MARK: - Per-minute calendar facts

/// Calendar facts for one day, computed once per simulated minute.
struct DayInfo {
    let month: Int
    let day: Int
    let weekday: Weekday
    let weekdayOrdinal: Int
    let minuteOfDay: Int

    init(date: Date, calendar: Calendar) {
        let c = calendar.dateComponents([.month, .day, .weekday, .weekdayOrdinal, .hour, .minute], from: date)
        month = c.month ?? 1
        day = c.day ?? 1
        weekday = Weekday(rawValue: c.weekday ?? 1) ?? .sun
        weekdayOrdinal = c.weekdayOrdinal ?? 1
        minuteOfDay = (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }
}

/// Today's facts plus (lazily) yesterday's, for overnight windows.
struct MinuteContext {
    let today: DayInfo
    private let date: Date
    private let calendar: Calendar

    init(date: Date, calendar: Calendar) {
        self.date = date
        self.calendar = calendar
        self.today = DayInfo(date: date, calendar: calendar)
    }

    var yesterday: DayInfo {
        let previous = calendar.date(byAdding: .day, value: -1, to: date) ?? date.addingTimeInterval(-86_400)
        return DayInfo(date: previous, calendar: calendar)
    }
}
