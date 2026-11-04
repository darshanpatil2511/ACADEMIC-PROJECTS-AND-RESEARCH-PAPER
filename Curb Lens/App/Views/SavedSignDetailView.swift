import CurbCore
import MapKit
import SwiftData
import SwiftUI

/// One saved sign: today's verdict, "I parked here", the rules, the photo and where it is.
struct SavedSignDetailView: View {
    @Bindable var sign: SavedSign

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var confirmDelete = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { timeline in
            let now = timeline.date
            let verdict = sign.verdict(at: now)
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VerdictCard(presentation: VerdictFormatter.present(verdict, now: now, calendar: .boston),
                                towZone: RuleEngine.towZoneApplies(rules: sign.rules, verdict: verdict,
                                                                   at: now, calendar: .boston))
                    ParkHereButton(canPark: verdict.isCanPark) { sign }
                    rulesSection
                    noteSection
                    locationSection
                    if let data = sign.photoJPEG, let image = UIImage(data: data) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Photo").font(.headline)
                            Image(uiImage: image).resizable().scaledToFit()
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    }
                    Text("Saved \(VerdictFormatter.relative(sign.createdAt, now: now, calendar: .boston))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding()
            }
        }
        .navigationTitle("Saved sign")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .destructive) { confirmDelete = true } label: { Image(systemName: "trash") }
            }
        }
        .confirmationDialog("Delete this sign?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                ParkingService.delete(sign, in: context, now: Date())
                dismiss()
            }
        }
    }

    @ViewBuilder private var rulesSection: some View {
        let rules = sign.rules
        VStack(alignment: .leading, spacing: 8) {
            Text("What the sign says").font(.headline)
            if rules.isEmpty {
                Text("No rules were read from this sign.").foregroundStyle(.secondary)
            }
            ForEach(Array(rules.enumerated()), id: \.offset) { _, rule in
                Text("• " + RuleDescriber.describe(rule))
            }
        }
    }

    private var noteSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Note").font(.headline)
            TextField("e.g. my side of the street, meter broken", text: $sign.note, axis: .vertical)
                .lineLimit(1...4)
                .textFieldStyle(.roundedBorder)
                .submitLabel(.done)
        }
    }

    @ViewBuilder private var locationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Location").font(.headline)
            if let coordinate = sign.coordinate {
                Map(initialPosition: .camera(MapCamera(centerCoordinate: coordinate, distance: 400,
                                                       heading: sign.headingDegrees ?? 0))) {
                    Marker("Sign", systemImage: "parkingsign", coordinate: coordinate)
                }
                .frame(height: 180)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .allowsHitTesting(false)
                HStack {
                    Text(locationDetail).font(.footnote).foregroundStyle(.secondary)
                    Spacer()
                    if let url = URL(string: "maps://?ll=\(coordinate.latitude),\(coordinate.longitude)&q=Parking%20sign") {
                        Button("Open in Maps") { openURL(url) }.font(.footnote)
                    }
                }
            } else {
                Text("Saved without a location (location permission was off or no fix arrived).")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// "Facing NE · camera 12° up · within 8 m"
    private var locationDetail: String {
        var parts: [String] = []
        if let heading = sign.headingDegrees { parts.append("Facing \(GeoText.cardinal(heading))") }
        if let pitch = sign.pitchDegrees { parts.append(GeoText.pitchLabel(degrees: pitch)) }
        if let accuracy = sign.accuracyMeters, accuracy > 0 { parts.append("within \(Int(accuracy.rounded())) m") }
        return parts.isEmpty ? "Location saved" : parts.joined(separator: " · ")
    }
}
