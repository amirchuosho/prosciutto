import AppKit

extension NSPasteboard {
    /// Put an image on the pasteboard the way copying its file in Finder would: the
    /// file URL AND the image pixels. Pasting then yields the actual file (Finder,
    /// Mail, Slack, chat) or the image (editors). Because it carries a file URL, the
    /// clip we capture back is a file-backed image (hashed by path), so pasting it
    /// again dedupes instead of piling up re-encoded copies.
    ///
    /// Shared by the screenshot watcher and the in-Preview image editor — both need
    /// exactly this shape, so keep it in one place.
    func writeFileBackedImage(_ url: URL, image: NSImage) {
        clearContents()
        writeObjects([url as NSURL, image])
    }

    /// Put a recording on the pasteboard as a FILE: the file URL (so pasting drops
    /// the `.mov` into Finder/Mail/Slack) plus an optional first-frame thumbnail (so
    /// the gallery tile has a preview, captured back as the clip's image data). Unlike
    /// an image, the video bytes are NOT written — the URL is the payload; the
    /// thumbnail is decoration.
    func writeFileBackedVideo(_ url: URL, thumbnail: NSImage?) {
        clearContents()
        var objects: [NSPasteboardWriting] = [url as NSURL]
        if let thumbnail { objects.append(thumbnail) }
        writeObjects(objects)
    }
}
