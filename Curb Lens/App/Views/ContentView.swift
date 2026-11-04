import SwiftUI
import CurbCore

struct ContentView: View {
    var body: some View {
        VStack(spacing: 8) {
            Text("CurbLens")
                .font(.largeTitle.bold())
            Text("Point. Read. Park.")
                .foregroundStyle(.secondary)
            Text("CurbCore \(CurbCore.version)")
                .font(.footnote.monospaced())
                .foregroundStyle(.tertiary)
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
