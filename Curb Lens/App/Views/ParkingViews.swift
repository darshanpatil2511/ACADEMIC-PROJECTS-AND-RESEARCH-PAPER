import CurbCore
import SwiftData
import SwiftUI

extension VerdictPresentation.Tone {
    var color: Color {
        switch self {
        case .go: return .green
        case .stop: return .red
        case .unknown: return .gray
        }
    }

    var symbol: String {
        switch self {
        case .go: return "checkmark.circle.fill"
        case .stop: return "xmark.octagon.fill"
        case .unknown: return "questionmark.circle.fill"
        }
    }
}

/// "I parked here": saves the sign if needed, records the session and schedules move-by reminders.
struct ParkHereButton: View {
    /// Whether the verdict right now allows parking.
    let canPark: Bool
    /// Returns the saved sign to park at (saving it first when needed).
    let resolveSign: @MainActor () async -> SavedSign?

    @Environment(\.modelContext) private var context
    @State private var busy = false
    @State private var message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                Task { await park() }
            } label: {
                Group {
                    if busy {
                        ProgressView()
                    } else {
                        Label(canPark ? "I parked here" : "Can't park here now", systemImage: "car.fill")
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!canPark || busy)
            if let message {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func park() async {
        busy = true
        defer { busy = false }
        guard let sign = await resolveSign() else { return }
        let fix = await LocationProvider.shared.currentFix()
        guard let outcome = await ParkingService.park(at: sign, location: fix, in: context, now: Date()) else {
            message = "Parking isn't allowed here right now."
            return
        }
        if outcome.session.moveBy == nil {
            message = "Parked. No time limit in the next 8 days, so no reminders."
        } else if !outcome.notificationsAllowed {
            message = "Parked. Notifications are off: turn them on in Settings to get move-by reminders."
        } else {
            message = "Parked. You'll get \(outcome.remindersScheduled) reminder\(outcome.remindersScheduled == 1 ? "" : "s") before the move-by time."
        }
    }
}

/// Home-screen card for the active parking session.
struct ParkedBanner: View {
    let session: ParkingSession

    @Environment(\.modelContext) private var context
    @Environment(\.openURL) private var openURL

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { timeline in
            let now = timeline.date
            let overdue = session.moveBy.map { $0 <= now } ?? false
            VStack(alignment: .leading, spacing: 10) {
                Label(overdue ? "Time to move your car" : "Parked", systemImage: "car.fill")
                    .font(.headline)
                Text(detail(now: now))
                    .font(.subheadline)
                HStack {
                    // Value-based: an eager `NavigationLink { SavedSignDetailView }` inside this
                    // TimelineView left the whole home screen blank on launch.
                    if let sign = session.sign {
                        NavigationLink("Sign", value: sign)
                    }
                    if let coordinate = session.coordinate,
                       let url = URL(string: "maps://?ll=\(coordinate.latitude),\(coordinate.longitude)&q=Parked%20car") {
                        Button("Find car") { openURL(url) }
                    }
                    Spacer()
                    Button("I've left") { ParkingService.end(session, in: context, now: Date()) }
                        .fontWeight(.semibold)
                }
                .buttonStyle(.bordered)
                .tint(.white)
            }
            .foregroundStyle(.white)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background((overdue ? Color.red : Color.blue).gradient, in: RoundedRectangle(cornerRadius: 16))
        }
    }

    private func detail(now: Date) -> String {
        let since = "since " + VerdictFormatter.relative(session.startedAt, now: now, calendar: .boston)
        guard let moveBy = session.moveBy else { return "No time limit · \(since)" }
        return "Move by \(VerdictFormatter.relative(moveBy, now: now, calendar: .boston)) · \(since)"
    }
}
