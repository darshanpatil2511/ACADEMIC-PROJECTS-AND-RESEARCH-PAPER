import AVFoundation
import CurbCore
import Foundation
import Observation
import QuartzCore
import UIKit

/// Drives the live scanner: camera frames → motion gate → fast read → multi-frame vote → live verdict,
/// and Capture → full-resolution still → accurate read → result screen.
@MainActor
@Observable
final class ScannerModel {
    enum CameraState: Equatable {
        case starting
        case running
        case denied
        case failed(String)
    }

    var cameraState: CameraState = .starting
    var isSteady = false
    /// Latest live reading, for the overlay.
    var latestReading: SignReading?
    /// Rules agreed on by `FrameVoter`; non-nil means "stable".
    var stableRules: [ParkingRule]?
    var topVotes = 0
    var isCapturing = false
    var captured: ScanResult?
    var showHUD = false
    var processedFPS: Double = 0
    var lastOCRMilliseconds: Double = 0

    let camera = CameraController()
    var session: AVCaptureSession { camera.session }

    /// Live frames use the same accurate reader as stills. Fast OCR was tried first: it drops the times
    /// on real signs ("7am-7pm" unread), so frames rarely agreed and the vote never settled.
    nonisolated static let liveOptions = ReaderOptions.accurate

    private let motion = MotionGate()
    private let reader = SignReader()
    private var voter = FrameVoter()
    private var processedTimes: [CFTimeInterval] = []
    private let haptics = UINotificationFeedbackGenerator()

    // MARK: Lifecycle

    func start() async {
        switch CameraController.authorizationStatus() {
        case .authorized:
            break
        case .notDetermined:
            guard await CameraController.requestAccess() else {
                cameraState = .denied
                return
            }
        default:
            cameraState = .denied
            return
        }

        do {
            try await camera.configure()
        } catch {
            cameraState = .failed(error.localizedDescription)
            return
        }

        let reader = self.reader
        let throttle = camera.throttle
        camera.onFrame = { [weak self] image in
            // Video queue. Read off the main actor, then publish on it.
            Task.detached(priority: .userInitiated) {
                defer { throttle.end() }
                let start = CACurrentMediaTime()
                guard let reading = try? await reader.read(image: image, orientation: .right,
                                                           options: ScannerModel.liveOptions) else { return }
                let elapsed = (CACurrentMediaTime() - start) * 1000
                await self?.handle(reading, ocrMilliseconds: elapsed)
            }
        }

        motion.start { [weak self] steady, _ in
            guard let self else { return }
            if steady != self.isSteady { self.isSteady = steady }
            throttle.setEnabled(steady && !self.isCapturing)
        }
        haptics.prepare()
        camera.start()
        cameraState = .running
    }

    func stop() {
        camera.stop()
        motion.stop()
        camera.throttle.setEnabled(false)
        camera.onFrame = nil
    }

    // MARK: Live frames

    private func handle(_ reading: SignReading, ocrMilliseconds: Double) {
        latestReading = reading
        lastOCRMilliseconds = ocrMilliseconds

        let now = CACurrentMediaTime()
        processedTimes.append(now)
        processedTimes.removeAll { now - $0 > 2 }
        processedFPS = Double(processedTimes.count) / 2

        let wasStable = stableRules != nil
        let vote = voter.add(reading.parse.rules)
        topVotes = vote.topVotes
        if vote.stableRules != stableRules {
            stableRules = vote.stableRules
            if !wasStable, vote.stableRules != nil { haptics.notificationOccurred(.success) }
        }
    }

    func liveVerdict(at date: Date) -> Verdict? {
        guard let stableRules else { return nil }
        return RuleEngine.evaluate(rules: stableRules, arrival: date, calendar: .boston, permitZone: nil)
    }

    // MARK: Capture

    func capture() async {
        guard !isCapturing else { return }
        isCapturing = true
        camera.throttle.setEnabled(false)
        defer {
            isCapturing = false
            camera.throttle.setEnabled(isSteady)
        }
        do {
            let data = try await camera.capturePhoto()
            let reader = self.reader
            let reading = try await Task.detached(priority: .userInitiated) {
                let (image, orientation) = try ImageDecoding.decode(data: data)
                return try await reader.read(image: image, orientation: orientation, options: .accurate)
            }.value
            #if DEBUG
            print("[CurbLens] capture panels: \(reading.panels)  rules: \(reading.parse.rules.map(RuleDescriber.describe))  \(Int(reading.timings.total)) ms")
            #endif
            captured = ScanResult(reading: reading)
            voter.reset()
            stableRules = nil
            topVotes = 0
        } catch {
            cameraState = .failed(error.localizedDescription)
        }
    }
}
