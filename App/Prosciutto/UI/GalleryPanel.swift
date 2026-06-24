import AppKit
import SwiftUI

final class GalleryPanel {
    private let panel: NSPanel

    init(content: @escaping () -> AnyView) {
        panel = NSPanel(contentRect: .zero,
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: true)
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        let host = NSHostingView(rootView: content())
        host.autoresizingMask = [.width, .height]
        panel.contentView = host
    }

    func show() {
        guard let screen = NSScreen.main else { return }
        let height: CGFloat = 220
        let margin: CGFloat = 16
        let visible = screen.visibleFrame
        panel.setFrame(NSRect(x: visible.minX + margin,
                              y: visible.minY + margin,
                              width: visible.width - margin * 2,
                              height: height),
                       display: true)
        panel.orderFrontRegardless()
    }

    func hide() { panel.orderOut(nil) }

    func toggle() { panel.isVisible ? hide() : show() }

    var isVisible: Bool { panel.isVisible }
}
