import ArgumentParser
import CurbCore
import Foundation

enum SplitChoice: String, ExpressibleByArgument, CaseIterable {
    case dev, test, all

    func includes(_ split: EvalLabel.Split) -> Bool {
        self == .all || rawValue == split.rawValue
    }
}

/// Options shared by `eval` and `ablate`.
struct DatasetOptions: ParsableArguments {
    @Option(help: "Folder holding labels.json and the photos it names.")
    var dataset = "Dataset"

    @Option(help: "Folder to write reports into.")
    var out = "Reports"

    @Option(help: "Which labels to score: dev (tune on these), test (held out), or all.")
    var split: SplitChoice = .dev
}

struct Eval: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Score the pipeline on the labelled dataset and write Reports/eval_<time>.md and .json.")

    @OptionGroup var data: DatasetOptions
    @OptionGroup var flags: ReaderFlags

    func run() async throws {
        let labels = try EvalRunner.loadLabels(data)
        let stamp = Timestamp.now()
        let result = try await EvalRunner.run(labels: labels, data: data, options: flags.options, stamp: stamp)
        let base = URL(fileURLWithPath: data.out).appendingPathComponent("eval_\(stamp.file)")
        try EvalRunner.write(EvalReport.markdown(result), json: result, base: base)
        EvalRunner.printSummary(result)
        print("\nwrote \(base.path).md and .json")
    }
}

struct Ablate: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Run eval for the baseline and three ablations and write one comparison table.")

    @OptionGroup var data: DatasetOptions

    @Flag(name: .customLong("neural-engine"), help: "Use the Neural Engine instead of the CPU.")
    var neuralEngine = false

    func run() async throws {
        let labels = try EvalRunner.loadLabels(data)
        let stamp = Timestamp.now()
        let cpu = !neuralEngine
        let configs: [(String, ReaderOptions)] = [
            ("baseline (accurate + crop + lang-correction)", ReaderOptions(preferCPU: cpu)),
            ("no crop", ReaderOptions(cropToSign: false, preferCPU: cpu)),
            ("no language correction", ReaderOptions(languageCorrection: false, preferCPU: cpu)),
            ("fast mode", ReaderOptions(level: .fast, preferCPU: cpu)),
        ]
        var results: [EvalResult] = []
        for (name, options) in configs {
            print("\n=== \(name)")
            var result = try await EvalRunner.run(labels: labels, data: data, options: options, stamp: stamp)
            result.config = name
            results.append(result)
        }
        let base = URL(fileURLWithPath: data.out).appendingPathComponent("ablation_\(stamp.file)")
        try EvalRunner.write(EvalReport.ablationMarkdown(results, generatedAt: stamp.display), json: results, base: base)
        print("\n" + EvalReport.ablationMarkdown(results, generatedAt: stamp.display))
        print("wrote \(base.path).md and .json")
    }
}

enum EvalRunner {
    static func loadLabels(_ data: DatasetOptions) throws -> [EvalLabel] {
        let url = URL(fileURLWithPath: data.dataset).appendingPathComponent("labels.json")
        guard let raw = try? Data(contentsOf: url) else {
            throw ValidationError("No labels at \(url.path). See Dataset/README.md for the format.")
        }
        let all = try EvalLabel.decodeList(raw)
        let problems = try all.flatMap { try EvalScorer.labelProblems($0, calendar: .boston) }
        if !problems.isEmpty {
            throw ValidationError("Fix these labels first (their checks contradict their own rules):\n  "
                                  + problems.joined(separator: "\n  "))
        }
        let chosen = all.filter { data.split.includes($0.split) }
        guard !chosen.isEmpty else { throw ValidationError("No labels in split \"\(data.split.rawValue)\".") }
        if data.split != .dev {
            print("note: scoring held-out photos. Don't tune the parser on these failures.")
        }
        return chosen
    }

    /// Reads the first photo once to warm Vision up (the first read loads models and can take seconds,
    /// which would skew p95), then reads and scores every photo.
    static func run(labels: [EvalLabel], data: DatasetOptions, options: ReaderOptions,
                    stamp: Timestamp) async throws -> EvalResult {
        let reader = SignReader()
        let folder = URL(fileURLWithPath: data.dataset)
        if let first = labels.first, let (image, orientation) = try? ImageLoader.load(path: folder.appendingPathComponent(first.image).path) {
            _ = try? await reader.read(image: image, orientation: orientation, options: options)
        }
        var scores: [ImageScore] = []
        for (index, label) in labels.enumerated() {
            let summary: ReadingSummary
            do {
                let (image, orientation) = try ImageLoader.load(path: folder.appendingPathComponent(label.image).path)
                summary = ReadingSummary(try await reader.read(image: image, orientation: orientation, options: options))
            } catch {
                summary = ReadingSummary(detected: false, panels: [], rules: [], timings: nil, error: "\(error)")
            }
            let score = try EvalScorer.score(label: label, reading: summary, calendar: .boston)
            scores.append(score)
            let mark = score.error != nil ? "ERR" : (score.exactMatch ? "ok " : "-- ")
            print(String(format: "[%3d/%d] %@ %@  checks %d/%d", index + 1, labels.count, mark, label.image,
                         score.checksPassed, score.checksTotal))
        }
        let errors = scores.filter { $0.error != nil }.count
        if errors > 0 {
            print("\nWARNING: \(errors) of \(scores.count) photos failed to read; they count as failures. "
                  + "If every photo fails with e5rtError, Vision's model service is stuck: wait a minute or restart the Mac, then rerun.")
        }
        return EvalResult(config: options.summary, split: data.split.rawValue, generatedAt: stamp.display, scores: scores)
    }

    static func write<T: Encodable>(_ markdown: String, json: T, base: URL) throws {
        try FileManager.default.createDirectory(at: base.deletingLastPathComponent(), withIntermediateDirectories: true)
        try markdown.write(to: base.appendingPathExtension("md"), atomically: true, encoding: .utf8)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(json).write(to: base.appendingPathExtension("json"))
    }

    static func printSummary(_ result: EvalResult) {
        let md = EvalReport.markdown(result)
        // The summary table is everything before the failure list.
        print("\n" + (md.components(separatedBy: "\n## Failures").first ?? md))
    }
}

/// One timestamp per run, used in file names and report headers.
struct Timestamp {
    let file: String
    let display: String

    static func now() -> Timestamp {
        let date = Date()
        func format(_ pattern: String) -> String {
            let f = DateFormatter()
            f.calendar = .boston
            f.timeZone = Calendar.boston.timeZone
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = pattern
            return f.string(from: date)
        }
        return Timestamp(file: format("yyyyMMdd-HHmmss"), display: format("yyyy-MM-dd HH:mm zzz"))
    }
}
