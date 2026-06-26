import Foundation

enum JSONTools {
    /// Pretty-print `s` as JSON, or nil if it isn't valid JSON.
    static func pretty(_ s: String) -> String? {
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = trimmed.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]),
              let out = try? JSONSerialization.data(withJSONObject: obj,
                        options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]),
              let str = String(data: out, encoding: .utf8) else { return nil }
        return str
    }
}
