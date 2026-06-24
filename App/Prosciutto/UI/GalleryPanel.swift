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

    private func targetFrame() -> NSRect? {
        guard let screen = NSScreen.main else { return nil }
        let margin: CGFloat = 18
        let height: CGFloat = 410
        let v = screen.visibleFrame
        return NSRect(x: v.minX + margin, y: v.minY + margin,
                      width: v.width - margin * 2, height: height)
    }

    /// A small frame near the top-right (menu bar) for the minimize/expand effect.
    private func minimizedFrame(from full: NSRect) -> NSRect {
        guard let screen = NSScreen.main else { return full }
        let v = screen.visibleFrame
        let w = full.width * 0.22, h = full.height * 0.22
        return NSRect(x: v.maxX - w - 12, y: v.maxY - h - 6, width: w, height: h)
    }

    private var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    func show() {
        guard let full = targetFrame() else { return }
        previousApp = NSWorkspace.shared.frontmostApplication
        NSApp.activate(ignoringOtherApps: true)

        if reduceMotion {
            panel.alphaValue = 1
            panel.setFrame(full, display: true)
            panel.makeKeyAndOrderFront(nil)
            return
        }

        panel.alphaValue = 0
        panel.setFrame(minimizedFrame(from: full), display: false)
        panel.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.24
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(full, display: true)
            panel.animator().alphaValue = 1
        }
    }

    /// Minimize toward the menu bar, then hide and return focus to the prior app.
    func hide() {
        guard panel.isVisible else { return }
        if reduceMotion {
            panel.orderOut(nil)
            panel.alphaValue = 1
            previousApp?.activate()
            return
        }
        let mini = minimizedFrame(from: panel.frame)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().setFrame(mini, display: true)
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            guard let self else { return }
            self.panel.orderOut(nil)
            self.panel.alphaValue = 1
            self.previousApp?.activate()
        }
    }
}
