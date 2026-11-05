import CoreGraphics
import Foundation

// Pure logic for the live scanner. The app feeds in CoreMotion samples and camera timestamps;
// everything here is deterministic and unit-tested.

/// One CoreMotion device-motion reading.
public struct MotionSample: Sendable, Equatable {
    /// Gravity along the device's y axis, in g. About -1 when the phone is held upright in portrait.
    public var gravityY: Double
    /// Rotation rate around x, y, z in rad/s.
    public var rotationRate: (x: Double, y: Double, z: Double)

    public init(gravityY: Double, rotationRate: (x: Double, y: Double, z: Double)) {
        self.gravityY = gravityY
        self.rotationRate = rotationRate
    }

    /// Total rotation speed in rad/s.
    public var rotationMagnitude: Double {
        (rotationRate.x * rotationRate.x + rotationRate.y * rotationRate.y + rotationRate.z * rotationRate.z).squareRoot()
    }

    public static func == (a: MotionSample, b: MotionSample) -> Bool {
        a.gravityY == b.gravityY && a.rotationRate == b.rotationRate
    }
}

/// When a camera frame is worth reading: the phone is roughly upright and not turning.
public enum SteadinessRule {
    /// Upright portrait: gravity mostly along -y.
    public static let maxGravityY = -0.8
    /// Turning slower than this (rad/s) counts as holding still.
    public static let maxRotation = 0.5

    /// True when a frame taken now is worth reading.
    public static func isSteady(_ sample: MotionSample) -> Bool {
        sample.gravityY < maxGravityY && sample.rotationMagnitude < maxRotation
    }
}

/// Multi-frame voting: a reading is trusted once the same rule set appears in enough recent frames.
///
/// Single fast-OCR frames flicker ("2 HOUR" one frame, "2 HOIR" the next). Requiring 3 of the last 6
/// processed frames to agree removes most of that noise for about one second of extra latency at 3 fps.
public struct FrameVoter: Sendable {
    /// How many recent frames vote.
    public let window: Int
    /// Votes a rule set needs to be trusted.
    public let threshold: Int
    private(set) var history: [Set<ParkingRule>] = []

    public init(window: Int = 6, threshold: Int = 3) {
        self.window = window
        self.threshold = threshold
    }

    /// The vote after adding a frame.
    public struct Result: Equatable, Sendable {
        /// The agreed rules, or nil while no non-empty rule set has `threshold` votes.
        public var stableRules: [ParkingRule]?
        /// Votes for the most common non-empty rule set in the window.
        public var topVotes: Int
    }

    /// Adds one processed frame's rules and returns the current vote.
    public mutating func add(_ rules: [ParkingRule]) -> Result {
        history.append(Set(rules.map(\.withoutSource)))
        if history.count > window { history.removeFirst(history.count - window) }

        var counts: [Set<ParkingRule>: Int] = [:]
        for set in history where !set.isEmpty { counts[set, default: 0] += 1 }
        guard let (winner, votes) = counts.max(by: { $0.value < $1.value }) else {
            return Result(stableRules: nil, topVotes: 0)
        }
        let stable = votes >= threshold
            ? winner.sorted { RuleDescriber.describe($0) < RuleDescriber.describe($1) }
            : nil
        return Result(stableRules: stable, topVotes: votes)
    }

    /// Forgets all votes (after a capture).
    public mutating func reset() {
        history.removeAll()
    }
}

/// Lets at most one frame be in flight and at most `maxPerSecond` start per second.
/// Thread-safe: the camera calls `tryBegin` on its video queue, the reader calls `end` when done.
public final class FrameThrottle: @unchecked Sendable {
    private let lock = NSLock()
    private let minInterval: Double
    private var lastStart: Double = -.infinity
    private var busy = false
    private var enabled = true

    public init(maxPerSecond: Double = 3) {
        self.minInterval = 1 / maxPerSecond
    }

    /// `now` is any monotonic clock in seconds (the app passes CACurrentMediaTime()).
    public func tryBegin(now: Double) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard enabled, !busy, now - lastStart >= minInterval else { return false }
        busy = true
        lastStart = now
        return true
    }

    /// Marks the in-flight frame as finished.
    public func end() {
        lock.lock()
        busy = false
        lock.unlock()
    }

    /// Off while the phone isn't steady.
    public func setEnabled(_ value: Bool) {
        lock.lock()
        enabled = value
        lock.unlock()
    }
}

extension VisionGeometry {
    /// Maps a Vision rect (normalized, bottom-left origin) in an upright image to a view that shows that
    /// image with aspect-fill (what AVCaptureVideoPreviewLayer's `.resizeAspectFill` does): scaled to cover
    /// the view, centered, overflow cropped. Result is in view points, top-left origin.
    public static func aspectFillRect(_ normalized: CGRect, imageSize: CGSize, viewSize: CGSize) -> CGRect {
        let (drawn, offset) = aspectFillLayout(imageSize: imageSize, viewSize: viewSize)
        return pixelRect(normalized, imageSize: drawn, origin: .topLeft).offsetBy(dx: offset.x, dy: offset.y)
    }

    /// Maps a Vision point in the upright image to view points, like `aspectFillRect`.
    public static func aspectFillPoint(_ normalized: CGPoint, imageSize: CGSize, viewSize: CGSize) -> CGPoint {
        let (drawn, offset) = aspectFillLayout(imageSize: imageSize, viewSize: viewSize)
        let p = pixelPoint(normalized, imageSize: drawn, origin: .topLeft)
        return CGPoint(x: p.x + offset.x, y: p.y + offset.y)
    }

    private static func aspectFillLayout(imageSize: CGSize, viewSize: CGSize) -> (CGSize, CGPoint) {
        guard imageSize.width > 0, imageSize.height > 0 else { return (viewSize, .zero) }
        let scale = max(viewSize.width / imageSize.width, viewSize.height / imageSize.height)
        let drawn = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return (drawn, CGPoint(x: (viewSize.width - drawn.width) / 2, y: (viewSize.height - drawn.height) / 2))
    }
}
