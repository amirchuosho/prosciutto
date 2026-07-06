import AppKit
import Foundation
import ProsciuttoKit

/// Watches the folder macOS saves screen captures to and copies each new one to the
/// pasteboard, so it is ready to paste and gets captured as a clip. A screenshot is
/// copied as an image; a screen recording as a FILE (its URL, plus a first-frame
/// thumbnail for the tile). The file on disk is left untouched.
///
/// We watch the folder directly (rather than an `NSMetadataQuery`) for two reasons:
/// Spotlight results are TCC-filtered — a background app can't even *see* Desktop
/// screenshots that way — and a metadata query never reads a file, so it never
/// triggers the macOS folder-access prompt. Listing/reading the folder directly does
/// both: it prompts once for access, then sees every screenshot.
final class ScreenshotWatcher {
    private let pasteboard: NSPasteboard
    /// Per-type gates, set by `AppEnvironment` before `start()`. The watcher runs
    /// whenever EITHER is on; these decide which captures it actually copies.
    var copyScreenshots = false
    var copyRecordings = false
    private var startedAt = Date()
    private var processed = Set<String>()
    private var source: DispatchSourceFileSystemObject?
    private var dirURL: URL?
    /// Bumped on every start/stop so a pending re-arm retry from a superseded run
    /// aborts instead of double-arming.
    private var armToken = 0

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    /// Pure decision: a screenshot is handled once, and only if it appeared after
    /// the watcher started (never the pre-existing backlog).
    static func shouldProcess(path: String, created: Date, startedAt: Date, processed: Set<String>) -> Bool {
        created >= startedAt && !processed.contains(path)
    }

    /// Where macOS writes screenshots: `com.apple.screencapture location`, else the
    /// Desktop.
    static func screenshotDirectory() -> URL {
        if let loc = UserDefaults(suiteName: "com.apple.screencapture")?.string(forKey: "location"),
           !loc.isEmpty {
            return URL(fileURLWithPath: (loc as NSString).expandingTildeInPath)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")
    }

    func start() {
        stop()                       // bumps armToken, cancels any live source
        startedAt = Date()
        arm(attempt: 0, token: armToken)
    }

    /// Arm the folder watch. Listing the directory is the TCC-gated step (it also
    /// fires the one-time folder-access prompt); if it throws we don't have access
    /// yet. Access is often granted a beat AFTER launch (the user answers the prompt),
    /// so retry for a while rather than giving up — otherwise the watch would stay
    /// dead until an app restart.
    private func arm(attempt: Int, token: Int) {
        guard token == armToken else { return }   // superseded by a newer start/stop
        let dir = Self.screenshotDirectory()
        guard let existing = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else {
            guard attempt < 15 else { return }     // ~30s of 2s retries, then give up
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                self?.arm(attempt: attempt + 1, token: token)
            }
            return
        }

        // Seed the processed-set with whatever is already there (backlog, never copied).
        dirURL = dir
        processed.removeAll()
        for name in existing { processed.insert(dir.appendingPathComponent(name).path) }

        let fd = open(dir.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write], queue: .main)
        src.setEventHandler { [weak self] in self?.scan() }
        src.setCancelHandler { close(fd) }
        source = src
        src.resume()
    }

    func stop() {
        armToken += 1                // invalidate any pending re-arm retry
        source?.cancel()
        source = nil
        dirURL = nil
    }

    /// A new entry appeared in the folder — copy any new screenshot.
    private func scan() {
        guard let dir = dirURL,
              let files = try? FileManager.default.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: [.creationDateKey], options: [.skipsHiddenFiles])
        else { return }
        for url in files {
            let path = url.path
            let created = (try? url.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? .distantPast
            guard Self.shouldProcess(path: path, created: created, startedAt: startedAt, processed: processed)
            else { continue }
            handleCandidate(path: path)
        }
    }

    /// Confirm the file is a screenshot and copy it. macOS sets the screenshot
    /// extended attribute when it writes the file, but the folder event can fire a
    /// hair before the xattr lands, so retry briefly. The path is claimed up front so
    /// repeated folder events don't handle it twice.
    private func handleCandidate(path: String, attempt: Int = 0) {
        if attempt == 0 { processed.insert(path) }   // claim it — re-scans will skip it
        if isScreenshot(path) {
            if copyScreenshots { copyImageToPasteboard(path: path) }
        } else if isScreenRecording(path) {
            if copyRecordings { copyVideoToPasteboard(path: path) }
        } else if attempt < 4 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.handleCandidate(path: path, attempt: attempt + 1)
            }
        }
    }

    /// A screenshot carries this extended attribute, written at the same time as the
    /// file — unlike the Spotlight index, it is available immediately and does not
    /// depend on indexing. Presence of the attribute is the marker (locale- and
    /// location-independent).
    private func isScreenshot(_ path: String) -> Bool {
        getxattr(path, "com.apple.metadata:kMDItemIsScreenCapture", nil, 0, 0, 0) >= 0
    }

    /// A screen RECORDING is a video file macOS tagged with the screen-capture
    /// metadata. Screenshots get `kMDItemIsScreenCapture`; recordings get
    /// `kMDItemScreenCaptureType` instead (verified on real recordings). Requiring
    /// the xattr means a random `.mov` the user drops in the folder is NOT copied.
    private func isScreenRecording(_ path: String) -> Bool {
        let ext = (path as NSString).pathExtension.lowercased()
        guard KindDetector.videoExtensions.contains(ext) else { return false }
        return getxattr(path, "com.apple.metadata:kMDItemScreenCaptureType", nil, 0, 0, 0) >= 0
    }

    /// Put the screenshot on the pasteboard the way copying it in Finder would: the
    /// file URL AND the image pixels. Pasting then yields the actual file (Finder,
    /// Mail, Slack, chat) or the image (editors). Because it carries a file URL, the
    /// captured clip is a file-backed image (hashed by path), so pasting it again
    /// dedupes instead of piling up re-encoded copies.
    private func copyImageToPasteboard(path: String, attempt: Int = 0) {
        let url = URL(fileURLWithPath: path)
        if let img = NSImage(contentsOf: url) {
            pasteboard.writeFileBackedImage(url, image: img)
        } else if attempt < 3 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.copyImageToPasteboard(path: path, attempt: attempt + 1)
            }
        }
    }

    /// Put the recording on the pasteboard as a FILE (its URL, so pasting drops the
    /// `.mov`), plus a first-frame thumbnail so the gallery tile previews. Thumbnail
    /// generation touches AVFoundation/disk, so do it off the main thread and hop
    /// back to write the pasteboard. If the thumbnail fails we still copy the file.
    private func copyVideoToPasteboard(path: String) {
        let url = URL(fileURLWithPath: path)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let thumb = VideoThumbnail.firstFrame(of: url)
            DispatchQueue.main.async {
                self?.pasteboard.writeFileBackedVideo(url, thumbnail: thumb)
            }
        }
    }

    deinit { stop() }
}
