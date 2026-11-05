import CurbCore
import Observation
import SwiftUI
import UIKit

/// On-device latency benchmark: every photo in App/Resources/BenchImages, read 3 times with the accurate
/// reader (Neural Engine), reporting p50/p95 per stage and the device model. Results can be shared as text.
struct BenchmarkView: View {
    @State private var model = BenchmarkModel()

    var body: some View {
        List {
            Section {
                LabeledContent("Device", value: model.device)
                LabeledContent("Photos", value: "\(model.imageURLs.count) × \(BenchmarkModel.runsPerImage) runs")
                Button {
                    Task { await model.run() }
                } label: {
                    Label(model.running ? "Running…" : "Run on-device benchmark", systemImage: "gauge.with.dots.needle.67percent")
                }
                .disabled(model.running || model.imageURLs.isEmpty)
                if model.running {
                    ProgressView(value: model.progress)
                }
                if model.imageURLs.isEmpty {
                    Text("Add photos to App/Resources/BenchImages and rebuild.").foregroundStyle(.secondary)
                }
                if let error = model.error {
                    Text(error).foregroundStyle(.red)
                }
            }
            if let result = model.result {
                Section("Latency (ms)") {
                    Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                        GridRow {
                            Text("Stage").bold()
                            Text("p50").bold()
                            Text("p95").bold()
                            Text("mean").bold()
                        }
                        ForEach(result.stages, id: \.name) { stage in
                            GridRow {
                                Text(stage.name)
                                Text(Self.ms(stage.stats.p50))
                                Text(Self.ms(stage.stats.p95))
                                Text(Self.ms(stage.stats.mean))
                            }
                            .fontWeight(stage.name == "total" ? .semibold : .regular)
                        }
                    }
                    .font(.callout.monospacedDigit())
                    LabeledContent("First read (cold, not counted)", value: Self.ms(result.coldMilliseconds) + " ms")
                }
                Section {
                    ShareLink(item: result.text) { Label("Share results", systemImage: "square.and.arrow.up") }
                }
            }
        }
        .navigationTitle("Benchmark")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            #if DEBUG
            // Debug aid: `-CurbLensRunBenchmark YES` starts the run on appear (simulator screenshots).
            if UserDefaults.standard.bool(forKey: "CurbLensRunBenchmark"), model.result == nil { await model.run() }
            #endif
        }
    }

    static func ms(_ value: Double) -> String { String(format: "%.0f", value) }
}

struct BenchmarkResult {
    var device: String
    var photos: Int
    var runs: Int
    var coldMilliseconds: Double
    var stages: [(name: String, stats: LatencyStats)]

    /// Plain-text report for sharing.
    var text: String {
        var lines = ["CurbLens on-device benchmark",
                     "\(device) · \(photos) photos × \(runs) runs · accurate OCR, crop on",
                     "First read (cold, not counted): \(BenchmarkView.ms(coldMilliseconds)) ms",
                     "",
                     "| Stage | p50 ms | p95 ms | mean ms |",
                     "|---|---|---|---|"]
        for stage in stages {
            lines.append("| \(stage.name) | \(BenchmarkView.ms(stage.stats.p50)) | \(BenchmarkView.ms(stage.stats.p95)) | \(BenchmarkView.ms(stage.stats.mean)) |")
        }
        return lines.joined(separator: "\n")
    }
}

@MainActor
@Observable
final class BenchmarkModel {
    static let runsPerImage = 3

    var running = false
    var progress = 0.0
    var result: BenchmarkResult?
    var error: String?

    let imageURLs: [URL] = {
        guard let folder = Bundle.main.url(forResource: "BenchImages", withExtension: nil),
              let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else {
            return []
        }
        let types: Set<String> = ["jpg", "jpeg", "png", "heic"]
        return files.filter { types.contains($0.pathExtension.lowercased()) }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }()

    /// e.g. "iPhone18,1 · iOS 27.0"
    let device: String = {
        var info = utsname()
        uname(&info)
        let machine = withUnsafeBytes(of: &info.machine) { raw in
            String(decoding: raw.prefix(while: { $0 != 0 }), as: UTF8.self)
        }
        return "\(machine) · iOS \(UIDevice.current.systemVersion)"
    }()

    func run() async {
        guard !running, let first = imageURLs.first else { return }
        running = true
        progress = 0
        error = nil
        defer { running = false }

        let urls = imageURLs
        let runs = Self.runsPerImage
        let reader = SignReader()
        do {
            // Cold read: loads Vision's models. Reported separately so it doesn't skew p95.
            let cold = try await Self.read(first, reader: reader).total
            var timings: [StageTimings] = []
            let steps = Double(urls.count * runs)
            for run in 0..<runs {
                for (index, url) in urls.enumerated() {
                    timings.append(try await Self.read(url, reader: reader))
                    progress = Double(run * urls.count + index + 1) / steps
                }
            }
            let stages = StageTimings().stages.map { stage in
                (name: stage.name, stats: LatencyStats(timings.map { t in t.stages.first { $0.name == stage.name }?.ms ?? 0 }))
            }
            result = BenchmarkResult(device: device, photos: urls.count, runs: runs, coldMilliseconds: cold, stages: stages)
            #if DEBUG
            print("[CurbLens] benchmark\n\(result?.text ?? "")")
            #endif
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Decodes and reads one photo off the main actor.
    private nonisolated static func read(_ url: URL, reader: SignReader) async throws -> StageTimings {
        try await Task.detached(priority: .userInitiated) {
            let (image, orientation) = try ImageDecoding.decode(url: url)
            return try await reader.read(image: image, orientation: orientation, options: .accurate).timings
        }.value
    }
}
