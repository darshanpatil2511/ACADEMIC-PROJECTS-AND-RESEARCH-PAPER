import Foundation

/// What the pipeline produced for one photo, independent of Vision types so scoring is unit-testable.
public struct ReadingSummary: Sendable {
    /// A sign rectangle was found (even if the full-image read then beat the crop).
    public var detected: Bool
    /// The whole image read better than the sign crop.
    public var usedFallback: Bool
    public var panels: [String]
    public var rules: [ParkingRule]
    /// nil when the read failed.
    public var timings: StageTimings?
    public var error: String?

    public init(detected: Bool, usedFallback: Bool = false, panels: [String], rules: [ParkingRule],
                timings: StageTimings?, error: String?) {
        self.detected = detected
        self.usedFallback = usedFallback
        self.panels = panels
        self.rules = rules
        self.timings = timings
        self.error = error
    }

    public init(_ reading: SignReading) {
        // The reader drops `signQuad` when the full-image fallback wins, but a rectangle was still found.
        self.init(detected: reading.signQuad != nil || reading.usedFullImageFallback,
                  usedFallback: reading.usedFullImageFallback, panels: reading.panels, rules: reading.parse.rules,
                  timings: reading.timings, error: nil)
    }
}

/// The score for one photo.
public struct ImageScore: Codable, Hashable, Sendable {
    public var image: String
    public var split: EvalLabel.Split
    public var conditions: [String]
    public var detected: Bool
    public var usedFallback: Bool
    /// Character error rate vs. the transcript; nil without a transcript.
    public var cer: Double?
    public var exactMatch: Bool
    /// Field name -> expected rules with that field right.
    public var fieldHits: [String: Int]
    public var expectedRuleCount: Int
    public var gotRuleCount: Int
    /// Predicted rules beyond the number expected.
    public var extraRules: Int
    public var checksPassed: Int
    public var checksTotal: Int
    /// "2026-11-10T03:00: expected cannotPark, got canPark"
    public var failedChecks: [String]
    public var expectedRules: [String]
    public var gotRules: [String]
    public var gotTranscript: String
    public var timings: StageTimings?
    public var error: String?
}

/// Scores one reading against its label.
public enum EvalScorer {
    public static func score(label: EvalLabel, reading: ReadingSummary, calendar: Calendar) throws -> ImageScore {
        var passed = 0
        var failed: [String] = []
        for check in label.checks {
            let verdict = RuleEngine.evaluate(rules: reading.rules, arrival: try check.date(calendar: calendar),
                                              calendar: calendar, permitZone: nil)
            let got = VerdictKind(verdict)
            if got == check.expect {
                passed += 1
            } else {
                failed.append("\(check.at): expected \(check.expect.rawValue), got \(got.rawValue)")
            }
        }
        let transcript = reading.panels.joined(separator: " | ")
        let hits = EvalMetrics.fieldHits(expected: label.rules, got: reading.rules)
        return ImageScore(
            image: label.image, split: label.split, conditions: label.conditions,
            detected: reading.detected, usedFallback: reading.usedFallback,
            cer: EvalMetrics.characterErrorRate(expected: label.transcript, got: transcript),
            exactMatch: EvalMetrics.rulesMatchExactly(expected: label.rules, got: reading.rules),
            fieldHits: Dictionary(uniqueKeysWithValues: hits.map { ($0.key.rawValue, $0.value) }),
            expectedRuleCount: label.rules.count, gotRuleCount: reading.rules.count,
            extraRules: max(0, reading.rules.count - label.rules.count),
            checksPassed: passed, checksTotal: label.checks.count, failedChecks: failed,
            expectedRules: label.rules.map(RuleDescriber.describe), gotRules: reading.rules.map(RuleDescriber.describe),
            gotTranscript: transcript, timings: reading.timings, error: reading.error)
    }

