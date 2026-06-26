import SwiftUI
import ProsciuttoKit

struct ImageCard: View {
    let item: ClipItem

    private var nsImage: NSImage? { item.imageData.flatMap { NSImage(data: $0) } }

    var body: some View {
        if let img = nsImage {
            Image(nsImage: img)
                .resizable()
                .aspectRatio(contentMode: .fill)
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
