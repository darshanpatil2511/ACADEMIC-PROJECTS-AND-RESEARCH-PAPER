import Foundation
import Testing
@testable import CurbCore

// All tests use a pinned America/New_York calendar so results never depend
// on the machine's time zone. Reference: Wed 2026-11-04 is a Wednesday;
// November 2026 Tuesdays are the 3rd (1st), 10th (2nd), 17th (3rd), 24th (4th).

private let cal = Calendar.boston

private func at(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int = 0) -> Date {
    let comps = DateComponents(year: y, month: mo, day: d, hour: h, minute: mi)
    guard let date = cal.date(from: comps) else { fatalError("bad test date") }
    return date
}

private func t(_ h: Int, _ m: Int = 0) -> TimeOfDay { TimeOfDay(hour: h, minute: m) }

// MARK: - Rules used across tests

/// "TOW ZONE / STREET CLEANING / 2ND & 4TH TUESDAY / 8AM - 12 NOON / APR 1 - NOV 30"
private let streetCleaning = ParkingRule(
    kind: .streetCleaning,
    days: .nthWeekday(ordinals: [2, 4], weekday: .tue),
    window: TimeWindow(start: t(8), end: t(12)),
    season: SeasonalRange(startMonth: 4, startDay: 1, endMonth: 11, endDay: 30),
    towZone: true,
    sourceText: "STREET CLEANING 2ND & 4TH TUESDAY 8AM-12 NOON APR 1-NOV 30"
)

/// "2 HOUR PARKING / 8AM-8PM / EXCEPT SUNDAY"
private let twoHour = ParkingRule(
    kind: .timeLimit(minutes: 120),
    days: .days([.mon, .tue, .wed, .thu, .fri, .sat]),
    window: TimeWindow(start: t(8), end: t(20)),
    season: nil,
    towZone: false,
    sourceText: "2 HOUR PARKING 8AM-8PM EXCEPT SUNDAY"
)

/// "NO PARKING 2AM-6AM"
private let noParkingNight = ParkingRule(
    kind: .noParking, days: .everyDay,
    window: TimeWindow(start: t(2), end: t(6)),
    season: nil, towZone: false, sourceText: "NO PARKING 2AM-6AM"
)

/// "NO STOPPING ANY TIME"
private let noStopping = ParkingRule(
    kind: .noStopping, days: .everyDay, window: nil,
    season: nil, towZone: true, sourceText: "NO STOPPING ANY TIME"
)

@Suite("Model")
struct ModelTests {
    @Test func weekdayRawValuesMatchCalendar() {
        // 2026-11-04 is a Wednesday; Calendar weekday 4.
        #expect(cal.component(.weekday, from: at(2026, 11, 4, 12)) == Weekday.wed.rawValue)
    }

    @Test func timeOfDayOrdering() {
        #expect(t(8) < t(12))
        #expect(t(23, 59).minutes == 1439)
    }

    @Test func overnightWindowDetection() {
        #expect(TimeWindow(start: t(22), end: t(6)).isOvernight)
        #expect(!TimeWindow(start: t(8), end: t(20)).isOvernight)
    }

    @Test func rulesRoundTripThroughJSON() throws {
        let rules = [streetCleaning, twoHour, noParkingNight, noStopping,
                     ParkingRule(kind: .permitOnly(zone: "BACK BAY"), days: .everyDay, window: nil,
                                 season: nil, towZone: false, sourceText: "RESIDENT PERMIT")]
        let data = try JSONEncoder().encode(rules)
        let decoded = try JSONDecoder().decode([ParkingRule].self, from: data)
        #expect(decoded == rules)
    }
}

@Suite("RuleEngine.isActive")
struct IsActiveTests {
    @Test func windowEndIsExclusive() {
        #expect(RuleEngine.isActive(streetCleaning, at: at(2026, 11, 10, 11, 59), calendar: cal))
        #expect(!RuleEngine.isActive(streetCleaning, at: at(2026, 11, 10, 12, 0), calendar: cal))
        #expect(RuleEngine.isActive(streetCleaning, at: at(2026, 11, 10, 8, 0), calendar: cal))
    }

    @Test func nthWeekdayOnlyMatchesListedOrdinals() {
        #expect(!RuleEngine.isActive(streetCleaning, at: at(2026, 11, 3, 9), calendar: cal))  // 1st Tue
        #expect(RuleEngine.isActive(streetCleaning, at: at(2026, 11, 24, 9), calendar: cal))  // 4th Tue
    }

