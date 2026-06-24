import Foundation
import CryptoKit

public enum ContentHasher {
    public static func hash(kind: ClipKind, primary: Data) -> String {
        var hasher = SHA256()
        hasher.update(data: Data(kind.rawValue.utf8))
        hasher.update(data: primary)
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
