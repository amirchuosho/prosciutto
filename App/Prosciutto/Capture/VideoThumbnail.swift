import AppKit
import AVFoundation
import ProsciuttoKit

/// Generates a first-frame thumbnail for a video file, used as the gallery-tile
/// preview for recording clips. Runs synchronously — call it off the main thread.
enum VideoThumbnail {
    /// First displayable frame of the video at `url`, or nil if it can't be read.
    /// `apertureMode = .cleanAperture` avoids the black bars some codecs encode.
    static func firstFrame(of url: URL, maxPixel: CGFloat = 640) -> NSImage? {
        let asset = AVURLAsset(url: url)
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true            // respect rotation
        gen.apertureMode = .cleanAperture
        gen.maximumSize = CGSize(width: maxPixel, height: maxPixel)
        // Ask for time zero but tolerate a nudge forward — the very first sample can
        // be un-decodable, so let the generator pick the nearest good frame.
        gen.requestedTimeToleranceBefore = .zero
        gen.requestedTimeToleranceAfter = CMTime(seconds: 1, preferredTimescale: 600)
        guard let cg = try? gen.copyCGImage(at: .zero, actualTime: nil) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }
}

/// Async, id-keyed cache of first-frame thumbnails for video tiles. Generating a
/// frame touches AVFoundation/disk, so tiles load it off the main thread once and
/// reuse it — the LazyHStack recreates cards on scroll, so without this every
/// re-appearance would re-decode and hitch.
@MainActor enum VideoThumbnailCache {
    private static var store: [UUID: NSImage] = [:]
    private static let limit = 80

    /// Cached thumbnail for the clip, generating it from its backing `.mov` path on
    /// first request. nil if the clip isn't a video or the file can't be read.
    static func thumbnail(for item: ClipItem) async -> NSImage? {
        if let hit = store[item.id] { return hit }
        guard item.kind == .video, let path = item.textPlain, !path.isEmpty else { return nil }
        let url = URL(fileURLWithPath: path)
        let img = await Task.detached(priority: .userInitiated) {
            VideoThumbnail.firstFrame(of: url, maxPixel: 480)
        }.value
        if let img {
            if store.count >= limit { store.removeAll() }
            store[item.id] = img
        }
        return img
    }
}
