import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import CoreML
import Foundation
import ImageIO
import Vision

/// Options for one read. Defaults are the high-accuracy configuration.
public struct ReaderOptions: Sendable, Hashable {
    public enum Level: String, Sendable, Hashable, CaseIterable {
        case accurate, fast
    }

    public var level: Level
    /// Detect the sign rectangle and perspective-correct it before OCR.
    public var cropToSign: Bool
    public var languageCorrection: Bool
    /// Extra vocabulary for Vision's language correction (only used when `languageCorrection` is on).
    public var customWords: [String]
    /// When cropping, also read the whole image if the crop found no rules or the sign fills less than
    /// `fullImageCheckArea` of the frame (Boston poles often carry several signs), and keep the better reading.
    public var fullImageFallback: Bool
    /// Run Vision on the CPU instead of the Neural Engine. Default on macOS, where a cold Neural Engine
    /// fails after every rebuild (CLI, tests, eval); off on iOS, where the Neural Engine is much faster.
    public var preferCPU: Bool

    public init(level: Level = .accurate, cropToSign: Bool = true, languageCorrection: Bool = true,
                customWords: [String] = SignReader.signVocabulary, fullImageFallback: Bool = true,
                preferCPU: Bool = ReaderOptions.defaultPreferCPU) {
        self.level = level
        self.cropToSign = cropToSign
        self.languageCorrection = languageCorrection
        self.customWords = customWords
        self.fullImageFallback = fullImageFallback
        self.preferCPU = preferCPU
    }

    #if os(macOS)
    public static let defaultPreferCPU = true
    #else
    public static let defaultPreferCPU = false
    #endif

    /// Below this fraction of the frame, a detected sign may be one of several on the pole.
    public static let fullImageCheckArea: CGFloat = 0.6

    public static let accurate = ReaderOptions()
    public static let fast = ReaderOptions(level: .fast)
}

/// Milliseconds spent in each pipeline stage.
public struct StageTimings: Codable, Hashable, Sendable {
    public var detect: Double = 0
    public var correct: Double = 0
    public var ocr: Double = 0
    public var group: Double = 0
    public var parse: Double = 0
    public var total: Double = 0

    public init() {}

    public static let stageNames = ["detect", "correct", "ocr", "group", "parse", "total"]

    public func value(for stage: String) -> Double {
        switch stage {
        case "detect": return detect
        case "correct": return correct
        case "ocr": return ocr
        case "group": return group
        case "parse": return parse
        default: return total
        }
    }
}

/// Everything one read of a sign produced.
public struct SignReading: @unchecked Sendable {
    /// OCR lines; boxes are normalized (bottom-left origin) in `ocrImage`.
    public var lines: [RecognizedLine]
    public var panels: [String]
    public var parse: ParseResult
    public var timings: StageTimings
    /// The detected sign, normalized in the upright input image; nil when no rectangle was found or cropping was off.
    public var signQuad: Quad?
    /// The image OCR ran on: the corrected sign crop, or the whole upright image.
    public var ocrImage: CGImage
    /// Size of the upright input image in pixels.
    public var imageSize: CGSize
    /// True when the whole image read better than the sign crop.
    public var usedFullImageFallback: Bool

    /// A line's box mapped into the upright input image (normalized, bottom-left origin).
    public func boxInInputImage(_ line: RecognizedLine) -> CGRect {
        (signQuad ?? .unit).project(line.box)
    }
}

public enum SignReaderError: Error, LocalizedError {
    case renderFailed

    public var errorDescription: String? {
        switch self {
        case .renderFailed: return "Couldn't prepare the image for reading."
        }
    }
}

