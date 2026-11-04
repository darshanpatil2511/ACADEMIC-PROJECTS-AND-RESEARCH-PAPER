import AVFoundation
import CoreImage
import CurbCore
import QuartzCore

/// Owns the AVFoundation capture session: back camera (multi-lens when available, for real optical zoom),
/// 1080p BGRA video frames for live reading,
/// and a photo output for the full-resolution accurate pass.
///
/// All session work happens on `sessionQueue`, frames arrive on `videoQueue`; nothing blocks the main thread.
final class CameraController: NSObject, @unchecked Sendable {
    enum CameraError: LocalizedError {
        case noCamera
        case cannotAddInputOrOutput
        case photoFailed

        var errorDescription: String? {
            switch self {
            case .noCamera: return "This device has no back camera."
            case .cannotAddInputOrOutput: return "The camera couldn't be set up."
            case .photoFailed: return "The photo couldn't be captured."
            }
        }
    }

    /// Zoom range and lens presets, in the numbers the Camera app shows (1× = main wide lens).
    struct ZoomInfo: Equatable, Sendable {
        var minDisplay: CGFloat = 1
        var maxDisplay: CGFloat = 1
        /// Multiply a device zoom factor by this to get the displayed value (0.5 when the virtual device starts at ultra-wide).
        var displayMultiplier: CGFloat = 1
        /// Lens-switch points and 2×, e.g. [0.5, 1, 2, 4].
        var presets: [CGFloat] = [1]
    }

    let session = AVCaptureSession()
    /// Set during `configure()`.
    private(set) var zoomInfo = ZoomInfo()
    private var device: AVCaptureDevice?
    /// Gate for live frames: one in flight, at most 2 per second (accurate OCR), only while steady.
    let throttle = FrameThrottle(maxPerSecond: 2)
    /// Called on the video queue with an upright-able frame when the throttle lets one through.
    /// The handler must call `throttle.end()` when it has finished with the frame.
    var onFrame: ((CGImage) -> Void)?

    private let sessionQueue = DispatchQueue(label: "curblens.camera.session")
    private let videoQueue = DispatchQueue(label: "curblens.camera.video")
    private let videoOutput = AVCaptureVideoDataOutput()
    private let photoOutput = AVCapturePhotoOutput()
    private let ciContext = CIContext()
    private var configured = false
    private var photoContinuation: CheckedContinuation<Data, Error>?

    static func authorizationStatus() -> AVAuthorizationStatus {
        AVCaptureDevice.authorizationStatus(for: .video)
    }

