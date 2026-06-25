public enum ClipKind: String, Codable, CaseIterable, Sendable {
    case text, rtf, image, link, color, code, file

    /// Kinds whose contents can be edited as text in the editor sheet.
    public var isEditable: Bool {
        switch self {
        case .text, .rtf, .code, .link, .color: return true
        case .image, .file: return false
        }
    }
}
