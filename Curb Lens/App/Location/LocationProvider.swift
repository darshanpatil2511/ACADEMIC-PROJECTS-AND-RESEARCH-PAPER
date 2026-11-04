import CoreLocation
import Foundation

/// A one-off position (and compass heading, when available).
struct LocationFix: Equatable {
    var latitude: Double
    var longitude: Double
    var accuracyMeters: Double
    /// Degrees from north the back camera faces; nil without a compass reading.
    var headingDegrees: Double?
}

/// One-shot location + heading for saving signs and parked cars. Asks for "When In Use" permission the
/// first time. Returns nil when permission is denied or no fix arrives in time; callers save without a location.
@MainActor
final class LocationProvider: NSObject, CLLocationManagerDelegate {
    static let shared = LocationProvider()

    private let manager = CLLocationManager()
    private var authWaiters: [CheckedContinuation<Void, Never>] = []
    private var locationWaiters: [CheckedContinuation<CLLocation?, Never>] = []
    /// Bumped per location request so a stale timeout can't resolve a newer request.
    private var requestGeneration = 0

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.headingOrientation = .portrait
    }

    var isAuthorized: Bool {
        manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways
    }

    /// The last known location without prompting or waiting (for distances in lists).
    var lastKnown: CLLocation? { isAuthorized ? manager.location : nil }

    func currentFix(timeout: TimeInterval = 8) async -> LocationFix? {
        if manager.authorizationStatus == .notDetermined {
            await withCheckedContinuation { continuation in
                authWaiters.append(continuation)
                manager.requestWhenInUseAuthorization()
            }
        }
        guard isAuthorized else { return nil }

        let headingOn = CLLocationManager.headingAvailable()
        if headingOn { manager.startUpdatingHeading() }
        defer { if headingOn { manager.stopUpdatingHeading() } }

        let location: CLLocation?
        if let recent = manager.location, -recent.timestamp.timeIntervalSinceNow < 30, recent.horizontalAccuracy <= 50 {
            location = recent
        } else {
            location = await requestLocation(timeout: timeout)
        }
        guard let location else { return nil }

        // The compass usually reports within a fraction of a second of starting.
        if headingOn {
            for _ in 0..<10 where manager.heading == nil {
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
        return LocationFix(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude,
                           accuracyMeters: location.horizontalAccuracy, headingDegrees: Self.degrees(manager.heading))
    }

    private static func degrees(_ heading: CLHeading?) -> Double? {
        guard let heading, heading.headingAccuracy >= 0 else { return nil }
        return heading.trueHeading >= 0 ? heading.trueHeading : heading.magneticHeading
    }

    private func requestLocation(timeout: TimeInterval) async -> CLLocation? {
        await withCheckedContinuation { continuation in
            locationWaiters.append(continuation)
            guard locationWaiters.count == 1 else { return }     // a request is already in flight
            requestGeneration += 1
            let generation = requestGeneration
            manager.requestLocation()
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(timeout))
                guard let self, self.requestGeneration == generation else { return }
                self.resolveLocation(nil)
            }
        }
    }

    private func resolveLocation(_ location: CLLocation?) {
        let waiters = locationWaiters
        locationWaiters = []
        requestGeneration += 1
        waiters.forEach { $0.resume(returning: location) }
    }

    // MARK: CLLocationManagerDelegate (called on the main thread: the manager was created there)

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        MainActor.assumeIsolated {
            guard manager.authorizationStatus != .notDetermined else { return }
            let waiters = authWaiters
            authWaiters = []
            waiters.forEach { $0.resume() }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        MainActor.assumeIsolated { resolveLocation(locations.last) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        MainActor.assumeIsolated { resolveLocation(nil) }
    }
}
