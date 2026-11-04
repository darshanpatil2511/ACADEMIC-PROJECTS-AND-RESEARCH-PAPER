import CurbCore
import Foundation
import Observation
import PhotosUI
import SwiftUI

/// One finished read of a sign, shown by `ResultView`.
struct ScanResult: Identifiable, Hashable {
    let id = UUID()
    let reading: SignReading

    static func == (lhs: ScanResult, rhs: ScanResult) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// Loads a photo and runs the accurate reader off the main actor.
@MainActor
@Observable
final class ScanViewModel {
    enum Status: Equatable {
        case idle
        case reading
        case failed(String)
    }

    var status: Status = .idle
    var result: ScanResult?

    private let reader = SignReader()

    func read(item: PhotosPickerItem) async {
        status = .reading
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                status = .failed("Couldn't load that photo.")
                return
            }
            try await read { try ImageDecoding.decode(data: data) }
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    func read(fileURL: URL) async {
        status = .reading
        do {
            try await read { try ImageDecoding.decode(url: fileURL) }
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    private func read(decode: @escaping @Sendable () throws -> (CGImage, CGImagePropertyOrientation)) async throws {
        let reader = self.reader
        let reading = try await Task.detached(priority: .userInitiated) {
            let (image, orientation) = try decode()
            return try await reader.read(image: image, orientation: orientation, options: .accurate)
        }.value
        #if DEBUG
        let lines = reading.lines.sorted { $0.box.midY > $1.box.midY }.map(\.text)
        print("[CurbLens] lines: \(lines)\n[CurbLens] panels: \(reading.panels)\n[CurbLens] unparsed: \(reading.parse.unparsedTokens)")
        #endif
        result = ScanResult(reading: reading)
        status = .idle
    }
}
