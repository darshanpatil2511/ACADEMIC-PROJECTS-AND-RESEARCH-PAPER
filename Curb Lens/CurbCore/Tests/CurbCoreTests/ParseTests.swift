import Foundation
import Testing
@testable import CurbCore

@Suite("TextNormalizer")
struct TextNormalizerTests {
    private func norm(_ s: String) -> String { TextNormalizer.normalize(s).text }

    @Test func fixesWordConfusions() {
        let result = TextNormalizer.normalize("N0 PARKING T0W ZONE M0NDAY")
        #expect(result.text == "NO PARKING TOW ZONE MONDAY")
        #expect(result.substitutions.contains("N0→NO"))
        #expect(result.substitutions.contains("M0NDAY→MONDAY"))
    }

    @Test func fixesDigitConfusionsAndNoon() {
        #expect(norm("8AM-l2 NOON") == "8AM - 12PM")
        #expect(norm("I2 N00N") == "12PM")
        #expect(norm("1O:3OAM") == "10:30AM")
    }

    @Test func unifiesRangesAndMeridiem() {
        #expect(norm("8 a.m. to 6 p.m.") == "8AM - 6PM")
        #expect(norm("MON THRU SAT") == "MON - SAT")
        #expect(norm("8AM\u{2013}12PM") == "8AM - 12PM")    // en dash
        #expect(norm("10PM - MIDNIGHT") == "10PM - 12AM")
        #expect(norm("12NOON") == "12PM")
    }

    @Test func leavesRealWordsAlone() {
        #expect(norm("SOUTH BOSTON") == "SOUTH BOSTON")
        #expect(norm("1ST & 3RD") == "1ST & 3RD")
        #expect(norm("IS") == "IS")
        #expect(norm("TOWED") == "TOWED")
    }

    @Test func specialCases() {
        #expect(norm("l HR PARKING") == "1 HR PARKING")
        #expect(norm("TOW-AWAY ZONE") == "TOW ZONE")
        #expect(norm("NO STOPPING ANYTIME") == "NO STOPPING ANY TIME")
        #expect(norm("OWNER'S EXPENSE") == "OWNERS EXPENSE")
    }

    @Test func cleanTextHasNoOCRFixes() {
        let result = TextNormalizer.normalize("NO PARKING 8AM - 12PM")
        #expect(result.substitutions.isEmpty)
    }
}

@Suite("Tokenizer")
struct TokenizerTests {
    @Test func typesTokens() {
        let kinds = Tokenizer.tokenize("2 HR PARKING 8AM - 7:30PM EXCEPT SUNDAY").map(\.kind)
        #expect(kinds == [
            .number(2), .keyword("HOUR"), .keyword("PARKING"),
            .time(TimeOfDay(hour: 8)), .dash, .time(TimeOfDay(hour: 19, minute: 30)),
            .keyword("EXCEPT"), .day(.sun),
        ])
    }

    @Test func ordinalsMonthsAndAliases() {
        let kinds = Tokenizer.tokenize("1ST & 3RD TUES APRIL 1 THURS AND 12AM").map(\.kind)
        #expect(kinds == [
            .ordinal(1), .and, .ordinal(3), .day(.tue), .month(4), .number(1),
            .day(.thu), .and, .time(TimeOfDay(hour: 0)),
        ])
    }

    @Test func unknownWordsAreKept() {
        #expect(Tokenizer.tokenize("BACK BAY").map(\.kind) == [.unknown("BACK"), .unknown("BAY")])
    }
}

// MARK: - Fixture-driven parser tests

struct SignFixture: Codable, Sendable, CustomTestStringConvertible {
    var name: String
    var panels: [String]
    var expectedRules: [ParkingRule]
    /// Fixtures in the same group describe the same sign (clean vs. noisy OCR).
    var group: String?
    var noisy: Bool?
    var garbage: Bool?

    var testDescription: String { name }
}

enum Fixtures {
    static let signTexts: [SignFixture] = {
        guard let url = Bundle.module.url(forResource: "sign_texts", withExtension: "json",
                                          subdirectory: "Fixtures"),
              let data = try? Data(contentsOf: url) else {
            fatalError("Missing Fixtures/sign_texts.json")
        }
        do {
            return try JSONDecoder().decode([SignFixture].self, from: data)
        } catch {
            fatalError("sign_texts.json is invalid: \(error)")
        }
    }()
}

