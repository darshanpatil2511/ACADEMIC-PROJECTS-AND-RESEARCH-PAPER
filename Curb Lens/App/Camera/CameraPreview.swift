import AVFoundation
import SwiftUI
import UIKit

/// Shows the live camera feed with aspect-fill, matching `VisionGeometry.aspectFillRect` for overlays.
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}

    final class PreviewView: UIView {
        let previewLayer = AVCaptureVideoPreviewLayer()

        override init(frame: CGRect) {
            super.init(frame: frame)
            backgroundColor = .black
            layer.addSublayer(previewLayer)
        }

        required init?(coder: NSCoder) {
            super.init(coder: coder)
            layer.addSublayer(previewLayer)
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            previewLayer.frame = bounds
            if let connection = previewLayer.connection, connection.isVideoRotationAngleSupported(90) {
                connection.videoRotationAngle = 90   // portrait
            }
        }
    }
}
