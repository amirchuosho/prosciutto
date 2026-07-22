import AppKit
import SwiftUI
import ProsciuttoKit

/// A borderless, non-key child panel that shows a large image preview floating ABOVE
/// the gallery strip, with a downward tail pointing at the card it belongs to — so it
/// reads as "expanded from" that item (Paste-style).
///
/// Why a separate panel and not an in-strip overlay: the gallery strip is a short
/// window pinned to the screen's bottom edge, so a large "expand upward from the item"
/// preview has to escape the strip's bounds. Unlike the system `QLPreviewPanel` (which
/// we couldn't anchor, sat *behind* the strip, and outlived the gallery), we own this
/// panel entirely: it never becomes key (the gallery keeps focus, so Space keeps
/// toggling), ignores the mouse, and is shown/hidden purely from `previewID`.
@MainActor
final class ImagePreviewPanel {
    private let panel: NSPanel
    private let host: NSHostingView<PreviewContent>

    /// Max on-screen size of the IMAGE itself; the image is aspect-fit inside it and
    /// the card + tail + shadow are added around it.
    private static let maxImage = NSSize(width: 1100, height: 1000)
    private static let gap: CGFloat = 6           // tail tip → card top

    /// Layout constants shared by the panel's sizing math and the SwiftUI content, so
    /// both lay out from one source of truth.
    enum Chrome {
        static let pad: CGFloat = 7      // frosted-material frame around the image
        static let shadow: CGFloat = 36  // panel padding reserved for the drop shadow's reach
        static let tailW: CGFloat = 26
        static let tailH: CGFloat = 12
    }

    init() {
        host = NSHostingView(rootView: PreviewContent(imageSize: .zero, image: nil, dimensions: nil))
        panel = NSPanel(contentRect: NSRect(origin: .zero, size: Self.maxImage),
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: true)
        panel.isFloatingPanel = true
        // Above the strip (.popUpMenu = 101), so the preview never renders behind it.
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue + 1)
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false                 // the SwiftUI content draws its own shadow
        panel.ignoresMouseEvents = true         // purely visual; never steals clicks
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.contentView = host
    }

    /// Show the preview for `image`, its tail tip `gap` above `anchorTopY` (AppKit
    /// screen coords, y-up), horizontally centered on `anchorCenterX`, clamped to
    /// `screen`.
    func show(image: NSImage, anchorCenterX: CGFloat, anchorTopY: CGFloat,
              on screen: NSScreen, animated: Bool) {
        let vis = screen.visibleFrame
        let chromeH = 2 * Chrome.pad + Chrome.tailH + 2 * Chrome.shadow
        let chromeW = 2 * Chrome.pad + 2 * Chrome.shadow
        // Fit to the max, then shrink to the room left above the card and within the
        // screen width, so on any normal display the box never overflows the top or sides.
        var img = Self.fittedImageSize(for: image)
        let roomH = (vis.maxY - 8) - (anchorTopY + Self.gap) - chromeH
        let roomW = vis.width - 16 - chromeW
        var scale: CGFloat = 1
        if roomH > 60 { scale = min(scale, roomH / img.height) }
        if roomW > 60 { scale = min(scale, roomW / img.width) }
        if scale < 1 {
            img = NSSize(width: (img.width * scale).rounded(), height: (img.height * scale).rounded())
        }
        host.rootView = PreviewContent(imageSize: img, image: image,
                                       dimensions: Self.dimensions(image))

        let w = img.width + chromeW
        let h = img.height + chromeH
        var x = anchorCenterX - w / 2
        x = min(max(x, vis.minX + 8), vis.maxX - w - 8)
        // Tail tip sits `Chrome.shadow` up from the panel's bottom edge; put it `gap`
        // above the card, so the box grows upward from the item.
        let y = anchorTopY + Self.gap - Chrome.shadow
        let target = NSRect(x: x, y: y, width: w, height: h)

        if !animated {
            panel.setFrame(target, display: true)
            panel.alphaValue = 1
            panel.orderFrontRegardless()
            return
        }
        // Grow + fade up from a slightly smaller, slightly lower box.
        if !panel.isVisible {
            panel.alphaValue = 0
            panel.setFrame(target.insetBy(dx: 12, dy: 12).offsetBy(dx: 0, dy: -10), display: false)
        }
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.16
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.3, 1)
            panel.animator().setFrame(target, display: true)
            panel.animator().alphaValue = 1
        }
    }

    func hide() {
        guard panel.isVisible else { return }
        panel.orderOut(nil)
        panel.alphaValue = 1
    }

    /// Aspect-fit the image within `maxImage`, never upscaling past its natural size.
    private static func fittedImageSize(for image: NSImage) -> NSSize {
        let natural = image.representations.first.map {
            NSSize(width: $0.pixelsWide, height: $0.pixelsHigh)
        } ?? image.size
        guard natural.width > 0, natural.height > 0 else { return maxImage }
        let scale = min(maxImage.width / natural.width, maxImage.height / natural.height, 1)
        return NSSize(width: (natural.width * scale).rounded(),
                      height: (natural.height * scale).rounded())
    }

    private static func dimensions(_ image: NSImage) -> String? {
        guard let rep = image.representations.first, rep.pixelsWide > 0, rep.pixelsHigh > 0
        else { return nil }
        return "\(rep.pixelsWide) × \(rep.pixelsHigh)"
    }
}

/// A downward-pointing triangle — the tail that connects the preview to its card.
private struct DownTail: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.midX, y: r.maxY))
        p.closeSubpath()
        return p
    }
}

/// The SwiftUI content: a frosted card holding the aspect-fit image, a dimensions
/// caption, and a downward tail — all under a soft drop shadow.
private struct PreviewContent: View {
    let imageSize: CGSize
    let image: NSImage?
    let dimensions: String?

    private typealias Chrome = ImagePreviewPanel.Chrome

    var body: some View {
        VStack(spacing: 0) {
            card
            // Tail overlaps the card by 1pt so there's no seam between them.
            DownTail()
                .fill(.regularMaterial)
                .frame(width: Chrome.tailW, height: Chrome.tailH)
                .offset(y: -1)
        }
        .compositingGroup()
        .shadow(color: .black.opacity(0.45), radius: 24, y: 12)
        .padding(Chrome.shadow)
    }

    private var card: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            } else {
                Color.clear
            }
        }
        .frame(width: imageSize.width, height: imageSize.height)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(alignment: .bottom) {
            if let dimensions {
                Text(dimensions)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 9).padding(.vertical, 3)
                    .background(.black.opacity(0.55), in: Capsule())
                    .padding(.bottom, 8)
            }
        }
        .padding(Chrome.pad)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
