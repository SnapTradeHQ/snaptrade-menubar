import SwiftUI

@main
struct SnapTradeMenuBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            MenuBarSettingsView(preferences: appDelegate.displayPreferences)
        }
        .commands {
            CommandGroup(replacing: .appSettings) { }
        }
    }
}
