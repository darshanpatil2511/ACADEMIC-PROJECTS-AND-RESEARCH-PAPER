import Foundation
import Testing
@testable import CurbCore

@Suite("VerdictFormatter")
struct VerdictFormatterTests {
    private let cal = Calendar.boston

    private func at(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int = 0) -> Date {
        cal.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi)) ?? .distantPast
    }

    @Test func relativeDayWords() {
        let now = at(2026, 11, 4, 19)   // Wednesday evening
        #expect(VerdictFormatter.relative(at(2026, 11, 4, 20), now: now, calendar: cal) == "today at 8:00 PM")
        #expect(VerdictFormatter.relative(at(2026, 11, 5, 9), now: now, calendar: cal) == "tomorrow at 9:00 AM")
        #expect(VerdictFormatter.relative(at(2026, 11, 9, 9), now: now, calendar: cal) == "Mon at 9:00 AM")
        #expect(VerdictFormatter.relative(at(2026, 11, 24, 8), now: now, calendar: cal) == "Tue Nov 24 at 8:00 AM")
    }

    @Test func presentations() {
        let now = at(2026, 11, 10, 9)
        let go = VerdictFormatter.present(.canPark(moveBy: at(2026, 11, 10, 11), notes: ["n"]), now: now, calendar: cal)
        #expect(go == VerdictPresentation(tone: .go, title: "You can park", detail: "Move by today at 11:00 AM", notes: ["n"]))

        let stop = VerdictFormatter.present(.cannotPark(reason: "Street cleaning", allowedFrom: at(2026, 11, 10, 12)),
                                            now: now, calendar: cal)
        #expect(stop.tone == .stop)
        #expect(stop.title == "No parking now")
        #expect(stop.detail == "Allowed from today at 12:00 PM · Street cleaning")

        #expect(VerdictFormatter.present(.canPark(moveBy: nil, notes: []), now: now, calendar: cal).detail
                == "No time limit in the next 8 days")
        #expect(VerdictFormatter.present(.unreadable(reason: "x"), now: now, calendar: cal).tone == .unknown)
    }

    @Test func towBadgeOnlyWhenTowRuleMatters() {
        let cleaning = ParkingRule(kind: .streetCleaning, days: .nthWeekday(ordinals: [2, 4], weekday: .tue),
                                   window: TimeWindow(start: TimeOfDay(hour: 8), end: TimeOfDay(hour: 12)),
                                   season: nil, towZone: true, sourceText: "")
        // Active now -> badge.
        let during = at(2026, 11, 10, 9)
        let v1 = RuleEngine.evaluate(rules: [cleaning], arrival: during, calendar: cal, permitZone: nil)
        #expect(RuleEngine.towZoneApplies(rules: [cleaning], verdict: v1, at: during, calendar: cal))
        // Starts at the move-by time -> badge.
        let before = at(2026, 11, 17, 9)
        let v2 = RuleEngine.evaluate(rules: [cleaning], arrival: before, calendar: cal, permitZone: nil)
        #expect(RuleEngine.towZoneApplies(rules: [cleaning], verdict: v2, at: before, calendar: cal))
        // A non-tow rule never shows the badge.
        var plain = cleaning
        plain.towZone = false
        #expect(!RuleEngine.towZoneApplies(rules: [plain], verdict: v1, at: during, calendar: cal))
    }
}
