import CoreMotion
import CurbCore

/// Reads CoreMotion device motion at 30 Hz and reports whether the phone is steady enough to read a sign
/// (rule in `SteadinessRule`: upright and turning slower than 0.5 rad/s).
final class MotionGate {
    private let manager = CMMotionManager()

    /// Where the back camera points relative to the horizon, in degrees (+ up), from the latest sample.
    /// Saved with each captured sign.
    private(set) var cameraPitchDegrees: Double?

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
            self?.cameraPitchDegrees = GeoText.cameraPitchDegrees(gravityX: motion.gravity.x,
                                                                  gravityY: motion.gravity.y,
                                                                  gravityZ: motion.gravity.z)
            let sample = MotionSample(gravityY: motion.gravity.y,
                                      rotationRate: (motion.rotationRate.x, motion.rotationRate.y, motion.rotationRate.z))
            handler(SteadinessRule.isSteady(sample), sample)
        }
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
    }
}
