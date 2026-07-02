import SwiftUI
import ProsciuttoKit

/// Decoded-image cache keyed by clip id. The LazyHStack recreates cards on
/// scroll; without this, each re-appearance re-decodes the image (from data or
/// disk), hitching the scroll.
@MainActor private enum ImageDecodeCache {
    static var store: [UUID: NSImage] = [:]
    static let limit = 80
    static func image(for item: ClipItem) -> NSImage? {
        if let hit = store[item.id] { return hit }
        let img: NSImage?
        if let data = item.imageData { img = NSImage(data: data) }
        else if let path = item.textPlain, !path.isEmpty { img = NSImage(contentsOfFile: path) }
        else { img = nil }
        if let img {
            if store.count >= limit { store.removeAll() }
            store[item.id] = img
        }
        return img
    }
}

struct ImageCard: View {
    let item: ClipItem

    private var nsImage: NSImage? { ImageDecodeCache.image(for: item) }

    var body: some View {
        if let img = nsImage {
            // Drive the size from a flexible Color.clear so the image (especially
            // one loaded via NSImage(contentsOfFile:), which carries an intrinsic
            // size) can never impose its own dimensions on the card layout and
            // push the header/footer out. The image is overlaid and clipped.
            Color.clear
                .overlay {
                    Image(nsImage: img)
                        .resizable()
                        .scaledToFill()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .overlay(alignment: .bottom) {
                    if let dims = dimensions(img) {
                        Text(dims)
                            .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(.black.opacity(0.55), in: Capsule())
                            .padding(.bottom, DS.Space.sm)
                    }
                }
        } else {
            Image(systemName: "photo")
                .font(.system(size: 34))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func dimensions(_ img: NSImage) -> String? {
        guard let rep = img.representations.first else { return nil }
        let w = rep.pixelsWide, h = rep.pixelsHigh
        guard w > 0, h > 0 else { return nil }
        return "\(w) × \(h)"
    }
}