    @Test func seasonThatWrapsTheYear() {
        let winter = ParkingRule(
            kind: .noParking, days: .everyDay, window: nil,
            season: SeasonalRange(startMonth: 12, startDay: 1, endMonth: 3, endDay: 31),
            towZone: false, sourceText: "NO PARKING DEC 1 - MAR 31")
        #expect(RuleEngine.isActive(winter, at: at(2027, 1, 15, 12), calendar: cal))
        #expect(RuleEngine.isActive(winter, at: at(2026, 12, 1, 0), calendar: cal))
        #expect(RuleEngine.isActive(winter, at: at(2027, 3, 31, 23, 59), calendar: cal))
        #expect(!RuleEngine.isActive(winter, at: at(2027, 4, 1, 0), calendar: cal))
        #expect(!RuleEngine.isActive(winter, at: at(2026, 7, 4, 12), calendar: cal))
    }

    @Test func overnightWindowUsesTheDayItStarts() {
        // "NO PARKING 10PM-6AM FRI" -> Fri 22:00 through Sat 05:59.
        let fridayNight = ParkingRule(
            kind: .noParking, days: .days([.fri]),
            window: TimeWindow(start: t(22), end: t(6)),
            season: nil, towZone: false, sourceText: "NO PARKING 10PM-6AM FRI")
        #expect(RuleEngine.isActive(fridayNight, at: at(2026, 11, 6, 23), calendar: cal))   // Fri night
        #expect(RuleEngine.isActive(fridayNight, at: at(2026, 11, 7, 5, 59), calendar: cal)) // Sat early
        #expect(!RuleEngine.isActive(fridayNight, at: at(2026, 11, 7, 6), calendar: cal))
        #expect(!RuleEngine.isActive(fridayNight, at: at(2026, 11, 6, 3), calendar: cal))   // Fri early = Thu's window
        #expect(!RuleEngine.isActive(fridayNight, at: at(2026, 11, 7, 23), calendar: cal))  // Sat night
    }

    @Test func nilWindowMeansAllDay() {
        #expect(RuleEngine.isActive(noStopping, at: at(2026, 11, 4, 0), calendar: cal))
        #expect(RuleEngine.isActive(noStopping, at: at(2026, 11, 4, 23, 59), calendar: cal))
    }
}

@Suite("RuleEngine.evaluate")
struct EvaluateTests {
    // MARK: Street cleaning

    @Test func streetCleaningActiveNow() {
        let v = RuleEngine.evaluate(rules: [streetCleaning], arrival: at(2026, 11, 10, 9),
                                    calendar: cal, permitZone: nil)
        guard case let .cannotPark(_, allowedFrom) = v else {
            Issue.record("expected cannotPark, got \(v)"); return
        }
        #expect(allowedFrom == at(2026, 11, 10, 12))
    }

    @Test func streetCleaningNextWeek() {
        let v = RuleEngine.evaluate(rules: [streetCleaning], arrival: at(2026, 11, 17, 9),
                                    calendar: cal, permitZone: nil)
        #expect(v.moveBy == at(2026, 11, 24, 8))
        #expect(v.isCanPark)
    }

    @Test func streetCleaningOutOfSeason() {
        let v = RuleEngine.evaluate(rules: [streetCleaning], arrival: at(2026, 12, 8, 9),
                                    calendar: cal, permitZone: nil)
        #expect(v == .canPark(moveBy: nil, notes: []))
    }

    // MARK: Time limits

    @Test func twoHourMidday() {
        let v = RuleEngine.evaluate(rules: [twoHour], arrival: at(2026, 11, 4, 10),
                                    calendar: cal, permitZone: nil)
        #expect(v.moveBy == at(2026, 11, 4, 12))
    }

    @Test func twoHourCounterPausesOvernight() {
        // 19:00-20:00 counts 60 min, pauses, resumes Thu 08:00, hits 120 at 09:00.
        let v = RuleEngine.evaluate(rules: [twoHour], arrival: at(2026, 11, 4, 19),
                                    calendar: cal, permitZone: nil)
        #expect(v.moveBy == at(2026, 11, 5, 9))
    }

    @Test func twoHourSkipsSunday() {
        let v = RuleEngine.evaluate(rules: [twoHour], arrival: at(2026, 11, 7, 19),
                                    calendar: cal, permitZone: nil)
        #expect(v.moveBy == at(2026, 11, 9, 9))
    }

    // MARK: Prohibitions

