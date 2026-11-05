import Foundation

/// The rule fields scored separately ("field accuracy").
public enum RuleField: String, CaseIterable, Codable, Sendable {
    case kind, days, window, season, towZone

    func matches(_ a: ParkingRule, _ b: ParkingRule) -> Bool {
        switch self {
        case .kind: return a.kind == b.kind
        case .days: return a.days == b.days
        case .window: return a.window == b.window
        case .season: return a.season == b.season
        case .towZone: return a.towZone == b.towZone
        }
    }
}

/// Pure scoring functions used by `curbeval eval`.
public enum EvalMetrics {
    /// Levenshtein distance over characters.
    public static func editDistance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var previous = Array(0...b.count)
        var current = Array(repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            current[0] = i
            for j in 1...b.count {
                let substitution = previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1)
                current[j] = min(previous[j] + 1, current[j - 1] + 1, substitution)
            }
            swap(&previous, &current)
        }
        return previous[b.count]
    }

    /// Uppercased, with whitespace and the "|" panel separators removed.
    public static func normalizeTranscript(_ text: String) -> String {
        String(text.uppercased().filter { !$0.isWhitespace && $0 != "|" })
    }

    /// Edit distance divided by the expected length, after `normalizeTranscript`. Nil when there is no transcript.
    /// Can exceed 1 when the OCR reads lots of extra text.
    public static func characterErrorRate(expected: String, got: String) -> Double? {
        let truth = normalizeTranscript(expected)
        guard !truth.isEmpty else { return nil }
        return Double(editDistance(truth, normalizeTranscript(got))) / Double(truth.count)
    }

    /// Same rules (ignoring where the text came from), in any order, with the same multiplicity.
    public static func rulesMatchExactly(expected: [ParkingRule], got: [ParkingRule]) -> Bool {
        counts(expected) == counts(got)
    }

    private static func counts(_ rules: [ParkingRule]) -> [ParkingRule: Int] {
        rules.reduce(into: [:]) { $0[$1.withoutSource, default: 0] += 1 }
    }

    /// For each field, how many expected rules got it right. Each expected rule is paired with the unused
    /// predicted rule that matches it on the most fields; expected rules left without a partner score 0.
    public static func fieldHits(expected: [ParkingRule], got: [ParkingRule]) -> [RuleField: Int] {
        var hits = Dictionary(uniqueKeysWithValues: RuleField.allCases.map { ($0, 0) })
        var unused = got
        for rule in expected {
            guard let best = unused.indices.max(by: { matchCount(rule, unused[$0]) < matchCount(rule, unused[$1]) })
            else { break }
            let partner = unused.remove(at: best)
            for field in RuleField.allCases where field.matches(rule, partner) { hits[field, default: 0] += 1 }
        }
        return hits
    }

    private static func matchCount(_ a: ParkingRule, _ b: ParkingRule) -> Int {
        RuleField.allCases.filter { $0.matches(a, b) }.count
    }

    /// Linear-interpolated percentile (p in 0...100). 0 for no values.
    public static func percentile(_ values: [Double], _ p: Double) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let rank = p / 100 * Double(sorted.count - 1)
        let low = Int(rank.rounded(.down)), high = Int(rank.rounded(.up))
        return sorted[low] + (sorted[high] - sorted[low]) * (rank - Double(low))
    }
}

/// p50 / p95 / mean of a set of latencies in milliseconds.
public struct LatencyStats: Codable, Hashable, Sendable {
    public var p50: Double
    public var p95: Double
    public var mean: Double
    public var count: Int

    public init(_ values: [Double]) {
        p50 = EvalMetrics.percentile(values, 50)
        p95 = EvalMetrics.percentile(values, 95)
        mean = values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
        count = values.count
    }
}

extension StageTimings {
    /// Stage name and value, in pipeline order (used by reports and the on-device benchmark).
    public var stages: [(name: String, ms: Double)] {
        [("detect", detect), ("correct", correct), ("ocr", ocr), ("group", group), ("parse", parse), ("total", total)]
    }
}

extension ReaderOptions {
    /// e.g. "accurate · crop · lang-correction · fallback"
    public var summary: String {
        var parts = [level.rawValue]
        parts.append(cropToSign ? "crop" : "no crop")
        parts.append(languageCorrection ? "lang-correction" : "no lang-correction")
        if cropToSign { parts.append(fullImageFallback ? "fallback" : "no fallback") }
        return parts.joined(separator: " · ")
    }
}
