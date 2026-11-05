import PhotosUI
import SwiftData
import SwiftUI

struct HomeView: View {
    @Query(filter: #Predicate<ParkingSession> { $0.endedAt == nil }, sort: \ParkingSession.startedAt, order: .reverse)
    private var activeSessions: [ParkingSession]
    @State private var model = ScanViewModel()
    @State private var pickerItem: PhotosPickerItem?
    /// Debug aid: `-CurbLensOpenSaved YES` opens the saved-signs screen on launch.
    @State private var showSaved = UserDefaults.standard.bool(forKey: "CurbLensOpenSaved")
    /// Debug aid: `-CurbLensOpenBenchmark YES` opens the benchmark on launch.
    @State private var showBenchmark = UserDefaults.standard.bool(forKey: "CurbLensOpenBenchmark")

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    if let session = activeSessions.first {
                        ParkedBanner(session: session)
                            .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.25)))
                    }
                    ScanHero(scale: activeSessions.isEmpty ? 1 : 0.62)
                        .padding(.top, activeSessions.isEmpty ? 8 : 0)
                    VStack(spacing: 6) {
                        Text("CurbLens")
                            .font(.system(size: 40, weight: .heavy, design: .rounded))
                        Text("Point. Read. Park.")
                            .font(.title3.weight(.medium))
                            .foregroundStyle(.white.opacity(0.75))
                        Label("Reads Boston parking signs entirely on your iPhone", systemImage: "lock.shield")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.6))
                            .padding(.top, 2)
                    }
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    ExampleVerdictCard()
                    HowItWorksRow()
                        .padding(.top, 4)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
            }
            .scrollIndicators(.hidden)
            .safeAreaInset(edge: .bottom) { actionPanel }
            .background { WelcomeBackground() }
            .toolbarBackground(.hidden, for: .navigationBar)
            .navigationDestination(item: $model.result) { result in
                ResultView(result: result)
            }
            .navigationDestination(isPresented: $showSaved) { SavedSignsView() }
            .navigationDestination(isPresented: $showBenchmark) { BenchmarkView() }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showBenchmark = true } label: {
                        Image(systemName: "gauge.with.dots.needle.67percent")
                            .foregroundStyle(.white)
                    }
                    .accessibilityLabel("On-device benchmark")
                }
            }
            .navigationDestination(for: SavedSign.self) { SavedSignDetailView(sign: $0) }
            .onChange(of: pickerItem) { _, item in
                guard let item else { return }
                Task {
                    await model.read(item: item)
                    pickerItem = nil
                }
            }
            .task { await loadDemoImageIfRequested() }
        }
    }

    /// Glass panel pinned to the bottom: the main action plus photo import and saved signs.
    private var actionPanel: some View {
        VStack(spacing: 12) {
            scanButton
            HStack(spacing: 12) {
                PhotosPicker(selection: $pickerItem, matching: .images) {
                    secondaryLabel("Choose photo", systemImage: "photo.on.rectangle")
                }
                .disabled(model.status == .reading)
                NavigationLink {
                    SavedSignsView()
                } label: {
                    secondaryLabel("Saved signs", systemImage: "map")
                }
            }
            statusView
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(.white.opacity(0.2)))
        .environment(\.colorScheme, .dark)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .padding(.top, 24)
        // Fade the scrolling content out behind the panel instead of letting it peek through below it.
        .background {
            LinearGradient(colors: [.clear, Color(red: 0.02, green: 0.05, blue: 0.20).opacity(0.95)],
                           startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.35))
                .ignoresSafeArea()
        }
    }

    private func secondaryLabel(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var scanLabel: some View {
        Label("Scan a sign", systemImage: "camera.viewfinder")
            .font(.headline)
            .foregroundStyle(Color(red: 0.04, green: 0.25, blue: 0.80))
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: .black.opacity(0.25), radius: 12, y: 6)
    }

    @ViewBuilder private var scanButton: some View {
        #if targetEnvironment(simulator)
        VStack(spacing: 6) {
            scanLabel.opacity(0.45)
            Text("The simulator has no camera. Use “Choose photo”, or run on your iPhone.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
        }
        #else
        NavigationLink {
            ScannerView()
        } label: {
            scanLabel
        }
        #endif
    }

    @ViewBuilder private var statusView: some View {
        switch model.status {
        case .idle:
            EmptyView()
        case .reading:
            ProgressView("Reading sign…")
                .tint(.white)
                .foregroundStyle(.white)
        case let .failed(message):
            Label(message, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
                .font(.footnote)
        }
    }

    /// Debug aid: `-CurbLensDemoImage /path/to/sign.jpg` opens a result straight away (used to
    /// screenshot the result screen from the command line).
    private func loadDemoImageIfRequested() async {
        #if DEBUG
        guard model.result == nil, let path = UserDefaults.standard.string(forKey: "CurbLensDemoImage") else { return }
        await model.read(fileURL: URL(fileURLWithPath: path))
        #endif
    }
}

#Preview {
    HomeView()
        .modelContainer(for: [SavedSign.self, ParkingSession.self], inMemory: true)
}
