import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import CurbCore

@Suite("Vision geometry")
struct VisionGeometryTests {
    private let size = CGSize(width: 400, height: 200)

    @Test func bottomLeftOriginIsAPureScale() {
        // Core Image shares Vision's bottom-left origin.
        let p = VisionGeometry.pixelPoint(CGPoint(x: 0.25, y: 0.75), imageSize: size, origin: .bottomLeft)
        #expect(p == CGPoint(x: 100, y: 150))
    }

    @Test func topLeftOriginFlipsY() {
        // A point near the TOP of the image in Vision (y = 0.75) is near the top in UIKit too (small y).
        let p = VisionGeometry.pixelPoint(CGPoint(x: 0.25, y: 0.75), imageSize: size, origin: .topLeft)
        #expect(p == CGPoint(x: 100, y: 50))
    }

    @Test func rectConversionKeepsSizeAndFlipsOrigin() {
        let r = CGRect(x: 0.1, y: 0.6, width: 0.5, height: 0.3)   // top band of the image
        #expect(VisionGeometry.pixelRect(r, imageSize: size, origin: .bottomLeft)
                == CGRect(x: 40, y: 120, width: 200, height: 60))
        let flipped = VisionGeometry.pixelRect(r, imageSize: size, origin: .topLeft)
        #expect(abs(flipped.minY - 20) < 1e-9)                    // (1 - 0.9) * 200
        #expect(flipped.size == CGSize(width: 200, height: 60))
    }

    @Test func quadProjectionMapsCornersAndIdentity() {
        // A tilted quadrilateral, like a sign photographed at an angle.
        let quad = Quad(topLeft: CGPoint(x: 0.2, y: 0.9), topRight: CGPoint(x: 0.7, y: 0.8),
                        bottomRight: CGPoint(x: 0.75, y: 0.2), bottomLeft: CGPoint(x: 0.15, y: 0.1))
        let close = { (a: CGPoint, b: CGPoint) in abs(a.x - b.x) < 1e-9 && abs(a.y - b.y) < 1e-9 }
        #expect(close(quad.project(CGPoint(x: 0, y: 0)), quad.bottomLeft))
        #expect(close(quad.project(CGPoint(x: 1, y: 0)), quad.bottomRight))
        #expect(close(quad.project(CGPoint(x: 1, y: 1)), quad.topRight))
        #expect(close(quad.project(CGPoint(x: 0, y: 1)), quad.topLeft))
        #expect(close(Quad.unit.project(CGPoint(x: 0.3, y: 0.6)), CGPoint(x: 0.3, y: 0.6)))
    }

    @Test func quadArea() {
        #expect(abs(Quad.unit.area - 1) < 1e-9)
    }
}

@Suite("PanelGrouper")
struct PanelGrouperTests {
    /// A line at a given vertical position (top of image = 1), bottom-left origin.
    private func line(_ text: String, top: CGFloat, x: CGFloat = 0.1, height: CGFloat = 0.05, width: CGFloat = 0.6) -> RecognizedLine {
        RecognizedLine(text: text, confidence: 1, box: CGRect(x: x, y: top - height, width: width, height: height))
    }

    @Test func readsTopToBottomAndSplitsOnKeywords() {
        let lines = [
            line("8AM - 12 NOON", top: 0.70),
            line("NO PARKING", top: 0.90),
            line("STREET CLEANING", top: 0.80),     // keyword line -> new panel
            line("TOW ZONE", top: 0.60),             // keyword line -> new panel
        ]
        #expect(PanelGrouper.panels(from: lines) == ["NO PARKING", "STREET CLEANING 8AM - 12 NOON", "TOW ZONE"])
    }

    @Test func largeGapStartsANewPanel() {
        let lines = [
            line("2 HOUR PARKING", top: 0.90),
            line("8AM-6PM", top: 0.84),
            line("EXCEPT SUNDAY", top: 0.30),        // far below: a different sign
        ]
        #expect(PanelGrouper.panels(from: lines) == ["2 HOUR PARKING 8AM-6PM", "EXCEPT SUNDAY"])
    }

    @Test func sameRowFragmentsJoinLeftToRight() {
        let lines = [
            line("PARKING", top: 0.90, x: 0.3, width: 0.5),
            line("2 HR", top: 0.90, x: 0.05, width: 0.2),
        ]
        #expect(PanelGrouper.panels(from: lines) == ["2 HR PARKING"])
    }
}

// MARK: - Real photos (skipped in CI with SKIP_VISION=1)

private let visionEnabled = ProcessInfo.processInfo.environment["SKIP_VISION"] != "1"

private func readFixture(_ name: String) async throws -> SignReading {
    guard let url = Bundle.module.url(forResource: name, withExtension: "jpeg", subdirectory: "Fixtures/images"),
          let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
        throw CocoaError(.fileNoSuchFile)
    }
    return try await SignReader().read(image: image, orientation: .up)
}

@Suite("SignReader on real photos", .enabled(if: visionEnabled, "set SKIP_VISION=1 to skip"), .serialized)
struct SignReaderPhotoTests {
    @Test func southEndPoleWithStreetCleaningAndSnowPanels() async throws {
        let rules = try await readFixture("south_end_2hr_street_cleaning_snow").parse.rules.map(\.withoutSource)
        #expect(rules.contains(ParkingRule(kind: .timeLimit(minutes: 120), days: .days([.mon, .tue, .wed, .thu, .fri]),
                                           window: TimeWindow(start: TimeOfDay(hour: 8), end: TimeOfDay(hour: 18)),
                                           season: nil, towZone: false, residentExempt: true, sourceText: "")))
        #expect(rules.contains { $0.kind == .streetCleaning && $0.days == .days([.tue]) && $0.towZone })
        #expect(rules.contains { $0.kind == .snowEmergency })
    }

    @Test func meterPoleFindsPickupZoneAndTwoHourMeter() async throws {
        let rules = try await readFixture("meter_pickup_dropoff_pole").parse.rules
        #expect(rules.contains { $0.kind == .loadingZone && $0.towZone })
        #expect(rules.contains { $0.kind == .timeLimit(minutes: 120) })
    }

    @Test func residentPermitOnly() async throws {
        let rules = try await readFixture("resident_permit_only").parse.rules
        #expect(rules.map(\.kind) == [.permitOnly(zone: nil)])
    }

    @Test func commercialVehiclesIsNotParkableForRegularCars() async throws {
        let rules = try await readFixture("commercial_vehicles_tow_zone").parse.rules
        #expect(rules.contains { $0.kind == .loadingZone && $0.towZone })
        #expect(!rules.contains { if case .timeLimit = $0.kind { return true }; return false })
    }

    @Test func glareHidesTheHourWord() async throws {
        let reading = try await readFixture("two_hr_except_sundays_glare")
        withKnownIssue("OCR reads '12 PARKING' — the 'HR' sits in the glare, so no time limit can be parsed") {
            #expect(!reading.parse.rules.isEmpty)
        }
    }

    @Test func timingsArePositive() async throws {
        let t = try await readFixture("resident_permit_only").timings
        #expect(t.ocr > 0 && t.total >= t.ocr)
    }
}
