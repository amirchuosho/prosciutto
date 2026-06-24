import AppKit
import SwiftUI

/// A borderless panel that CAN become key (the default NSPanel refuses, which
/// is why keyboard input never reached the gallery). We still preserve the
/// previously-active app so paste can target it.
final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class GalleryPanel: NSObject {
    private let panel: KeyablePanel
    /// The app that was frontmost when the gallery opened — paste returns here.
    private(set) var previousApp: NSRunningApplication?
    /// Called when the panel loses key focus (click outside), unless a sheet is up.
    var onResign: (() -> Void)?

    init(content: @escaping () -> AnyView) {
        panel = KeyablePanel(contentRect: NSRect(x: 0, y: 0, width: 900, height: 260),
                             styleMask: [.borderless, .nonactivatingPanel],
                             backing: .buffered, defer: true)
        super.init()
        panel.level = .popUpMenu                       // above floating windows / most apps
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

        NotificationCenter.default.addObserver(
            self, selector: #selector(panelResignedKey),
            name: NSWindow.didResignKeyNotification, object: panel)
    }

    @objc private func panelResignedKey() {
        // Ignore when a sheet (edit / new-section alert) is what took focus.
        guard panel.attachedSheet == nil else { return }
        onResign?()
    }

    var hasSheet: Bool { panel.attachedSheet != nil }
    var isVisible: Bool { panel.isVisible }

    func show() {
        guard let screen = NSScreen.main else { return }
        previousApp = NSWorkspace.shared.frontmostApplication
        let margin: CGFloat = 18
        let height: CGFloat = 272
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
}