/// The on-device pipeline: detect sign → perspective-correct → OCR → group panels → parse.
public final class SignReader: @unchecked Sendable {
    /// Words Vision should prefer when language correction is on.
    public static let signVocabulary: [String] = [
        "NO", "PARKING", "STOPPING", "TOW", "ZONE", "STREET", "CLEANING", "HOUR", "HR", "MIN", "MINUTE",
        "RESIDENT", "PERMIT", "ONLY", "EXCEPT", "ANY", "TIME", "LOADING", "SNOW", "EMERGENCY", "LIMIT",
        "METER", "COMMERCIAL", "VEHICLES", "NOON", "MIDNIGHT", "THRU",
        "MON", "TUE", "TUES", "WED", "THU", "THURS", "FRI", "SAT", "SUN",
        "MONDAY", "TUESDAY", "WEDNESDAY", "THURSDAY", "FRIDAY", "SATURDAY", "SUNDAY",
        "1ST", "2ND", "3RD", "4TH", "AM", "PM",
        "JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC",
    ]

    /// Reused across reads; creating a CIContext is expensive.
    private let context = CIContext(options: [.cacheIntermediates: false])

    public init() {}

    /// Reads a parking sign from an image.
    /// - Parameters:
    ///   - image: The camera frame or photo as stored (not yet rotated).
    ///   - orientation: How to rotate `image` to make it upright (EXIF orientation; `.right` for portrait camera frames).
    public func read(image: CGImage, orientation: CGImagePropertyOrientation,
                     options: ReaderOptions = .accurate) async throws -> SignReading {
        let totalStart = ContinuousClock.now
        var timings = StageTimings()

        let upright = try uprightImage(image, orientation: orientation)
        let imageSize = CGSize(width: upright.width, height: upright.height)

        // a. Detect the sign.
        var quad: Quad?
        if options.cropToSign {
            let start = ContinuousClock.now
            quad = try detectSign(in: upright, preferCPU: options.preferCPU)
            timings.detect = Self.ms(since: start)
        }

        // b. Perspective-correct it.
        var ocrImage = upright
        if let detected = quad {
            let start = ContinuousClock.now
            if let corrected = perspectiveCorrect(upright, quad: detected) {
                ocrImage = corrected
            } else {
                quad = nil
            }
            timings.correct = Self.ms(since: start)
        }

        // c–e. OCR, group into panels, parse.
        var best = try recognizeAndParse(ocrImage, options: options, timings: &timings)
        var usedFallback = false

        // Fallback: the crop may hold only one of several signs, or be a bad crop.
        if let detected = quad, options.fullImageFallback,
           best.parse.rules.isEmpty || detected.area < ReaderOptions.fullImageCheckArea {
            let full = try recognizeAndParse(upright, options: options, timings: &timings)
            if Self.isBetter(full.parse, than: best.parse) {
                best = full
                ocrImage = upright
                quad = nil
                usedFallback = true
            }
        }

        timings.total = Self.ms(since: totalStart)
        return SignReading(lines: best.lines, panels: best.panels, parse: best.parse, timings: timings,
                           signQuad: quad, ocrImage: ocrImage, imageSize: imageSize, usedFullImageFallback: usedFallback)
    }

    private struct Pass {
        var lines: [RecognizedLine]
        var panels: [String]
        var parse: ParseResult
    }

    /// Runs OCR → panels → parser on one image, adding to the stage timings.
    private func recognizeAndParse(_ image: CGImage, options: ReaderOptions, timings: inout StageTimings) throws -> Pass {
        var start = ContinuousClock.now
        let lines = try recognizeText(in: image, options: options)
        timings.ocr += Self.ms(since: start)

        start = ContinuousClock.now
        let panels = PanelGrouper.panels(from: lines)
        timings.group += Self.ms(since: start)

        start = ContinuousClock.now
        let parse = SignParser.parse(panels: panels)
        timings.parse += Self.ms(since: start)
        return Pass(lines: lines, panels: panels, parse: parse)
    }

    /// More rules wins; on a tie, higher confidence.
    static func isBetter(_ a: ParseResult, than b: ParseResult) -> Bool {
        if a.rules.count != b.rules.count { return a.rules.count > b.rules.count }
        return a.confidence > b.confidence
    }

    // MARK: - Stages

