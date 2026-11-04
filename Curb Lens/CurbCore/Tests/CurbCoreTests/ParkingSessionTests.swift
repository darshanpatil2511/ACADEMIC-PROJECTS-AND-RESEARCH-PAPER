import Foundation
import Testing
@testable import CurbCore

// Reference week: Wed 2026-11-04. Tue 2026-11-10 is the 2nd Tuesday of November.

private let cal = Calendar.boston

private func at(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int = 0) -> Date {
    guard let date = cal.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi)) else {
        fatalError("bad test date")
    }
    return date
}

private func t(_ h: Int, _ m: Int = 0) -> TimeOfDay { TimeOfDay(hour: h, minute: m) }

/// "TOW ZONE / STREET CLEANING / 2ND & 4TH TUESDAY / 8AM - 12 NOON / APR 1 - NOV 30"
private let streetCleaning = ParkingRule(
    kind: .streetCleaning, days: .nthWeekday(ordinals: [2, 4], weekday: .tue),
    window: TimeWindow(start: t(8), end: t(12)),
    season: SeasonalRange(startMonth: 4, startDay: 1, endMonth: 11, endDay: 30),
    towZone: true, sourceText: "STREET CLEANING 2ND & 4TH TUESDAY 8AM-12 NOON")

/// "2 HOUR PARKING / 8AM-8PM / EXCEPT SUNDAY"
private let twoHour = ParkingRule(
    kind: .timeLimit(minutes: 120), days: .days([.mon, .tue, .wed, .thu, .fri, .sat]),
    window: TimeWindow(start: t(8), end: t(20)), season: nil, towZone: false,
    sourceText: "2 HOUR PARKING 8AM-8PM EXCEPT SUNDAY")

@Suite("Parking reminders")
struct ReminderPlannerTests {
    @Test func remindsThirtyAndTenMinutesBeforeAndAtMoveTime() {
        let parked = at(2026, 11, 4, 9)                      // Wed 9:00, 2-hour limit -> move by 11:00
        let verdict = RuleEngine.evaluate(rules: [twoHour], arrival: parked, calendar: cal, permitZone: nil)
        #expect(verdict.moveBy == at(2026, 11, 4, 11))

        let plan = ReminderPlanner.plan(rules: [twoHour], verdict: verdict, now: parked, calendar: cal)
        #expect(plan.map(\.fireDate) == [at(2026, 11, 4, 10, 30), at(2026, 11, 4, 10, 50), at(2026, 11, 4, 11)])
        #expect(plan.map(\.minutesBefore) == [30, 10, 0])
        #expect(plan[0].title == "Move your car in 30 min")
        #expect(plan[0].body == "Move by today at 11:00 AM · 2-hour limit ends")
        #expect(plan[2].title == "Move your car now")
    }

    @Test func skipsRemindersAlreadyInThePast() {
        // Parked Tue Nov 10 7:45, street cleaning starts 8:00: the 30-minute reminder is already past.
        let parked = at(2026, 11, 10, 7, 45)
        let rules = [streetCleaning]
        let verdict = RuleEngine.evaluate(rules: rules, arrival: parked, calendar: cal, permitZone: nil)
        #expect(verdict.moveBy == at(2026, 11, 10, 8))
        let plan = ReminderPlanner.plan(rules: rules, verdict: verdict, now: parked, calendar: cal)
        #expect(plan.map(\.minutesBefore) == [10, 0])
        #expect(plan[0].body == "Move by today at 8:00 AM · Street cleaning starts (tow zone)")
    }

    @Test func noRemindersWhenThereIsNoMoveTimeOrParkingIsNotAllowed() {
        let now = at(2026, 11, 4, 9)
        #expect(ReminderPlanner.plan(rules: [], verdict: .canPark(moveBy: nil, notes: []), now: now, calendar: cal).isEmpty)
        #expect(ReminderPlanner.plan(rules: [], verdict: .cannotPark(reason: "x", allowedFrom: nil), now: now, calendar: cal).isEmpty)
        #expect(ReminderPlanner.plan(rules: [], verdict: .unreadable(reason: "x"), now: now, calendar: cal).isEmpty)
    }

    @Test func moveReasonPrefersTheRuleThatStartsOverTheTimeLimit() {
        // Parked Tue Nov 10 7:00 with both rules: cleaning at 8:00 comes first.
        let parked = at(2026, 11, 10, 7)
        let rules = [twoHour, streetCleaning]
        let verdict = RuleEngine.evaluate(rules: rules, arrival: parked, calendar: cal, permitZone: nil)
        #expect(verdict.moveBy == at(2026, 11, 10, 8))
        #expect(ReminderPlanner.moveReason(rules: rules, moveBy: at(2026, 11, 10, 8), calendar: cal)
                == "Street cleaning starts (tow zone)")
    }
}

@Suite("Compass and distance")
struct GeoTextTests {
    @Test func cardinalDirections() {
        #expect(GeoText.cardinal(0) == "N")
        #expect(GeoText.cardinal(44) == "NE")
        #expect(GeoText.cardinal(90) == "E")
        #expect(GeoText.cardinal(200) == "S")
        #expect(GeoText.cardinal(337.6) == "N")
        #expect(GeoText.cardinal(-90) == "W")
        #expect(GeoText.cardinal(720 + 270) == "W")
    }

    @Test func haversineDistance() {
        // Park St station to Copley Square is about 1.4 km.
        let d = GeoText.distanceMeters(lat1: 42.3564, lon1: -71.0624, lat2: 42.3499, lon2: -71.0774)
        #expect(abs(d - 1_400) < 150)
        #expect(GeoText.distanceMeters(lat1: 42.35, lon1: -71.06, lat2: 42.35, lon2: -71.06) == 0)
    }

    @Test func cameraPitchFromGravity() {
        // Upright portrait: camera looks at the horizon.
        #expect(abs(GeoText.cameraPitchDegrees(gravityX: 0, gravityY: -1, gravityZ: 0)) < 0.001)
        // Flat on a table, screen up: camera looks straight down.
        #expect(abs(GeoText.cameraPitchDegrees(gravityX: 0, gravityY: 0, gravityZ: -1) - (-90)) < 0.001)
        // Tilted back 30° to aim at a sign high on a pole: g = (0, -cos30, +sin30).
        #expect(abs(GeoText.cameraPitchDegrees(gravityX: 0, gravityY: -0.866, gravityZ: 0.5) - 30) < 0.1)
        // Not unit length (accelerometer noise) still works.
        #expect(abs(GeoText.cameraPitchDegrees(gravityX: 0, gravityY: -1.7, gravityZ: 1) - 30.5) < 0.2)
    }

    @Test func pitchLabels() {
        #expect(GeoText.pitchLabel(degrees: 12.4) == "camera 12° up")
        #expect(GeoText.pitchLabel(degrees: -8) == "camera 8° down")
        #expect(GeoText.pitchLabel(degrees: 1.2) == "camera level")
    }

    @Test func distanceLabels() {
        #expect(GeoText.distanceLabel(meters: 12) == "12 m")
        #expect(GeoText.distanceLabel(meters: 999) == "999 m")
        #expect(GeoText.distanceLabel(meters: 1_450) == "1.4 km")
    }
}

@Suite("Saved rules archive")
struct RuleArchiveTests {
    @Test func roundTrips() throws {
        let data = try RuleArchive.encode([streetCleaning, twoHour])
        #expect(try RuleArchive.decode(data) == [streetCleaning, twoHour])
    }

    @Test func badDataThrows() {
        #expect((try? RuleArchive.decode(Data("nope".utf8))) == nil)
    }
}
