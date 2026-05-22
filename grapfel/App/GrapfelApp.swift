import SwiftUI

@main
struct GrapfelApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        // Preferences window — opens with ⌘,
        Settings {
            if ProcessInfo.processInfo.environment["XCTestSessionIdentifier"] == nil {
                SettingsView()
            }
        }
    }
}
