import SwiftUI

/// Live camera scanner. Phase 5 replaces this placeholder with the AVFoundation pipeline.
struct ScannerView: View {
    var body: some View {
        ContentUnavailableView("Live scanning is coming next",
                               systemImage: "camera.viewfinder",
                               description: Text("For now, use “Choose photo” on the home screen."))
            .navigationTitle("Scan")
    }
}
