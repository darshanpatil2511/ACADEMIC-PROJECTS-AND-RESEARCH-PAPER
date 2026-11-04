import CurbCore
import SwiftData
import SwiftUI

struct ResultView: View {
    let result: ScanResult

    @Environment(\.modelContext) private var context
    /// Set once the sign is saved (by "Save sign" or "I parked here").
    @State private var savedSign: SavedSign?
    @State private var saving = false
    @State private var overrideTime = false
    @State private var testReminderStatus: String?
    @State private var customTime = Date()

    private let calendar = Calendar.boston
    private var reading: SignReading { result.reading }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let now = overrideTime ? customTime : context.date
            let verdict = RuleEngine.evaluate(rules: reading.parse.rules, arrival: now,
                                              calendar: calendar, permitZone: nil)
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VerdictCard(presentation: VerdictFormatter.present(verdict, now: now, calendar: calendar),
                                towZone: RuleEngine.towZoneApplies(rules: reading.parse.rules, verdict: verdict,
                                                                   at: now, calendar: calendar))
                    // Parking always uses the real clock, even with the debug time override on.
                    ParkHereButton(canPark: currentVerdictAllowsParking) { await saveIfNeeded() }
                    saveButton
                    if needsDoubleCheck { warningRow }
                    rulesSection
                    photoSection
                    rawTextSection
                    #if DEBUG
                    debugTimeSection
                    #endif
                    Text("Always check the sign yourself. Holidays and temporary signs aren't handled.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)
                }
                .padding()
            }
        }
        .navigationTitle("Sign")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: applyDemoTimeIfRequested)
        .task { await parkIfDemoRequested() }
    }

    // MARK: Saving

    private var currentVerdictAllowsParking: Bool {
        RuleEngine.evaluate(rules: reading.parse.rules, arrival: Date(), calendar: calendar, permitZone: nil).isCanPark
    }

    private var saveButton: some View {
        Button {
            Task { _ = await saveIfNeeded() }
        } label: {
            Group {
                if saving {
                    ProgressView()
                } else if savedSign != nil {
                    Label("Saved", systemImage: "checkmark")
                } else {
                    Label("Save sign", systemImage: "mappin.and.ellipse")
                }
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .disabled(saving || savedSign != nil)
    }

    /// Saves the sign with the current location the first time; later calls return the same sign.
    private func saveIfNeeded() async -> SavedSign? {
        if let savedSign { return savedSign }
        saving = true
        defer { saving = false }
        // Scanner captures already carry the fix from the moment of capture; imported photos use where you are now.
        let fix: LocationFix?
        if let captured = result.captureFix { fix = captured } else { fix = await LocationProvider.shared.currentFix() }
        let sign = ParkingService.saveSign(reading, location: fix, pitchDegrees: result.capturePitchDegrees,
                                           in: context, now: Date())
        savedSign = sign
        return sign
    }

    // MARK: Sections

    private var needsDoubleCheck: Bool {
        reading.parse.confidence < 0.7 || !reading.parse.unparsedTokens.isEmpty
    }

    private var warningRow: some View {
        Label("Some text wasn't understood — double-check the sign.", systemImage: "exclamationmark.triangle.fill")
            .font(.subheadline)
            .foregroundStyle(.orange)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder private var rulesSection: some View {
        if !reading.parse.rules.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("What the sign says").font(.headline)
                ForEach(Array(reading.parse.rules.enumerated()), id: \.offset) { _, rule in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Image(systemName: icon(for: rule.kind))
                            .foregroundStyle(.secondary)
                            .frame(width: 22)
                        Text(RuleDescriber.describe(rule))
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private var photoSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(reading.signQuad == nil ? "Photo" : "Detected sign").font(.headline)
            AnnotatedImageView(image: reading.ocrImage, boxes: reading.lines.map(\.box))
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    private var rawTextSection: some View {
        DisclosureGroup("Raw text") {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(reading.panels.enumerated()), id: \.offset) { index, panel in
                    Text("\(index + 1). \(panel)")
                        .font(.footnote.monospaced())
                }
                if !reading.parse.unparsedTokens.isEmpty {
                    Text("Not understood: \(reading.parse.unparsedTokens.joined(separator: " "))")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
                Text(String(format: "Confidence %.0f%% · read in %.0f ms",
                            reading.parse.confidence * 100, reading.timings.total))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 6)
        }
    }

    #if DEBUG
    private var debugTimeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Override time (debug)", isOn: $overrideTime)
            if overrideTime {
                DatePicker("Pretend it's", selection: $customTime)
                    .environment(\.timeZone, calendar.timeZone)
            }
            Divider()
            Button("Send test reminder in 1 minute") {
                Task {
                    let ok = await ReminderScheduler.scheduleTestReminder(rules: reading.parse.rules, now: Date())
                    testReminderStatus = ok ? "Scheduled. Lock the phone and wait a minute."
                                            : "Notifications are off for CurbLens (Settings → Notifications)."
                }
            }
            if let testReminderStatus {
                Text(testReminderStatus).font(.footnote).foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
    }
    #endif

    private func icon(for kind: RestrictionKind) -> String {
        switch kind {
        case .noParking, .noStopping: return "nosign"
        case .streetCleaning: return "wind"
        case .loadingZone: return "shippingbox"
        case .timeLimit: return "clock"
        case .permitOnly: return "person.text.rectangle"
        case .snowEmergency: return "snowflake"
        }
    }

    /// Debug aid: `-CurbLensDemoPark YES` saves the sign and starts a parking session (simulator screenshots).
    private func parkIfDemoRequested() async {
        #if DEBUG
        guard UserDefaults.standard.bool(forKey: "CurbLensDemoPark"), savedSign == nil,
              let sign = await saveIfNeeded() else { return }
        let outcome = await ParkingService.park(at: sign, location: sign.fix, in: context, now: Date(),
                                                  scheduleReminders: false)
        print("[CurbLens] demo park: moveBy=\(String(describing: outcome?.session.moveBy)) reminders=\(outcome?.remindersScheduled ?? -1)")
        #endif
    }

    /// Debug aid: `-CurbLensDemoTime 2026-11-10T09:00` starts with the time override on.
    private func applyDemoTimeIfRequested() {
        #if DEBUG
        guard let text = UserDefaults.standard.string(forKey: "CurbLensDemoTime") else { return }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
        if let date = formatter.date(from: text) {
            customTime = date
            overrideTime = true
        }
        #endif
    }
}

// MARK: - Components

struct VerdictCard: View {
    let presentation: VerdictPresentation
    let towZone: Bool

    private var color: Color { presentation.tone.color }
    private var symbol: String { presentation.tone.symbol }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                Image(systemName: symbol).font(.title)
                VStack(alignment: .leading, spacing: 4) {
                    Text(presentation.title).font(.title2.bold())
                    Text(presentation.detail).font(.body)
                }
                Spacer(minLength: 0)
            }
            if towZone {
                Label("Tow zone", systemImage: "car.rear.and.tire.marks")
                    .font(.subheadline.bold())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(.white.opacity(0.25), in: Capsule())
            }
            ForEach(presentation.notes, id: \.self) { note in
                Label(note, systemImage: "info.circle")
                    .font(.footnote)
            }
        }
        .foregroundStyle(.white)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.gradient, in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
    }
}

/// The image OCR ran on, with each recognized line outlined.
struct AnnotatedImageView: View {
    let image: CGImage
    /// Normalized, bottom-left origin (Vision).
    let boxes: [CGRect]

    var body: some View {
        Image(decorative: image, scale: 1)
            .resizable()
            .scaledToFit()
            .overlay {
                GeometryReader { geo in
                    ForEach(Array(boxes.enumerated()), id: \.offset) { _, box in
                        let rect = VisionGeometry.pixelRect(box, imageSize: geo.size, origin: .topLeft)
                        Rectangle()
                            .stroke(.yellow, lineWidth: 2)
                            .frame(width: rect.width, height: rect.height)
                            .position(x: rect.midX, y: rect.midY)
                    }
                }
            }
    }
}
