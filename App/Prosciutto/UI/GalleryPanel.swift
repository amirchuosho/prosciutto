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

    deinit { NotificationCenter.default.removeObserver(self) }

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
        let height: CGFloat = 464
        let v = screen.visibleFrame
        return NSRect(x: v.minX + margin, y: v.minY + margin,
                      width: v.width - margin * 2, height: height)
    }

    /// Off-screen below the bottom edge — the panel slides up from / down to here.
    private func belowFrame(from full: NSRect) -> NSRect {
        NSRect(x: full.minX, y: full.minY - full.height - 40,
               width: full.width, height: full.height)
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
        panel.setFrame(belowFrame(from: full), display: false)
        panel.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.28
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1, 0.3, 1) // ease-out-expo-ish
            panel.animator().setFrame(full, display: true)
            panel.animator().alphaValue = 1
        }
    }

    /// Slide down off the bottom edge, then hide and return focus to the prior app.
    /// `completion` runs after the panel is fully hidden and focus restored.
    func hide(completion: (() -> Void)? = nil) {
        guard panel.isVisible else { completion?(); return }
        let finish: () -> Void = { [weak self] in
            guard let self else { return }
            self.panel.orderOut(nil)
            self.panel.alphaValue = 1
            self.previousApp?.activate()
            completion?()
        }
        if reduceMotion { finish(); return }
        let below = belowFrame(from: panel.frame)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().setFrame(below, display: true)
            panel.animator().alphaValue = 0
        } completionHandler: { finish() }
    }
}
