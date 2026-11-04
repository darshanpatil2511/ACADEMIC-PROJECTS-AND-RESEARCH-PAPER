import ArgumentParser
import CurbCore
import Foundation
import ImageIO

struct Read: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Read one sign photo and print what CurbLens understood.")

    @Argument(help: "Path to a JPEG/HEIC/PNG photo.")
    var path: String

    @OptionGroup var flags: ReaderFlags

    @Option(help: "Evaluate the verdict at this Boston time (yyyy-MM-dd'T'HH:mm) instead of now.")
    var at: String?

    @Option(name: .customLong("save-crop"), help: "Write the image OCR ran on (the corrected sign crop) to this PNG path.")
    var saveCrop: String?

    func run() async throws {
        let (image, orientation) = try ImageLoader.load(path: path)
        let reading = try await SignReader().read(image: image, orientation: orientation, options: flags.options)
        let calendar = Calendar.boston
        let now = try at.map { try BostonTime.parse($0) } ?? Date()

        print("== \(URL(fileURLWithPath: path).lastPathComponent)  (\(Int(reading.imageSize.width))×\(Int(reading.imageSize.height)), orientation \(orientation.rawValue))")
        print("options: \(flags.options.level.rawValue), crop \(flags.options.cropToSign ? "on" : "off"), language correction \(flags.options.languageCorrection ? "on" : "off"), \(flags.options.preferCPU ? "CPU" : "Neural Engine")")
        print("sign detected: \(reading.signQuad == nil ? "no / full image used" : "yes, cropped")\(reading.usedFullImageFallback ? " (full image read better than the crop)" : "")")

        print("\n-- OCR lines")
        for line in reading.lines.sorted(by: { $0.box.midY > $1.box.midY }) {
            print(String(format: "  %.2f  %@", line.confidence, line.text))
        }

        print("\n-- Panels")
        for (i, panel) in reading.panels.enumerated() { print("  [\(i + 1)] \(panel)") }

        print("\n-- Rules")
        if reading.parse.rules.isEmpty { print("  (none)") }
        for rule in reading.parse.rules { print("  • \(RuleDescriber.describe(rule))") }
        print(String(format: "  confidence %.2f", reading.parse.confidence))
        if !reading.parse.unparsedTokens.isEmpty { print("  unparsed: \(reading.parse.unparsedTokens.joined(separator: " "))") }
        if !reading.parse.normalizations.isEmpty { print("  fixes: \(reading.parse.normalizations.joined(separator: ", "))") }

        print("\n-- Verdict at \(BostonTime.format(now))")
        let verdict = RuleEngine.evaluate(rules: reading.parse.rules, arrival: now, calendar: calendar, permitZone: nil)
        print("  \(VerdictText.describe(verdict))")

        if let saveCrop {
            try ImageLoader.savePNG(reading.ocrImage, to: saveCrop)
            print("\nsaved OCR image (\(reading.ocrImage.width)×\(reading.ocrImage.height)) to \(saveCrop)")
        }

        print("\n-- Timing (ms)")
        let t = reading.timings
        print(String(format: "  detect %.1f · correct %.1f · ocr %.1f · group %.1f · parse %.1f · total %.1f",
                     t.detect, t.correct, t.ocr, t.group, t.parse, t.total))
    }
}

enum ImageLoader {
    struct LoadError: Error, CustomStringConvertible {
        var description: String
    }

    static func savePNG(_ image: CGImage, to path: String) throws {
        let url = URL(fileURLWithPath: path) as CFURL
        guard let dest = CGImageDestinationCreateWithURL(url, "public.png" as CFString, 1, nil) else {
            throw LoadError(description: "Couldn't write \(path)")
        }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { throw LoadError(description: "Couldn't write \(path)") }
    }

    /// Loads the first image in a file and its EXIF orientation.
    static func load(path: String) throws -> (CGImage, CGImagePropertyOrientation) {
        let url = URL(fileURLWithPath: path)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw LoadError(description: "Couldn't read an image from \(path)")
        }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let raw = (properties?[kCGImagePropertyOrientation] as? UInt32) ?? 1
        return (image, CGImagePropertyOrientation(rawValue: raw) ?? .up)
    }
}

enum BostonTime {
    static func parse(_ text: String) throws -> Date {
        let f = formatter()
        guard let date = f.date(from: text) else {
            throw ValidationError("Expected yyyy-MM-dd'T'HH:mm, got \(text)")
        }
        return date
    }

    static func format(_ date: Date) -> String {
        let f = formatter()
        f.dateFormat = "EEE yyyy-MM-dd HH:mm"
        return f.string(from: date)
    }

    private static func formatter() -> DateFormatter {
        let f = DateFormatter()
        f.calendar = Calendar.boston
        f.timeZone = Calendar.boston.timeZone
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm"
        return f
    }
}

enum VerdictText {
    static func describe(_ verdict: Verdict) -> String {
        switch verdict {
        case let .canPark(moveBy, notes):
            let deadline = moveBy.map { "move by \(BostonTime.format($0))" } ?? "no deadline in the next 8 days"
            return (["CAN PARK — \(deadline)"] + notes.map { "note: \($0)" }).joined(separator: "\n  ")
        case let .cannotPark(reason, allowedFrom):
            let from = allowedFrom.map { "allowed from \(BostonTime.format($0))" } ?? "not allowed in the next 8 days"
            return "CANNOT PARK — \(reason); \(from)"
        case let .unreadable(reason):
            return "UNREADABLE — \(reason)"
        }
    }
}
