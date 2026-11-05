import Foundation

/// Markdown renderings of eval results (Reports/eval_*.md and Reports/ablation_*.md).
public enum EvalReport {
    public static func markdown(_ result: EvalResult) -> String {
        let s = result.overall
        var out: [String] = []
        out.append("# CurbLens eval: \(result.config)")
        out.append("")
        out.append("Generated \(result.generatedAt) · split **\(result.split)** · \(s.images) images"
                   + (s.readErrors > 0 ? " · \(s.readErrors) read errors" : ""))
        out.append("")
        out.append("| Metric | Value |")
        out.append("|---|---|")
        out.append("| Sign rectangle found | \(percent(s.signDetectedRate)) (\(s.signsDetected)/\(s.images)) |")
        out.append("| Full image read better than crop | \(s.fullImageFallbacks)/\(s.images) |")
        out.append("| OCR character error rate | \(String(format: "%.3f", s.meanCER)) |")
        out.append("| Rule exact match | \(percent(s.ruleExactMatchRate)) (\(s.exactMatches)/\(s.images)) |")
        for field in RuleField.allCases {
            out.append("| Field accuracy: \(field.rawValue) | \(percent(s.fieldAccuracy[field.rawValue] ?? 0)) |")
        }
        out.append("| Verdict accuracy | \(percent(s.verdictAccuracy)) (\(s.checksPassed)/\(s.checksTotal) checks) |")
        out.append("| Extra rules per image | \(String(format: "%.2f", s.extraRulesPerImage)) |")
        out.append("")
        out.append("## Latency (ms, after one warm-up read)")
        out.append("")
        out.append("| Stage | p50 | p95 | mean |")
        out.append("|---|---|---|---|")
        for stage in StageTimings().stages.map(\.name) {
            let l = s.latency[stage] ?? LatencyStats([])
            out.append("| \(stage) | \(ms(l.p50)) | \(ms(l.p95)) | \(ms(l.mean)) |")
        }
        if !result.byCondition.isEmpty {
            out.append("")
            out.append("## By condition")
            out.append("")
            out.append("| Condition | Images | Detected | CER | Exact match | Verdict |")
            out.append("|---|---|---|---|---|---|")
            for (tag, c) in result.byCondition.sorted(by: { $0.key < $1.key }) {
                out.append("| \(tag) | \(c.images) | \(percent(c.signDetectedRate)) | \(String(format: "%.3f", c.meanCER)) | "
                           + "\(percent(c.ruleExactMatchRate)) | \(percent(c.verdictAccuracy)) |")
            }
        }
        let failures = result.images.filter { !$0.exactMatch || !$0.failedChecks.isEmpty || $0.error != nil }
        out.append("")
        out.append("## Failures (\(failures.count))")
        for score in failures {
            out.append("")
            out.append("### \(score.image)" + (score.conditions.isEmpty ? "" : " (\(score.conditions.joined(separator: ", ")))"))
            if let error = score.error { out.append("- **read error:** \(error)") }
            out.append("- expected: " + list(score.expectedRules))
            out.append("- got: " + list(score.gotRules))
            for failed in score.failedChecks { out.append("- failed check: \(failed)") }
            out.append("- OCR: `\(score.gotTranscript.isEmpty ? "(nothing)" : score.gotTranscript)`"
                       + (score.cer.map { String(format: " (CER %.3f)", $0) } ?? ""))
        }
        return out.joined(separator: "\n") + "\n"
    }

    /// One row per configuration, for comparing ablations.
    public static func ablationMarkdown(_ results: [EvalResult], generatedAt: String) -> String {
        var out = ["# CurbLens ablation", ""]
        out.append("Generated \(generatedAt) · split **\(results.first?.split ?? "-")** · \(results.first?.overall.images ?? 0) images")
        out.append("")
        out.append("| Config | Exact match | Verdict | CER | Detected | kind | days | window | p50 total ms | p95 total ms |")
        out.append("|---|---|---|---|---|---|---|---|---|---|")
        for r in results {
            let s = r.overall
            let total = s.latency["total"] ?? LatencyStats([])
            out.append("| \(r.config) | \(percent(s.ruleExactMatchRate)) | \(percent(s.verdictAccuracy)) | "
                       + "\(String(format: "%.3f", s.meanCER)) | \(percent(s.signDetectedRate)) | "
                       + "\(percent(s.fieldAccuracy["kind"] ?? 0)) | \(percent(s.fieldAccuracy["days"] ?? 0)) | "
                       + "\(percent(s.fieldAccuracy["window"] ?? 0)) | \(ms(total.p50)) | \(ms(total.p95)) |")
        }
        return out.joined(separator: "\n") + "\n"
    }

    private static func percent(_ value: Double) -> String { "\(Int((value * 100).rounded()))%" }
    private static func ms(_ value: Double) -> String { String(format: "%.0f", value) }
    private static func list(_ rules: [String]) -> String { rules.isEmpty ? "(none)" : rules.joined(separator: "; ") }
}
