import ArgumentParser
import CurbCore

@main
struct CurbEval: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "curbeval",
        abstract: "Read parking-sign photos and evaluate the CurbLens pipeline.",
        version: CurbCore.version,
        subcommands: [Read.self]
    )
}

/// Reader flags shared by `read` (and later `eval`).
struct ReaderFlags: ParsableArguments {
    @Flag(help: "Use Vision's fast recognition level instead of accurate.")
    var fast = false

    @Flag(name: .customLong("no-crop"), help: "Skip sign detection and perspective correction.")
    var noCrop = false

    @Flag(name: .customLong("no-lang-correction"), help: "Turn off Vision language correction.")
    var noLangCorrection = false

    @Flag(name: .customLong("no-fallback"), help: "Don't also read the whole image when the sign crop is small or empty.")
    var noFallback = false

    @Flag(name: .customLong("neural-engine"),
          help: "Use the Neural Engine instead of the CPU (first run after a rebuild can take ~30 s or fail).")
    var neuralEngine = false

    var options: ReaderOptions {
        ReaderOptions(level: fast ? .fast : .accurate, cropToSign: !noCrop, languageCorrection: !noLangCorrection,
                      fullImageFallback: !noFallback, preferCPU: !neuralEngine)
    }
}
