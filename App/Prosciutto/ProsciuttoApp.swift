import SwiftUI

@main
struct ProsciuttoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var env = AppEnvironment.shared

    init() { FontRegistrar.registerBundledFonts() }

    var body: some Scene {
        MenuBarExtra {
            MenuContent(env: env)
        } label: {
            Image("HamBar")
                .renderingMode(.template)
        }

        Settings {
            SettingsView()
                .environmentObject(env.theme)
        }
    }
}

private struct MenuContent: View {
    @ObservedObject var env: AppEnvironment
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Button("Open Prosciutto") { env.openGallery() }
            .keyboardShortcut("v", modifiers: [.command, .shift])
        Divider()
        if env.pasteIsInstalled {
            Button("Import from Paste…") { env.importFromPaste() }
            Divider()
        }
        Button(env.isPaused ? "Resume Capture" : "Pause Capture") { env.togglePause() }
        Button("Settings…") {
            NSApp.activate(ignoringOtherApps: true)
            openSettings()
        }
        .keyboardShortcut(",", modifiers: .command)
        Divider()
        Button("Quit Prosciutto") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }
}
