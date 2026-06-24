import AppKit
import SwiftUI

/// A borderless panel that CAN become key (the default NSPanel refuses, which
/// is why keyboard input never reached the gallery). We still preserve the
/// previously-active app so paste can target it.
final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class GalleryPanel {
    private let panel: KeyablePanel
    /// The app that was frontmost when the gallery opened — paste returns here.
    private(set) var previousApp: NSRunningApplication?

    init(content: @escaping () -> AnyView) {
        panel = KeyablePanel(contentRect: NSRect(x: 0, y: 0, width: 800, height: 240),
                             styleMask: [.borderless, .nonactivatingPanel],
                             backing: .buffered, defer: true)
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.animationBehavior = .utilityWindow
        let host = NSHostingView(rootView: content())
        host.autoresizingMask = [.width, .height]
        panel.contentView = host
    }

    func show() {
        guard let screen = NSScreen.main else { return }
        previousApp = NSWorkspace.shared.frontmostApplication
        let margin: CGFloat = 18
        let height: CGFloat = 252
        let visible = screen.visibleFrame
        panel.setFrame(NSRect(x: visible.minX + margin,
                              y: visible.minY + margin,
                              width: visible.width - margin * 2,
                              height: height),
                       display: true)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    /// Hide and return focus to the app the user was in.
    func hide() {
        panel.orderOut(nil)
        previousApp?.activate()
    }

    func toggle() { panel.isVisible ? hide() : show() }

    var isVisible: Bool { panel.isVisible }
}
