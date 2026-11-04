import PhotosUI
import SwiftUI

struct HomeView: View {
    @State private var model = ScanViewModel()
    @State private var pickerItem: PhotosPickerItem?

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()
                VStack(spacing: 6) {
                    Image(systemName: "parkingsign.circle.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(.tint)
                    Text("CurbLens")
                        .font(.largeTitle.bold())
                    Text("Point. Read. Park.")
                        .foregroundStyle(.secondary)
                }
                Spacer()

                scanButton

                PhotosPicker(selection: $pickerItem, matching: .images) {
                    Label("Choose photo", systemImage: "photo.on.rectangle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(model.status == .reading)

                statusView
                    .frame(minHeight: 44)
            }
            .padding(24)
            .navigationDestination(item: $model.result) { result in
                ResultView(result: result)
            }
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

    @ViewBuilder private var scanButton: some View {
        #if targetEnvironment(simulator)
        VStack(spacing: 6) {
            Label("Scan a sign", systemImage: "camera.viewfinder")
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .modifier(ProminentButtonLook())
                .opacity(0.4)
            Text("The simulator has no camera. Use “Choose photo”, or run on your iPhone.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        #else
        NavigationLink {
            ScannerView()
        } label: {
            Label("Scan a sign", systemImage: "camera.viewfinder")
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        #endif
    }

    @ViewBuilder private var statusView: some View {
        switch model.status {
        case .idle:
            EmptyView()
        case .reading:
            ProgressView("Reading sign…")
        case let .failed(message):
            Label(message, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.red)
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

/// Looks like `.borderedProminent` without being a button (for the disabled simulator state).
private struct ProminentButtonLook: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.headline)
            .foregroundStyle(.white)
            .padding(.vertical, 8)
            .background(.tint, in: RoundedRectangle(cornerRadius: 12))
    }
}

#Preview {
    HomeView()
}
