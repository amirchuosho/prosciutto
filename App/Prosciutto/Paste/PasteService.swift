import AppKit
import ProsciuttoKit

final class PasteService {
    func write(_ item: ClipItem, asPlainText: Bool) {
        let pb = NSPasteboard.general
        pb.clearContents()
        switch item.kind {
        case .image:
            if let d = item.imageData {
                pb.setData(d, forType: .png)
            } else if let path = item.textPlain {
                // File-backed image: write the file URL (so Finder/apps get the
                // file) plus its pixels (so editors get the image).
                let url = URL(fileURLWithPath: path)
                pb.writeObjects([url as NSURL])
                if let d = try? Data(contentsOf: url) { pb.setData(d, forType: .png) }
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
