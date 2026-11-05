import Foundation
import Testing
@testable import CurbCore

private let cal = Calendar.boston
private func t(_ h: Int, _ m: Int = 0) -> TimeOfDay { TimeOfDay(hour: h, minute: m) }

/// "2 HOUR PARKING 8AM-8PM EXCEPT SUNDAY"
private let twoHour = ParkingRule(kind: .timeLimit(minutes: 120), days: .days([.mon, .tue, .wed, .thu, .fri, .sat]),
                                  window: TimeWindow(start: t(8), end: t(20)), season: nil, towZone: false,
                                  sourceText: "2 HOUR PARKING 8AM-8PM EXCEPT SUNDAY")
/// "TOW ZONE STREET CLEANING TUESDAY 12:01AM-7AM"
private let cleaning = ParkingRule(kind: .streetCleaning, days: .days([.tue]),
                                   window: TimeWindow(start: t(0, 1), end: t(7)), season: nil, towZone: true,
                                   sourceText: "TOW ZONE STREET CLEANING TUESDAY 12:01AM-7AM")

private func label(rules: [ParkingRule], checks: [EvalCheck] = [], transcript: String = "",
                   conditions: [String] = []) -> EvalLabel {
    EvalLabel(image: "x.jpg", split: .dev, conditions: conditions, transcript: transcript, rules: rules, checks: checks)
}

private func reading(rules: [ParkingRule], panels: [String] = [], detected: Bool = true,
                     total: Double = 100) -> ReadingSummary {
    var timings = StageTimings()
    timings.total = total
    timings.ocr = total / 2
    return ReadingSummary(detected: detected, panels: panels, rules: rules, timings: timings, error: nil)
}

@Suite("Eval metrics")
struct EvalMetricsTests {
    @Test func levenshtein() {
        #expect(EvalMetrics.editDistance("KITTEN", "SITTING") == 3)
        #expect(EvalMetrics.editDistance("", "ABC") == 3)
        #expect(EvalMetrics.editDistance("SAME", "SAME") == 0)
    }

    @Test func characterErrorRateIgnoresSeparatorsSpacesAndCase() {
        #expect(EvalMetrics.characterErrorRate(expected: "NO PARKING | TOW ZONE", got: "no parking tow zone") == 0)
        // "2 HOUR" read as "2 HOIR": 1 substitution over 5 characters ("2HOUR").
        #expect(EvalMetrics.characterErrorRate(expected: "2 HOUR", got: "2 HOIR") == 0.2)
        #expect(EvalMetrics.characterErrorRate(expected: "", got: "ANY") == nil)
    }

    @Test func exactMatchIsOrderIndependentAndIgnoresSourceText() {
        var copy = cleaning
        copy.sourceText = "different OCR text"
        #expect(EvalMetrics.rulesMatchExactly(expected: [twoHour, cleaning], got: [copy, twoHour]))
        #expect(!EvalMetrics.rulesMatchExactly(expected: [twoHour, cleaning], got: [twoHour]))
        // Two identical signs on one pole ("NO PARKING ANY TIME" twice) mean the same thing as one.
        #expect(EvalMetrics.rulesMatchExactly(expected: [twoHour], got: [twoHour, twoHour]))
    }

    @Test func fieldHitsPairEachExpectedRuleWithItsClosestGuess() {
        var wrongWindow = twoHour
        wrongWindow.window = TimeWindow(start: t(8), end: t(18))
        let hits = EvalMetrics.fieldHits(expected: [twoHour, cleaning], got: [wrongWindow])
        // twoHour pairs with wrongWindow (4 of 5 fields right); cleaning has nothing left to pair with.
        #expect(hits[.kind] == 1 && hits[.days] == 1 && hits[.season] == 1 && hits[.towZone] == 1)
        #expect(hits[.window] == 0)
    }

    @Test func percentilesInterpolate() {
        let values: [Double] = [10, 20, 30, 40, 50]
        #expect(EvalMetrics.percentile(values, 50) == 30)
        #expect(EvalMetrics.percentile(values, 95) == 48)
        #expect(EvalMetrics.percentile([7], 95) == 7)
        #expect(EvalMetrics.percentile([], 50) == 0)
        let stats = LatencyStats(values)
        #expect(stats.p50 == 30 && stats.mean == 30 && stats.count == 5)
    }
}

@Suite("Eval scoring")
struct EvalScorerTests {
    private let checks = [
        EvalCheck(at: "2026-11-10T03:00", expect: .cannotPark),   // Tue: street cleaning
        EvalCheck(at: "2026-11-04T10:00", expect: .canPark),      // Wed: 2-hour limit
    ]

    @Test func perfectReadingScoresFull() throws {
        let l = label(rules: [twoHour, cleaning], checks: checks, transcript: "2 HOUR PARKING | STREET CLEANING")
        let score = try EvalScorer.score(label: l, reading: reading(rules: [cleaning, twoHour],
                                                                  panels: ["2 HOUR PARKING", "STREET CLEANING"]),
                                         calendar: cal)
        #expect(score.exactMatch && score.detected && score.cer == 0)
        #expect(score.checksPassed == 2 && score.checksTotal == 2 && score.failedChecks.isEmpty)
        #expect(score.extraRules == 0)
    }

