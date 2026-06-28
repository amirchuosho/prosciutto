import Foundation

public enum KindDetector {
    private static let colorRegex = try! NSRegularExpression(
        pattern: "^#([0-9a-fA-F]{3}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$")

    private static let imageExtensions: Set<String> =
        ["png", "jpg", "jpeg", "gif", "heic", "heif", "webp", "tiff", "tif", "bmp"]

    public static func detect(_ s: PasteboardSnapshot) -> ClipKind? {
        if let file = s.fileURLs.first {
            // An image file (copied from Finder) is treated as an image, not a file.
            return imageExtensions.contains(file.pathExtension.lowercased()) ? .image : .file
        }
        if s.imageData != nil { return .image }
        if let raw = s.plainText {
            let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty else { return s.rtfData != nil ? .rtf : nil }
            if isColor(t) { return .color }
            if isURL(t) { return .link }
            if isJSONObjectOrArray(t) { return .code }
            if looksLikeCode(t) { return .code }
            return .text
        }
        if s.rtfData != nil { return .rtf }
        return nil
    }

    static func isColor(_ t: String) -> Bool {
        let r = NSRange(t.startIndex..., in: t)
        return colorRegex.firstMatch(in: t, range: r) != nil
    }

    static func isURL(_ t: String) -> Bool {
        guard !t.contains(" "), !t.contains("\n") else { return false }
        guard let u = URL(string: t), let scheme = u.scheme else { return false }
        return scheme == "http" || scheme == "https"
    }

    /// True for a JSON object/array (not bare scalars). JSON is treated as code
    /// so it renders monospaced and gets the Format action.
    static func isJSONObjectOrArray(_ t: String) -> Bool {
        guard t.hasPrefix("{") || t.hasPrefix("["),
              let d = t.data(using: .utf8) else { return false }
        return (try? JSONSerialization.jsonObject(with: d)) != nil   // no fragments
    }

    static func looksLikeCode(_ t: String) -> Bool {
        let tokens = ["func ", "def ", "class ", "{", "};", "=>", "import ", "const ", "let ", "var ", "</", "/>"]
        let hits = tokens.filter { t.contains($0) }.count
        let newlineDense = t.filter { $0 == "\n" }.count >= 1 && t.contains("  ")
        return hits >= 2 || (hits >= 1 && newlineDense)
    }
}
