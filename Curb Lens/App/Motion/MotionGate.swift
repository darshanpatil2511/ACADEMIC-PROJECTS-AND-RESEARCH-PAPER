import CoreMotion
import CurbCore

/// Reads CoreMotion device motion at 30 Hz and reports whether the phone is steady enough to read a sign
/// (rule in `SteadinessRule`: upright and turning slower than 0.5 rad/s).
final class MotionGate {
    private let manager = CMMotionManager()

    /// The latest device pitch in radians (used later to tag saved signs).
    private(set) var pitch: Double = 0

    /// `handler` runs on the main queue for every sample.
    func start(handler: @escaping (_ steady: Bool, _ sample: MotionSample) -> Void) {
        guard manager.isDeviceMotionAvailable else {
            // Simulator or unsupported device: never block reading.
            handler(true, MotionSample(gravityY: -1, rotationRate: (0, 0, 0)))
            return
        }
        manager.deviceMotionUpdateInterval = 1.0 / 30.0
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let motion else { return }
            self?.pitch = motion.attitude.pitch
            let sample = MotionSample(gravityY: motion.gravity.y,
                                      rotationRate: (motion.rotationRate.x, motion.rotationRate.y, motion.rotationRate.z))
            handler(SteadinessRule.isSteady(sample), sample)
        }
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
    }
}
