import SwiftUI

@main
struct ProsciuttoApp: App {
    var body: some Scene {
        MenuBarExtra("Prosciutto", systemImage: "rectangle.stack") {
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }
    }
}
