import ArgumentParser
import CurbCore

@main
struct CurbEval: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "curbeval",
        abstract: "Read parking-sign photos and evaluate the CurbLens pipeline.",
        version: CurbCore.version
    )

    func run() throws {
        print("curbeval \(CurbCore.version) — subcommands arrive in Phase 3 (read) and Phase 7 (eval, ablate).")
    }
}