@Suite("SignParser")
struct SignParserTests {
    @Test("Fixture", arguments: Fixtures.signTexts)
    func fixture(_ fixture: SignFixture) {
        let result = SignParser.parse(panels: fixture.panels)
        let expected = fixture.expectedRules.map(\.withoutSource)
        let actual = result.rules.map(\.withoutSource)

        let missing = expected.filter { !actual.contains($0) }
        let extra = actual.filter { !expected.contains($0) }
        if !missing.isEmpty || !extra.isEmpty || expected.count != actual.count {
            var diff = "\n  panels: \(fixture.panels)"
            for rule in missing { diff += "\n  - missing: \(RuleDescriber.describe(rule))  \(json(rule))" }
            for rule in extra { diff += "\n  + extra:   \(RuleDescriber.describe(rule))  \(json(rule))" }
            diff += "\n  unparsed: \(result.unparsedTokens)  normalizations: \(result.normalizations)"
            Issue.record("\(fixture.name) mismatch:\(diff)")
        }

        if fixture.garbage == true {
            #expect(result.rules.isEmpty)
            #expect(result.confidence < 0.5)
        }
        if fixture.noisy == true {
            #expect(!result.normalizations.isEmpty, "noisy fixture should need OCR fixes")
        }
    }

    @Test func atLeastThirtyFixturesIncludingGarbage() {
        #expect(Fixtures.signTexts.count >= 30)
        #expect(Fixtures.signTexts.filter { $0.garbage == true }.count >= 3)
    }

    /// Clean and noisy versions of a sign must expect (and therefore produce) the same rules.
    @Test func groupsShareExpectedRules() {
        let groups = Dictionary(grouping: Fixtures.signTexts.filter { $0.group != nil }, by: { $0.group ?? "" })
        for (group, members) in groups {
            let first = Set(members[0].expectedRules.map(\.withoutSource))
            for member in members.dropFirst() {
                #expect(Set(member.expectedRules.map(\.withoutSource)) == first, "group \(group): \(member.name)")
            }
            #expect(members.contains { $0.noisy == true } || members.count > 1, "group \(group)")
        }
    }

    @Test func cleanSignIsFullyUnderstood() {
        let result = SignParser.parse(panels: ["2 HOUR PARKING", "8AM-8PM", "EXCEPT SUNDAY"])
        #expect(result.confidence == 1.0)
        #expect(result.unparsedTokens.isEmpty)
    }

    @Test func unknownWordsLowerConfidence() {
        let result = SignParser.parse(panels: ["NO PARKING", "HERE TO CORNER"])
        #expect(result.rules.count == 1)
        #expect(result.confidence < 0.7)
        #expect(result.unparsedTokens == ["HERE", "CORNER"])
    }

    @Test func exceptHolidaysIsReportedNotIgnored() {
        let result = SignParser.parse(panels: ["2 HOUR PARKING 8AM-6PM EXCEPT HOLIDAYS"])
        #expect(result.unparsedTokens.contains("HOLIDAYS"))
    }

    @Test func parsedSignFeedsTheRuleEngine() {
        // End to end: noisy OCR text -> rules -> verdict.
        let result = SignParser.parse(panels: ["N0 PARKING", "T0W ZONE", "STREET CLEANING",
                                               "2ND & 4TH TUESDAY", "8AM - l2 N00N", "APR 1 - NOV 30"])
        let cal = Calendar.boston
        guard let arrival = cal.date(from: DateComponents(year: 2026, month: 11, day: 10, hour: 9)) else {
            Issue.record("bad date"); return
        }
        let verdict = RuleEngine.evaluate(rules: result.rules, arrival: arrival, calendar: cal, permitZone: nil)
        guard case let .cannotPark(_, allowedFrom) = verdict else {
            Issue.record("expected cannotPark, got \(verdict)"); return
        }
        #expect(allowedFrom == cal.date(from: DateComponents(year: 2026, month: 11, day: 10, hour: 12)))
    }

    private func json(_ rule: ParkingRule) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return (try? encoder.encode(rule)).flatMap { String(data: $0, encoding: .utf8) } ?? "?"
    }
}