    @Test func noParkingOvernightAhead() {
        let v = RuleEngine.evaluate(rules: [noParkingNight], arrival: at(2026, 11, 4, 23),
                                    calendar: cal, permitZone: nil)
        #expect(v.moveBy == at(2026, 11, 5, 2))
    }

    @Test func noStoppingAnyTime() {
        let v = RuleEngine.evaluate(rules: [noStopping], arrival: at(2026, 11, 4, 12),
                                    calendar: cal, permitZone: nil)
        guard case let .cannotPark(reason, allowedFrom) = v else {
            Issue.record("expected cannotPark, got \(v)"); return
        }
        #expect(allowedFrom == nil)
        #expect(reason.lowercased().contains("no stopping"))
    }

    @Test func stackedRulesEarliestDeadlineWins() {
        // 2-hour limit would end at 12:00, but no parking starts at 11:00.
        let noParkingLate = ParkingRule(
            kind: .noParking, days: .days([.wed]),
            window: TimeWindow(start: t(11), end: t(13)),
            season: nil, towZone: false, sourceText: "NO PARKING 11AM-1PM WED")
        let v1 = RuleEngine.evaluate(rules: [twoHour, noParkingLate], arrival: at(2026, 11, 4, 10),
                                     calendar: cal, permitZone: nil)
        #expect(v1.moveBy == at(2026, 11, 4, 11))
        // Order of rules must not matter.
        let v2 = RuleEngine.evaluate(rules: [noParkingLate, twoHour], arrival: at(2026, 11, 4, 10),
                                     calendar: cal, permitZone: nil)
        #expect(v2.moveBy == at(2026, 11, 4, 11))
    }

    @Test func arrivalWithSecondsIsTruncatedToTheMinute() {
        let arrival = at(2026, 11, 4, 10).addingTimeInterval(37)
        let v = RuleEngine.evaluate(rules: [twoHour], arrival: arrival, calendar: cal, permitZone: nil)
        #expect(v.moveBy == at(2026, 11, 4, 12))
    }

    // MARK: Notes: snow emergency and permits

    @Test func snowEmergencyAddsNoteWithoutBlocking() {
        let snow = ParkingRule(kind: .snowEmergency, days: .everyDay, window: nil,
                               season: nil, towZone: true, sourceText: "TOW ZONE SNOW EMERGENCY")
        let v = RuleEngine.evaluate(rules: [snow], arrival: at(2026, 11, 4, 12),
                                    calendar: cal, permitZone: nil)
        #expect(v == .canPark(moveBy: nil, notes: ["Tow zone during declared snow emergencies"]))
    }

    private var permitRule: ParkingRule {
        ParkingRule(kind: .permitOnly(zone: "BACK BAY"), days: .days([.mon, .tue, .wed, .thu, .fri]),
                    window: TimeWindow(start: t(8), end: t(18)),
                    season: nil, towZone: false, sourceText: "RESIDENT PERMIT PARKING ONLY BACK BAY 8AM-6PM MON-FRI")
    }

    @Test func permitWithUnknownZoneAddsNote() {
        let v = RuleEngine.evaluate(rules: [permitRule], arrival: at(2026, 11, 4, 10),
                                    calendar: cal, permitZone: nil)
        guard case let .canPark(moveBy, notes) = v else {
            Issue.record("expected canPark, got \(v)"); return
        }
        #expect(moveBy == nil)
        #expect(notes.count == 1)
    }

    @Test func permitWithWrongZoneBlocks() {
        let v = RuleEngine.evaluate(rules: [permitRule], arrival: at(2026, 11, 4, 10),
                                    calendar: cal, permitZone: "SOUTH END")
        guard case let .cannotPark(_, allowedFrom) = v else {
            Issue.record("expected cannotPark, got \(v)"); return
        }
        #expect(allowedFrom == at(2026, 11, 4, 18))
    }

    @Test func permitWithMatchingZoneIsAllowed() {
        let v = RuleEngine.evaluate(rules: [permitRule], arrival: at(2026, 11, 4, 10),
                                    calendar: cal, permitZone: "back bay")
        #expect(v == .canPark(moveBy: nil, notes: []))
    }

    @Test func noRulesMeansUnreadable() {
        let v = RuleEngine.evaluate(rules: [], arrival: at(2026, 11, 4, 10), calendar: cal, permitZone: nil)
        guard case .unreadable = v else { Issue.record("expected unreadable, got \(v)"); return }
    }
}