    /// Rotates the image so it is upright; afterwards every stage works in one coordinate space.
    private func uprightImage(_ image: CGImage, orientation: CGImagePropertyOrientation) throws -> CGImage {
        guard orientation != .up else { return image }
        let oriented = CIImage(cgImage: image).oriented(orientation)
        let moved = oriented.transformed(by: CGAffineTransform(translationX: -oriented.extent.minX,
                                                               y: -oriented.extent.minY))
        guard let rendered = context.createCGImage(moved, from: moved.extent) else {
            throw SignReaderError.renderFailed
        }
        return rendered
    }

    private func detectSign(in image: CGImage, preferCPU: Bool) throws -> Quad? {
        let request = try Self.perform(on: image, preferCPU: preferCPU) {
            let request = VNDetectRectanglesRequest()
            request.minimumAspectRatio = 0.2
            request.maximumAspectRatio = 1.0
            request.minimumSize = 0.1
            request.minimumConfidence = 0.6
            request.maximumObservations = 4
            return request
        }
        let observations = (request.results as? [VNRectangleObservation]) ?? []
        let quads = observations.map {
            Quad(topLeft: $0.topLeft, topRight: $0.topRight, bottomRight: $0.bottomRight, bottomLeft: $0.bottomLeft)
        }
        return quads.max { $0.area < $1.area }
    }

    /// Vision and Core Image both put the origin at the bottom-left, so normalized → pixel is a pure scale.
    private func perspectiveCorrect(_ image: CGImage, quad: Quad) -> CGImage? {
        let input = CIImage(cgImage: image)
        let size = CGSize(width: image.width, height: image.height)
        let px = { VisionGeometry.pixelPoint($0, imageSize: size, origin: .bottomLeft) }
        let filter = CIFilter.perspectiveCorrection()
        filter.inputImage = input
        filter.topLeft = px(quad.topLeft)
        filter.topRight = px(quad.topRight)
        filter.bottomRight = px(quad.bottomRight)
        filter.bottomLeft = px(quad.bottomLeft)
        guard let output = filter.outputImage, output.extent.width >= 8, output.extent.height >= 8 else { return nil }
        return context.createCGImage(output, from: output.extent)
    }

    private func recognizeText(in image: CGImage, options: ReaderOptions) throws -> [RecognizedLine] {
        let request = try Self.perform(on: image, preferCPU: options.preferCPU) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = options.level == .accurate ? .accurate : .fast
            request.usesLanguageCorrection = options.languageCorrection
            request.recognitionLanguages = ["en-US"]
            if options.languageCorrection {
                request.customWords = options.customWords
            }
            return request
        }
        let observations = (request.results as? [VNRecognizedTextObservation]) ?? []
        return observations.compactMap { observation in
            guard let best = observation.topCandidates(1).first else { return nil }
            return RecognizedLine(text: best.string, confidence: best.confidence, box: observation.boundingBox)
        }
    }

    /// Runs a Vision request, on the CPU when `preferCPU` is set. If it fails — on macOS a cold Neural
    /// Engine throws "e5rtError ... 13" after every rebuild — it runs again on the CPU.
    private static func perform<R: VNRequest>(on image: CGImage, preferCPU: Bool,
                                              _ makeRequest: () -> R) throws -> R {
        let request = makeRequest()
        if preferCPU { runOnCPU(request) }
        do {
            try VNImageRequestHandler(cgImage: image, orientation: .up).perform([request])
            return request
        } catch {
            let cpuRequest = makeRequest()
            runOnCPU(cpuRequest)
            try VNImageRequestHandler(cgImage: image, orientation: .up).perform([cpuRequest])
            return cpuRequest
        }
    }

    private static func runOnCPU(_ request: VNRequest) {
        guard let stages = try? request.supportedComputeStageDevices else { return }
        for (stage, devices) in stages {
            let cpu = devices.first { device in
                if case .cpu = device { return true }
                return false
            }
            if let cpu { request.setComputeDevice(cpu, for: stage) }
        }
    }

    private static func ms(since start: ContinuousClock.Instant) -> Double {
        let d = ContinuousClock.now - start
        return Double(d.components.seconds) * 1000 + Double(d.components.attoseconds) / 1e15
    }
}
