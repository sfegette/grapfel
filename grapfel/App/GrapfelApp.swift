import SwiftUI

@main
struct GrapfelApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        // Preferences window — opens with ⌘,
        Settings {
            SettingsView()
        }
    }
}
