import AppKit

extension Notification.Name {
    static let prosciuttoOpenGallery = Notification.Name("prosciuttoOpenGallery")
}

/// Handles the user re-opening the app (clicking its icon in Launchpad/Dock
/// while it's already running in the menu bar) by showing the gallery.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        NotificationCenter.default.post(name: .prosciuttoOpenGallery, object: nil)
        return true
    }
}
