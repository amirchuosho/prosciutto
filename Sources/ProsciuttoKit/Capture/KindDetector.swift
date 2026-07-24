import Foundation

public enum KindDetector {
    private static let colorRegex = try! NSRegularExpression(
        pattern: "^#([0-9a-fA-F]{3}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$")

    private static let imageExtensions: Set<String> =
        ["png", "jpg", "jpeg", "gif", "heic", "heif", "webp", "tiff", "tif", "bmp"]

    /// Video containers we treat as a `.video` clip (file-backed, previewed by a
    /// first-frame thumbnail). Screen recordings are `.mov`; the rest are common
    /// exports a user might copy from Finder.
    public static let videoExtensions: Set<String> =
        ["mov", "mp4", "m4v", "mkv", "webm", "avi"]

    public static func detect(_ s: PasteboardSnapshot) -> ClipKind? {
        // Multiple files (e.g. several pics from Finder) → a file clip that lists
        // names/count, NOT a single-image preview of just the first one.
        if s.fileURLs.count > 1 { return .file }
        if let file = s.fileURLs.first {
            let ext = file.pathExtension.lowercased()
            // A single image file (copied from Finder) is treated as an image, a
            // single video file as a video; anything else is a plain file clip.
            if imageExtensions.contains(ext) { return .image }
            if videoExtensions.contains(ext) { return .video }
            return .file
        }
        if s.imageData != nil { return .image }
        if let raw = s.plainText {
            let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty else { return s.rtfData != nil ? .rtf : nil }
            if isColor(t) { return .color }
            if isURL(t) { return .link }
            if isJSONObjectOrArray(t) { return .code }
            if isCoordinates(t) || isAddress(t) { return .location }
            if looksLikeCode(t) { return .code }
            return .text
        }
        if s.rtfData != nil { return .rtf }
        return nil
    }

    /// The single image file this snapshot represents, or nil. Uses the same
    /// `imageExtensions` rule `detect` uses to classify a `.image` file clip, so the
    /// capture layer and the classifier never disagree. Nil for multi-file, a single
    /// non-image file, or a snapshot with no file URL.
    public static func singleImageFileURL(in snapshot: PasteboardSnapshot) -> URL? {
        guard snapshot.fileURLs.count == 1, let url = snapshot.fileURLs.first,
              imageExtensions.contains(url.pathExtension.lowercased()) else { return nil }
        return url
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

    /// `lat, long` with valid ranges (lat ±90, long ±180).
    private static let coordRegex = try! NSRegularExpression(
        pattern: #"^[-+]?(?:[1-8]?\d(?:\.\d+)?|90(?:\.0+)?)\s*,\s*[-+]?(?:180(?:\.0+)?|(?:1[0-7]\d|[1-9]?\d)(?:\.\d+)?)$"#)

    static func isCoordinates(_ t: String) -> Bool {
        coordRegex.firstMatch(in: t, range: NSRange(t.startIndex..., in: t)) != nil
    }

    /// A postal address, via the same Data Detector macOS uses to underline
    /// addresses in Mail/Notes. Requires the match to cover most of the string so
    /// a code snippet containing an address substring isn't misclassified.
    static func isAddress(_ t: String) -> Bool {
        guard t.count >= 6, t.count <= 200 else { return false }
        // 1) Apple's Data Detector (strong for US / CA / UK formats).
        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.address.rawValue) {
            let range = NSRange(t.startIndex..., in: t)
            if let m = detector.firstMatch(in: t, range: range), m.resultType == .address,
               Double(m.range.length) >= Double(range.length) * 0.7 {
                return true
            }
        }
        // 2) Heuristic for international formats NSDataDetector misses: a street
        //    keyword (multi-language) + a house number + a comma, on one line.
        return looksLikeStreetAddress(t)
    }

    private static let streetWords: [String] = [
        "st", "street", "ave", "avenue", "rd", "road", "blvd", "boulevard",
        "ln", "lane", "dr", "drive", "way", "sq", "square", "hwy", "highway",
        "ct", "court", "pl", "place", "terrace", "close", "crescent",
        "רחוב", "שדרות", "שד", "דרך", "סמטה", "סמטת", "כביש", "רח",
    ]

    private static func looksLikeStreetAddress(_ t: String) -> Bool {
        guard !t.contains("\n"), t.contains(","), t.rangeOfCharacter(from: .decimalDigits) != nil
        else { return false }
        let lower = t.lowercased()
        let tokens = lower.split { !$0.isLetter && !($0.unicodeScalars.first.map { $0.value >= 0x0590 && $0.value <= 0x05FF } ?? false) }
                          .map(String.init)
        return tokens.contains { streetWords.contains($0) }
    }

    static func looksLikeCode(_ t: String) -> Bool {
        let tokens = ["func ", "def ", "class ", "{", "};", "=>", "import ", "const ", "let ", "var ", "</", "/>"]
        let hits = tokens.filter { t.contains($0) }.count
        let newlineDense = t.filter { $0 == "\n" }.count >= 1 && t.contains("  ")
        return hits >= 2 || (hits >= 1 && newlineDense)
    }
}
