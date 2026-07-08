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
        panel.isFloatingPanel = true
        // Level MUST be set after `isFloatingPanel`, which otherwise forces it back to
        // `.floating` (3) — below the Dock (20), so the strip rendered *behind* a visible
        // Dock. `.popUpMenu` (101) sits above the Dock, covering it while the strip is up
        // (like Paste), matching the strip now anchoring to the true screen bottom.
        panel.level = .popUpMenu
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

    /// True when an event belongs to this panel's window — lets app-wide event
    /// monitors (e.g. the scroll-to-navigate monitor) scope themselves to the strip
    /// rather than firing over the Settings window too.
    func owns(_ window: NSWindow?) -> Bool { window === panel }

    /// The screen to show on: the one under the cursor (where the user is looking),
    /// falling back to the key/main screen, then the primary. Keeps the strip on the
    /// active display in multi-monitor setups instead of always the main one.
    private func activeScreen() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
            ?? NSScreen.main ?? NSScreen.screens.first
    }

    /// Used only if the hosting view can't yet produce a real fitting size (measured
    /// before first layout) — a reasonable strip height so the panel is never zero-sized.
    private static let fallbackContentHeight: CGFloat = 452

    /// The strip's real content height, measured from the SwiftUI hosting view at the
    /// target width — so the window is sized to what's actually drawn, with no hardcoded
    /// height that drifts across machines/fonts. Falls back to a sane value if layout
    /// hasn't produced a size yet.
    private func measuredContentHeight(forWidth width: CGFloat) -> CGFloat {
        guard let host = panel.contentView else { return Self.fallbackContentHeight }
        host.setFrameSize(NSSize(width: width, height: host.frame.height))
        host.layoutSubtreeIfNeeded()
        let h = host.fittingSize.height
        return h > 1 ? h : Self.fallbackContentHeight
    }

    private func targetFrame() -> NSRect? {
        guard let screen = activeScreen() else { return nil }
        let margin: CGFloat = 18
        let width = screen.frame.width - margin * 2
        let contentHeight = measuredContentHeight(forWidth: width)
        return Self.panelFrame(inScreen: screen.frame, contentHeight: contentHeight, margin: margin)
    }

    /// Pure geometry: the strip's frame within a screen. Anchored to the screen's TRUE
    /// bottom edge (over the dock, like Paste) — NOT the visible frame, which would
    /// float it above the dock. Sized to the real content height (no magic number),
    /// clamped so it always fits even on a tiny display.
    static func panelFrame(inScreen screen: NSRect, contentHeight: CGFloat,
                           margin: CGFloat) -> NSRect {
        let height = min(contentHeight, screen.height - margin * 2)
        return NSRect(x: screen.minX + margin, y: screen.minY + margin,
                      width: screen.width - margin * 2, height: height)
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
    /// - Parameter restoreFocus: whether to re-activate the app that was frontmost
    ///   when the gallery opened. TRUE for deliberate dismissals while Prosciutto is
    ///   active (paste needs the target app front; Escape / close returns you there).
    ///   FALSE when the gallery is dismissed *because* the user switched to another
    ///   app — that app is now frontmost, and re-activating previousApp would yank
    ///   focus off it (e.g. opening Finder while the gallery is up shoved Finder
    ///   behind). Making this explicit avoids racing the resign notification against
    ///   `NSApp.isActive`.
    func hide(restoreFocus: Bool = true, completion: (() -> Void)? = nil) {
        guard panel.isVisible else { completion?(); return }
        let finish: () -> Void = { [weak self] in
            guard let self else { return }
            self.panel.orderOut(nil)
            self.panel.alphaValue = 1
            if restoreFocus { self.previousApp?.activate() }
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