    @Test func missingRuleFailsTheCheckItGoverns() throws {
        let l = label(rules: [twoHour, cleaning], checks: checks)
        let score = try EvalScorer.score(label: l, reading: reading(rules: [twoHour]), calendar: cal)
        #expect(!score.exactMatch)
        #expect(score.checksPassed == 1)
        #expect(score.failedChecks == ["2026-11-10T03:00: expected cannotPark, got canPark"])
    }

    @Test func readErrorScoresAsNothingRead() throws {
        let l = label(rules: [twoHour], checks: [EvalCheck(at: "2026-11-04T10:00", expect: .canPark)])
        let failed = ReadingSummary(detected: false, panels: [], rules: [], timings: nil, error: "boom")
        let score = try EvalScorer.score(label: l, reading: failed, calendar: cal)
        #expect(score.error == "boom" && !score.exactMatch && score.checksPassed == 0)
    }

    @Test func readErrorNeverPassesEvenWhenNothingIsExpected() throws {
        // A private-lot sign labelled with no rules: an error also yields no rules, but must not count as a pass.
        let l = label(rules: [], checks: [EvalCheck(at: "2026-11-04T10:00", expect: .unreadable)])
        let failed = ReadingSummary(detected: false, panels: [], rules: [], timings: nil, error: "boom")
        let score = try EvalScorer.score(label: l, reading: failed, calendar: cal)
        #expect(!score.exactMatch && score.checksPassed == 0)
        #expect(score.failedChecks == ["2026-11-04T10:00: read error"])
    }

    @Test func labelProblemsCatchChecksTheLabelledRulesContradict() throws {
        let bad = label(rules: [twoHour], checks: [EvalCheck(at: "2026-11-04T10:00", expect: .cannotPark)])
        #expect(try EvalScorer.labelProblems(bad, calendar: cal) ==
                ["x.jpg: check 2026-11-04T10:00 expects cannotPark but the labelled rules give canPark"])
        #expect(try EvalScorer.labelProblems(label(rules: [twoHour, cleaning], checks: checks), calendar: cal).isEmpty)
        #expect(throws: (any Error).self) {
            try EvalScorer.labelProblems(label(rules: [], checks: [EvalCheck(at: "Nov 4", expect: .canPark)]), calendar: cal)
        }
    }
}

@Suite("Eval summary and reports")
struct EvalSummaryTests {
    @Test func summaryAggregatesAndSplitsByCondition() throws {
        let check = EvalCheck(at: "2026-11-04T10:00", expect: .canPark)
        let good = try EvalScorer.score(label: label(rules: [twoHour], checks: [check], conditions: ["angle"]),
                                        reading: reading(rules: [twoHour], total: 100), calendar: cal)
        let bad = try EvalScorer.score(label: label(rules: [twoHour], checks: [check], conditions: ["angle", "dusk"]),
                                       reading: reading(rules: [], detected: false, total: 300), calendar: cal)
        let summary = EvalSummary(scores: [good, bad])
        #expect(summary.images == 2)
        #expect(summary.ruleExactMatchRate == 0.5)
        #expect(summary.signDetectedRate == 0.5)
        #expect(summary.fullImageFallbacks == 0)
        #expect(summary.verdictAccuracy == 0.5)
        #expect(summary.fieldAccuracy["kind"] == 0.5)
        #expect(summary.latency["total"]?.p50 == 200)

        let byCondition = EvalSummary.byCondition([good, bad])
        #expect(byCondition["angle"]?.images == 2)
        #expect(byCondition["dusk"]?.images == 1 && byCondition["dusk"]?.ruleExactMatchRate == 0)
    }

    @Test func labelsDecodeFromTheDatasetFormat() throws {
        let json = """
        [{"image": "IMG_1.jpg", "split": "test", "conditions": ["angle"],
          "transcript": "2 HOUR PARKING | 8AM-8PM | EXCEPT SUNDAY",
          "rules": [{"kind": {"type": "timeLimit", "minutes": 120}, "days": {"days": ["MON","TUE","WED","THU","FRI","SAT"]},
                     "window": {"start": "08:00", "end": "20:00"}}],
          "checks": [{"at": "2026-11-04T10:00", "expect": "canPark"}]}]
        """
        let labels = try EvalLabel.decodeList(Data(json.utf8))
        #expect(labels.count == 1 && labels[0].split == .test && labels[0].rules[0].withoutSource == twoHour.withoutSource)
    }

    @Test func markdownReportListsMetricsAndFailures() throws {
        let check = EvalCheck(at: "2026-11-04T10:00", expect: .canPark)
        let bad = try EvalScorer.score(label: label(rules: [twoHour], checks: [check]),
                                       reading: reading(rules: []), calendar: cal)
        let result = EvalResult(config: "accurate · crop", split: "dev", generatedAt: "2026-11-04 12:00",
                                scores: [bad])
        let md = EvalReport.markdown(result)
        #expect(md.contains("| Rule exact match | 0% (0/1) |"))
        #expect(md.contains("### x.jpg"))
        #expect(md.contains("expected cannotPark") == false)
        #expect(md.contains("2-hour parking 8:00 AM–8:00 PM Mon–Sat"))

        let table = EvalReport.ablationMarkdown([result, result], generatedAt: "2026-11-04 12:00")
        #expect(table.components(separatedBy: "| accurate · crop |").count == 3)
    }
}
