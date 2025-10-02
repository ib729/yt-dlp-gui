import SwiftUI

@main
struct yt_dlp_guiApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified)
        .defaultSize(width: 1100, height: 720)
        .defaultMinimumSize(width: 900, height: 620)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Preferences...") {
                    NotificationCenter.default.post(name: .openSettings, object: nil)
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}

extension Notification.Name {
    static let openSettings = Notification.Name("openSettings")
}
