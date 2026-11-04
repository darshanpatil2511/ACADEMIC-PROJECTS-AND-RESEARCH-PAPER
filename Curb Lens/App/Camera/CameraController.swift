import AVFoundation
import CoreImage
import CurbCore
import QuartzCore

/// Owns the AVFoundation capture session: back wide camera, 1080p BGRA video frames for live reading,
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

    let session = AVCaptureSession()
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
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            throw CameraError.noCamera
        }
        let input = try AVCaptureDeviceInput(device: device)

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
        device.unlockForConfiguration()

        configured = true
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
