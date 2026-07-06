import AppKit
import ProsciuttoKit

final class PasteService {
    func write(_ item: ClipItem, asPlainText: Bool) {
        let pb = NSPasteboard.general
        pb.clearContents()
        switch item.kind {
        case .image:
            if let d = item.imageData, let img = NSImage(data: d) {
                // Write a real NSImage: it puts the standard image types (TIFF etc.)
                // on the pasteboard, which apps recognize when pasting. Writing only
                // .png data is understood by far fewer targets.
                pb.writeObjects([img])
            } else if let path = item.textPlain {
                // File-backed image: write the file URL (so Finder/apps get the
                // file) plus the image itself (so editors get the pixels).
                let url = URL(fileURLWithPath: path)
                var objects: [NSPasteboardWriting] = [url as NSURL]
                if let img = NSImage(contentsOf: url) { objects.append(img) }
                pb.writeObjects(objects)
            }
        case .video:
            // File-backed recording: write the file URL so pasting drops the .mov
            // into Finder/Mail/Slack, plus the thumbnail so image targets get a
            // preview. The path lives in textPlain (like a file-backed image).
            if let path = item.textPlain {
                let url = URL(fileURLWithPath: path)
                var objects: [NSPasteboardWriting] = [url as NSURL]
                if let d = item.imageData, let thumb = NSImage(data: d) { objects.append(thumb) }
                pb.writeObjects(objects)
            }
        case .file:
            if let t = item.textPlain { pb.setString(t, forType: .string) }
        default:
            if !asPlainText, let rtf = item.rtfData { pb.setData(rtf, forType: .rtf) }
            if let t = item.textPlain { pb.setString(t, forType: .string) }
        }
    }

    /// Synthesize a ⌘V keystroke into the frontmost app. Call AFTER focus has
    /// been returned to the target app.
    func synthesizePaste() {
        guard AccessibilityAuthorizer.isTrusted else { return }
        let src = CGEventSource(stateID: .combinedSessionState)
        let v: CGKeyCode = 9 // kVK_ANSI_V
        let down = CGEvent(keyboardEventSource: src, virtualKey: v, keyDown: true)
        down?.flags = .maskCommand
        let up = CGEvent(keyboardEventSource: src, virtualKey: v, keyDown: false)
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
}
