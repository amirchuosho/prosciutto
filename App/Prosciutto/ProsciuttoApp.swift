import SwiftUI

@main
struct ProsciuttoApp: App {
    @StateObject private var env = AppEnvironment()

    var body: some Scene {
        MenuBarExtra("Prosciutto", systemImage: "rectangle.stack") {
            Button("Open Prosciutto") { env.openGallery() }
                .keyboardShortcut("v", modifiers: [.command, .shift])
            Divider()
            Button(env.isPaused ? "Resume Capture" : "Pause Capture") { env.togglePause() }
            SettingsLink { Text("Settings…") }
                .keyboardShortcut(",", modifiers: .command)
            Divider()
            Button("Quit Prosciutto") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }

        Settings {
            SettingsView()
        }
    }
}