    static func requestAccess() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .video)
    }

    /// Configures the session once. Safe to call again.
    func configure() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            sessionQueue.async {
                do {
                    try self.configureOnSessionQueue()
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func start() {
        sessionQueue.async {
            if self.configured, !self.session.isRunning { self.session.startRunning() }
        }
    }

    func stop() {
        sessionQueue.async {
            if self.session.isRunning { self.session.stopRunning() }
        }
    }

    /// Takes a full-resolution still. The returned JPEG/HEIC data carries the EXIF orientation.
    func capturePhoto() async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            sessionQueue.async {
                guard self.photoContinuation == nil else {
                    continuation.resume(throwing: CameraError.photoFailed)
                    return
                }
                self.photoContinuation = continuation
                let settings = AVCapturePhotoSettings()
                settings.photoQualityPrioritization = .balanced
                self.photoOutput.capturePhoto(with: settings, delegate: self)
            }
        }
    }

    // MARK: - Setup

    private func configureOnSessionQueue() throws {
        guard !configured else { return }
        guard let device = Self.bestBackCamera() else { throw CameraError.noCamera }
        let input = try AVCaptureDeviceInput(device: device)
        self.device = device

        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = session.canSetSessionPreset(.hd1920x1080) ? .hd1920x1080 : .high

        guard session.canAddInput(input), session.canAddOutput(videoOutput), session.canAddOutput(photoOutput) else {
            throw CameraError.cannotAddInputOrOutput
        }
        session.addInput(input)

        videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.setSampleBufferDelegate(self, queue: videoQueue)
        session.addOutput(videoOutput)
        session.addOutput(photoOutput)

        // Stills come out in portrait (EXIF orientation set accordingly). Video frames stay in sensor
        // orientation; the reader is told `.right` instead, which is cheaper than rotating every frame.
        if let connection = photoOutput.connection(with: .video), connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90
        }

        try device.lockForConfiguration()
        if device.isFocusModeSupported(.continuousAutoFocus) { device.focusMode = .continuousAutoFocus }
        if device.isExposureModeSupported(.continuousAutoExposure) { device.exposureMode = .continuousAutoExposure }
        if device.isAutoFocusRangeRestrictionSupported { device.autoFocusRangeRestriction = .none }
        let zoom = Self.zoomInfo(for: device)
        device.videoZoomFactor = Self.clampedFactor(1 / zoom.displayMultiplier, device: device)   // start at 1×
        device.unlockForConfiguration()

        zoomInfo = zoom
        configured = true
    }

    // MARK: - Zoom

    /// Sets the zoom using the displayed value (1× = main lens). Animated for lens buttons, direct for pinch.
    func setZoom(display: CGFloat, animated: Bool) {
        sessionQueue.async {
            guard let device = self.device else { return }
            let factor = Self.clampedFactor(display / self.zoomInfo.displayMultiplier, device: device)
            do {
                try device.lockForConfiguration()
                if animated {
                    device.ramp(toVideoZoomFactor: factor, withRate: 8)
                } else {
                    device.cancelVideoZoomRamp()
                    device.videoZoomFactor = factor
                }
                device.unlockForConfiguration()
            } catch {
                // Zoom is best-effort; keep the current factor.
            }
        }
    }

    /// Prefers the virtual multi-camera devices: as zoom changes they switch to the ultra-wide or
    /// telephoto lens, so 4× is real optics instead of an upscaled crop (much better for OCR).
    private static func bestBackCamera() -> AVCaptureDevice? {
        let preferred: [AVCaptureDevice.DeviceType] = [.builtInTripleCamera, .builtInDualWideCamera,
                                                       .builtInDualCamera, .builtInWideAngleCamera]
        let found = AVCaptureDevice.DiscoverySession(deviceTypes: preferred, mediaType: .video, position: .back).devices
        for type in preferred {
            if let device = found.first(where: { $0.deviceType == type }) { return device }
        }
        return nil
    }

    private static func zoomInfo(for device: AVCaptureDevice) -> ZoomInfo {
        let switchOvers = device.virtualDeviceSwitchOverVideoZoomFactors.map { CGFloat(truncating: $0) }
        let hasUltraWide = device.constituentDevices.contains { $0.deviceType == .builtInUltraWideCamera }
        // On a virtual device with an ultra-wide lens, factor 1 is the ultra-wide (shown as 0.5×) and the
        // first switch-over is the main lens (1×).
        let multiplier: CGFloat = hasUltraWide ? 1 / (switchOvers.first ?? 2) : 1

        let minDisplay = device.minAvailableVideoZoomFactor * multiplier
        // Beyond ~10× the image is mostly digital upscaling and OCR stops improving.
        let maxDisplay = min(device.maxAvailableVideoZoomFactor * multiplier, 10)
        var presets: [CGFloat] = [1, 2] + switchOvers.map { $0 * multiplier }
        if hasUltraWide { presets.append(minDisplay) }
        let rounded = Set(presets.map { ($0 * 10).rounded() / 10 }).filter { $0 >= minDisplay - 0.01 && $0 <= maxDisplay + 0.01 }
        return ZoomInfo(minDisplay: minDisplay, maxDisplay: maxDisplay, displayMultiplier: multiplier,
                        presets: rounded.sorted())
    }

    private static func clampedFactor(_ factor: CGFloat, device: AVCaptureDevice) -> CGFloat {
        min(max(factor, device.minAvailableVideoZoomFactor), device.maxAvailableVideoZoomFactor)
    }
}

// MARK: - Live frames

extension CameraController: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let onFrame, throttle.tryBegin(now: CACurrentMediaTime()) else { return }
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            throttle.end()
            return
        }
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        guard let image = ciContext.createCGImage(ciImage, from: ciImage.extent) else {
            throttle.end()
            return
        }
        onFrame(image)
    }
}

// MARK: - Stills

extension CameraController: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        sessionQueue.async {
            let continuation = self.photoContinuation
            self.photoContinuation = nil
            if let error {
                continuation?.resume(throwing: error)
            } else if let data = photo.fileDataRepresentation() {
                continuation?.resume(returning: data)
            } else {
                continuation?.resume(throwing: CameraError.photoFailed)
            }
        }
    }
}
