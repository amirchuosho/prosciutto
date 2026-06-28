import SwiftUI
import ProsciuttoKit

struct ImageCard: View {
    let item: ClipItem

    private var nsImage: NSImage? {
        if let data = item.imageData { return NSImage(data: data) }
        if let path = item.textPlain, !path.isEmpty { return NSImage(contentsOfFile: path) }
        return nil
    }

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
