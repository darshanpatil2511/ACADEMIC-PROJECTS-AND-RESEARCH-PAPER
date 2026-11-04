import CurbCore
import MapKit
import SwiftData
import SwiftUI

/// Saved signs on a map (pins colored by whether you can park there right now) or as a list.
struct SavedSignsView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case map = "Map", list = "List"
        var id: Self { self }
    }

    @Query(sort: \SavedSign.createdAt, order: .reverse) private var signs: [SavedSign]
    @Environment(\.modelContext) private var context
    @State private var mode: Mode = .map
    @State private var mapSelection: UUID?
    @State private var selected: SavedSign?
    @State private var position: MapCameraPosition = .automatic

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { timeline in
            Group {
                if signs.isEmpty {
                    ContentUnavailableView("No saved signs", systemImage: "mappin.slash",
                                           description: Text("Read a sign, then tap Save sign or I parked here."))
                } else if mode == .map {
                    map(now: timeline.date)
                } else {
                    list(now: timeline.date)
                }
            }
        }
        .navigationTitle("Saved signs")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("View", selection: $mode) {
                    ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(width: 180)
            }
        }
        .navigationDestination(item: $selected) { SavedSignDetailView(sign: $0) }
        .task {
            #if DEBUG
            // Debug aid: `-CurbLensOpenFirstSign YES` opens the newest sign (simulator screenshots).
            if UserDefaults.standard.bool(forKey: "CurbLensOpenFirstSign"), selected == nil { selected = signs.first }
            #endif
        }
        .onChange(of: mapSelection) { _, id in
            guard let id else { return }
            selected = signs.first { $0.id == id }
            mapSelection = nil
        }
    }

    private func map(now: Date) -> some View {
        Map(position: $position, selection: $mapSelection) {
            UserAnnotation()
            ForEach(signs) { sign in
                if let coordinate = sign.coordinate {
                    let tone = VerdictFormatter.present(sign.verdict(at: now), now: now, calendar: .boston).tone
                    Marker(sign.title, systemImage: "parkingsign", coordinate: coordinate)
                        .tint(tone.color)
                        .tag(sign.id)
                }
            }
        }
        .mapControls {
            MapUserLocationButton()
            MapCompass()
        }
        .overlay(alignment: .bottom) {
            let missing = signs.filter { $0.coordinate == nil }.count
            if missing > 0 {
                Text("\(missing) sign\(missing == 1 ? " has" : "s have") no location: see List")
                    .font(.footnote)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.bottom, 24)
            }
        }
    }

    private func list(now: Date) -> some View {
        let here = LocationProvider.shared.lastKnown
        return List {
            ForEach(signs) { sign in
                Button { selected = sign } label: {
                    SavedSignRow(sign: sign, now: now, distance: distance(from: here, to: sign))
                }
                .foregroundStyle(.primary)
            }
            .onDelete { offsets in
                offsets.map { signs[$0] }.forEach { ParkingService.delete($0, in: context, now: Date()) }
            }
        }
    }

    private func distance(from here: CLLocation?, to sign: SavedSign) -> String? {
        guard let here, let lat = sign.latitude, let lon = sign.longitude else { return nil }
        return GeoText.distanceLabel(meters: GeoText.distanceMeters(lat1: here.coordinate.latitude,
                                                                     lon1: here.coordinate.longitude,
                                                                     lat2: lat, lon2: lon))
    }
}

private struct SavedSignRow: View {
    let sign: SavedSign
    let now: Date
    let distance: String?

    var body: some View {
        let presentation = VerdictFormatter.present(sign.verdict(at: now), now: now, calendar: .boston)
        HStack(spacing: 12) {
            SignThumbnail(data: sign.photoJPEG)
                .frame(width: 56, height: 56)
            VStack(alignment: .leading, spacing: 3) {
                Text(sign.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                if !sign.note.isEmpty {
                    Text(sign.note).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Label(presentation.title, systemImage: presentation.tone.symbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(presentation.tone.color)
                Text([VerdictFormatter.relative(sign.createdAt, now: now, calendar: .boston), distance]
                        .compactMap { $0 }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

struct SignThumbnail: View {
    let data: Data?

    var body: some View {
        Group {
            if let data, let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: "parkingsign").font(.title2).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.quaternary)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