    /// Checks whose expected verdict the label's own rules don't produce: a typo in the label, not a reader
    /// failure. Throws on a malformed check time.
    public static func labelProblems(_ label: EvalLabel, calendar: Calendar) throws -> [String] {
        try label.checks.compactMap { check in
            let verdict = RuleEngine.evaluate(rules: label.rules, arrival: try check.date(calendar: calendar),
                                              calendar: calendar, permitZone: nil)
            let got = VerdictKind(verdict)
            guard got != check.expect else { return nil }
            return "\(label.image): check \(check.at) expects \(check.expect.rawValue) but the labelled rules give \(got.rawValue)"
        }
    }
}

/// Aggregate metrics over a set of photos.
public struct EvalSummary: Codable, Hashable, Sendable {
    public var images: Int
    public var readErrors: Int
    public var signsDetected: Int
    public var signDetectedRate: Double
    /// Photos where the whole image read better than the sign crop.
    public var fullImageFallbacks: Int
    /// Mean CER over photos with a transcript.
    public var meanCER: Double
    public var exactMatches: Int
    public var ruleExactMatchRate: Double
    /// Field name -> fraction of expected rules with that field right.
    public var fieldAccuracy: [String: Double]
    public var checksPassed: Int
    public var checksTotal: Int
    public var verdictAccuracy: Double
    public var extraRulesPerImage: Double
    /// Stage name -> latency over successful reads.
    public var latency: [String: LatencyStats]

    public init(scores: [ImageScore]) {
        func rate(_ part: Int, _ whole: Int) -> Double { whole == 0 ? 0 : Double(part) / Double(whole) }
        images = scores.count
        readErrors = scores.filter { $0.error != nil }.count
        signsDetected = scores.filter(\.detected).count
        signDetectedRate = rate(signsDetected, images)
        fullImageFallbacks = scores.filter(\.usedFallback).count
        let cers = scores.compactMap(\.cer)
        meanCER = cers.isEmpty ? 0 : cers.reduce(0, +) / Double(cers.count)
        exactMatches = scores.filter(\.exactMatch).count
        ruleExactMatchRate = rate(exactMatches, images)
        let expectedRules = scores.map(\.expectedRuleCount).reduce(0, +)
        fieldAccuracy = Dictionary(uniqueKeysWithValues: RuleField.allCases.map { field in
            (field.rawValue, rate(scores.map { $0.fieldHits[field.rawValue] ?? 0 }.reduce(0, +), expectedRules))
        })
        checksPassed = scores.map(\.checksPassed).reduce(0, +)
        checksTotal = scores.map(\.checksTotal).reduce(0, +)
        verdictAccuracy = rate(checksPassed, checksTotal)
        extraRulesPerImage = images == 0 ? 0 : Double(scores.map(\.extraRules).reduce(0, +)) / Double(images)
        let timings = scores.compactMap(\.timings)
        latency = Dictionary(uniqueKeysWithValues: StageTimings().stages.map { stage in
            (stage.name, LatencyStats(timings.map { t in t.stages.first { $0.name == stage.name }?.ms ?? 0 }))
        })
    }

    /// One summary per condition tag.
    public static func byCondition(_ scores: [ImageScore]) -> [String: EvalSummary] {
        let tags = Set(scores.flatMap(\.conditions))
        return Dictionary(uniqueKeysWithValues: tags.map { tag in
            (tag, EvalSummary(scores: scores.filter { $0.conditions.contains(tag) }))
        })
    }
}

/// Everything one eval run produced; written to Reports/ as JSON.
public struct EvalResult: Codable, Hashable, Sendable {
    public var config: String
    public var split: String
    public var generatedAt: String
    public var overall: EvalSummary
    public var byCondition: [String: EvalSummary]
    public var images: [ImageScore]

    public init(config: String, split: String, generatedAt: String, scores: [ImageScore]) {
        self.config = config
        self.split = split
        self.generatedAt = generatedAt
        self.overall = EvalSummary(scores: scores)
        self.byCondition = EvalSummary.byCondition(scores)
        self.images = scores
    }
}
