import SwiftUI
import ProsciuttoKit

/// Tile for a recording clip: a first-frame thumbnail (generated from the backing
/// `.mov` on disk, async + cached) with a play badge so it reads as a video. The
/// pasteboard image is NOT used — a Finder copy of a `.mov` supplies a generic file
/// icon, so the real frame from disk is the reliable preview. Falls back to a film
/// glyph while the frame loads or if the file can't be read.
struct VideoCard: View {
    let item: ClipItem
    @State private var thumb: NSImage?

    var body: some View {
        ZStack {
            if let img = thumb {
                Color.clear
                    .overlay {
                        Image(nsImage: img)
                            .resizable()
                            .scaledToFill()
                            .allowsHitTesting(false)   // decoration only — see ImageCard
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
            } else {
                Image(systemName: "film")
                    .font(.system(size: 34))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            // Play badge, centered, so a thumbnail reads unmistakably as a video.
            Image(systemName: "play.fill")
                .font(.system(size: 15, weight: .black))
                .foregroundStyle(.white)
                .padding(11)
                .background(.black.opacity(0.45), in: Circle())
                .overlay(Circle().strokeBorder(.white.opacity(0.85), lineWidth: 1.5))
                .allowsHitTesting(false)
        }
        .task(id: item.id) { thumb = await VideoThumbnailCache.thumbnail(for: item) }
    }
}
