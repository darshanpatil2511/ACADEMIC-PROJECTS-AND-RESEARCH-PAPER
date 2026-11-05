import SwiftUI

// Pieces of the home/welcome screen. Animations stop when Reduce Motion is on.

/// Deep blue backdrop with two slowly drifting glows.
struct WelcomeBackground: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drift = false

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.07, green: 0.30, blue: 0.95), Color(red: 0.03, green: 0.12, blue: 0.45),
                                    Color(red: 0.02, green: 0.05, blue: 0.20)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            Circle()
                .fill(Color.cyan.opacity(0.35))
                .frame(width: 320)
                .blur(radius: 90)
                .offset(x: drift ? 120 : -60, y: drift ? -260 : -180)
            Circle()
                .fill(Color.green.opacity(0.22))
                .frame(width: 280)
                .blur(radius: 100)
                .offset(x: drift ? -120 : 80, y: drift ? 260 : 340)
        }
        .ignoresSafeArea()
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 9).repeatForever(autoreverses: true)) { drift = true }
        }
    }
}

/// The app icon brought to life: a parking sign inside viewfinder corners, a scan line sweeping over it,
/// and the green "you can park" check popping in.
struct ScanHero: View {
    /// Smaller when the parked banner shares the screen.
    var scale: CGFloat = 1

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var scanning = false
    @State private var checkShown = false

    private let frameSize: CGFloat = 190
    private let sign = CGSize(width: 92, height: 118)

    var body: some View {
        ZStack {
            Circle()
                .fill(.white.opacity(0.08))
                .frame(width: frameSize * 1.1)
            ViewfinderCorners()
                .stroke(.white.opacity(0.9), style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
                .frame(width: frameSize, height: frameSize)

            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.white)
                .frame(width: sign.width, height: sign.height)
                .overlay {
                    Text("P")
                        .font(.system(size: 76, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color(red: 0.04, green: 0.28, blue: 0.84))
                }
                .shadow(color: .black.opacity(0.3), radius: 14, y: 8)

            // Scan line sweeping across the sign.
            Capsule()
                .fill(LinearGradient(colors: [.clear, .cyan, .white, .cyan, .clear], startPoint: .leading, endPoint: .trailing))
                .frame(width: sign.width + 44, height: 4)
                .shadow(color: .cyan, radius: 8)
                .offset(y: scanning ? sign.height / 2 + 6 : -sign.height / 2 - 6)
                .opacity(reduceMotion ? 0 : 1)

            Image(systemName: "checkmark.circle.fill")
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, .green)
                .font(.system(size: 46, weight: .bold))
                .background(Circle().fill(Color(red: 0.03, green: 0.15, blue: 0.5)).padding(-5))
                .offset(x: sign.width / 2 + 2, y: sign.height / 2 - 2)
                .scaleEffect(checkShown ? 1 : 0.4)
                .opacity(checkShown ? 1 : 0)
        }
        .frame(width: frameSize * 1.15, height: frameSize * 1.15)
        .scaleEffect(scale)
        .frame(height: frameSize * 1.15 * scale)
        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: scale)
        .accessibilityHidden(true)
        .onAppear {
            if reduceMotion {
                checkShown = true
                return
            }
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) { scanning = true }
            withAnimation(.spring(response: 0.5, dampingFraction: 0.55).delay(0.9)) { checkShown = true }
        }
    }
}

/// Four rounded L-shaped corners, like the camera app's focus frame.
struct ViewfinderCorners: Shape {
    func path(in rect: CGRect) -> Path {
        let arm = rect.width * 0.24
        var path = Path()
        let corners: [(CGPoint, CGFloat, CGFloat)] = [
            (CGPoint(x: rect.minX, y: rect.minY), 1, 1), (CGPoint(x: rect.maxX, y: rect.minY), -1, 1),
            (CGPoint(x: rect.minX, y: rect.maxY), 1, -1), (CGPoint(x: rect.maxX, y: rect.maxY), -1, -1),
        ]
        for (point, dx, dy) in corners {
            path.move(to: CGPoint(x: point.x, y: point.y + dy * arm))
            path.addLine(to: point)
            path.addLine(to: CGPoint(x: point.x + dx * arm, y: point.y))
        }
        return path
    }
}

/// Cycles through example signs and the answer CurbLens gives for each, so first-time users see what it does.
struct ExampleVerdictCard: View {
    private struct Example: Equatable {
        let sign: String
        let title: String
        let detail: String
        let symbol: String
        let color: Color
    }

    private let examples = [
        Example(sign: "2 HOUR PARKING · 8AM–6PM · MON–FRI", title: "You can park", detail: "Move by today at 11:00 AM",
                symbol: "checkmark.circle.fill", color: .green),
        Example(sign: "TOW ZONE · STREET CLEANING · 2ND & 4TH TUE", title: "No parking now",
                detail: "Allowed from today at 12:00 PM", symbol: "xmark.octagon.fill", color: .red),
        Example(sign: "RESIDENT PERMIT PARKING ONLY", title: "Permit needed", detail: "Resident sticker required",
                symbol: "person.text.rectangle.fill", color: .orange),
    ]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var index = 0

    var body: some View {
        let example = examples[index]
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "text.viewfinder")
                Text("Example").textCase(.uppercase)
                Spacer()
                HStack(spacing: 5) {
                    ForEach(examples.indices, id: \.self) { i in
                        Capsule()
                            .fill(.white.opacity(i == index ? 0.9 : 0.3))
                            .frame(width: i == index ? 16 : 6, height: 6)
                    }
                }
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white.opacity(0.7))

            Group {
                Text(example.sign)
                    .font(.footnote.monospaced().weight(.medium))
                    .foregroundStyle(.white.opacity(0.85))
                HStack(spacing: 12) {
                    Image(systemName: example.symbol)
                        .font(.title)
                        .foregroundStyle(.white)
                        .frame(width: 48, height: 48)
                        .background(example.color.gradient, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(example.title).font(.headline)
                        Text(example.detail).font(.subheadline).foregroundStyle(.white.opacity(0.8))
                    }
                    .foregroundStyle(.white)
                }
            }
            .id(index)
            .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                    removal: .move(edge: .leading).combined(with: .opacity)))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(.white.opacity(0.18)))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .combine)
        .task {
            guard !reduceMotion else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3.2))
                withAnimation(.spring(response: 0.55, dampingFraction: 0.85)) { index = (index + 1) % examples.count }
            }
        }
    }
}

/// "Point → Read → Park" in three small steps.
struct HowItWorksRow: View {
    private let steps = [
        ("camera.viewfinder", "Point", "at any sign"),
        ("text.magnifyingglass", "Read", "on your iPhone"),
        ("car.fill", "Park", "with a reminder"),
    ]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                VStack(spacing: 6) {
                    Image(systemName: step.0)
                        .font(.title3.weight(.semibold))
                        .frame(width: 44, height: 44)
                        .background(.white.opacity(0.12), in: Circle())
                    Text(step.1).font(.subheadline.weight(.bold))
                    Text(step.2).font(.caption2).foregroundStyle(.white.opacity(0.65))
                }
                .frame(maxWidth: .infinity)
                if index < steps.count - 1 {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white.opacity(0.35))
                        .padding(.bottom, 30)
                }
            }
        }
        .foregroundStyle(.white)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Point at any sign, CurbLens reads it on your iPhone, then park with a reminder.")
    }
}
