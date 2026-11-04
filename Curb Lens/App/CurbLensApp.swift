import SwiftData
import SwiftUI
import UserNotifications

@main
struct CurbLensApp: App {
    /// Kept alive for the app's lifetime; the notification center holds it weakly.
    private let notificationDelegate = ForegroundNotificationDelegate()

    init() {
        UNUserNotificationCenter.current().delegate = notificationDelegate
    }

    var body: some Scene {
        WindowGroup {
            HomeView()
        }
        .modelContainer(for: [SavedSign.self, ParkingSession.self])
    }
}
