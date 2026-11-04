import CurbCore
import SwiftUI

/// Live camera scanner: point at a sign, hold steady, and the verdict appears once 3 of the last 6
/// frames agree. Capture takes a full-resolution photo and runs the accurate reader.
struct ScannerView: View {
    @State private var model = ScannerModel()
    @Environment(\.openURL) private var openURL

    var body: some View {
        @Bindable var model = model
        ZStack {
            Color.black.ignoresSafeArea()
            switch model.cameraState {
            case .starting, .running:
                CameraPreview(session: model.session)
                    .ignoresSafeArea()
                LiveOverlay(reading: model.latestReading)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                controls
            case .denied:
                permissionView
            case let .failed(message):
                ContentUnavailableView("Camera unavailable", systemImage: "camera.badge.ellipsis",
                                       description: Text(message))
                    .foregroundStyle(.white)
            }
        }
        .navigationTitle("Scan")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(model.showHUD ? "Hide HUD" : "HUD") { model.showHUD.toggle() }
            }
        }
        .navigationDestination(item: $model.captured) { result in
            ResultView(result: result)
        }
        .task { await model.start() }
        .onDisappear { model.stop() }
        .onAppear { if model.cameraState == .running { model.camera.start() } }
    }

    // MARK: Controls

    private var controls: some View {
        VStack {
            if model.showHUD { hud }
            Spacer()
            TimelineView(.periodic(from: .now, by: 30)) { context in
                statusCard(now: context.date)
            }
            captureButton
        }
        .padding()
    }

    @ViewBuilder private func statusCard(now: Date) -> some View {
        if model.isCapturing {
            pill(ProgressView("Reading full photo…").tint(.white), color: .black)
        } else if let verdict = model.liveVerdict(at: now) {
            VerdictCard(presentation: VerdictFormatter.present(verdict, now: now, calendar: .boston),
                        towZone: RuleEngine.towZoneApplies(rules: model.stableRules ?? [], verdict: verdict,
                                                           at: now, calendar: .boston))
        } else if !model.isSteady {
            pill(Label("Hold steady and point at the sign", systemImage: "hand.raised"), color: .black)
        } else {
            pill(Label("Reading…", systemImage: "text.viewfinder"), color: .black)
        }
    }

    private func pill<Content: View>(_ content: Content, color: Color) -> some View {
        content
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(color.opacity(0.6), in: Capsule())
    }

    /// Always available: a stable live reading is a bonus, not a requirement. It turns green when the
    /// last frames agree, so the user knows the capture will most likely read well.
    private var captureButton: some View {
        Button {
            Task { await model.capture() }
        } label: {
            Label(model.stableRules == nil ? "Capture" : "Capture — reading is stable",
                  systemImage: "camera.circle.fill")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
        }
        .buttonStyle(.borderedProminent)
        .tint(model.stableRules == nil ? .accentColor : .green)
        .controlSize(.large)
        .disabled(model.isCapturing || model.cameraState != .running)
        .padding(.top, 8)
    }

    private var hud: some View {
        HStack(spacing: 14) {
            hudItem("FPS", String(format: "%.1f", model.processedFPS))
            hudItem("OCR", String(format: "%.0f ms", model.lastOCRMilliseconds))
            hudItem("Steady", model.isSteady ? "yes" : "no")
            hudItem("Votes", "\(model.topVotes)/3")
            hudItem("Rules", "\(model.latestReading?.parse.rules.count ?? 0)")
        }
        .font(.caption.monospacedDigit())
        .foregroundStyle(.white)
        .padding(10)
        .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 10))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func hudItem(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).foregroundStyle(.white.opacity(0.7))
            Text(value).bold()
        }
    }

    private var permissionView: some View {
        VStack(spacing: 16) {
            Image(systemName: "camera.fill").font(.largeTitle)
            Text("CurbLens needs the camera to read signs.")
                .font(.headline)
            Text("Photos are processed on your iPhone and never leave it.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.7))
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            }
            .buttonStyle(.borderedProminent)
        }
        .multilineTextAlignment(.center)
        .foregroundStyle(.white)
        .padding()
    }
}

/// Draws the detected sign outline and recognized text boxes over the aspect-fill camera preview.
struct LiveOverlay: View {
    let reading: SignReading?

    var body: some View {
        Canvas { context, size in
            guard let reading else { return }
            let imageSize = reading.imageSize
            if let quad = reading.signQuad {
                var outline = Path()
                let points = quad.corners.map {
                    VisionGeometry.aspectFillPoint($0, imageSize: imageSize, viewSize: size)
                }
                outline.addLines(points)
                outline.closeSubpath()
                context.stroke(outline, with: .color(.green), lineWidth: 3)
            }
            for line in reading.lines {
                let rect = VisionGeometry.aspectFillRect(reading.boxInInputImage(line), imageSize: imageSize, viewSize: size)
                context.stroke(Path(rect), with: .color(.yellow), lineWidth: 1.5)
            }
        }
    }
}
