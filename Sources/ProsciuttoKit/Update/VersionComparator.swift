import Foundation

/// Compares dot-separated version strings. Pure; no I/O.
public enum VersionComparator {
    /// True iff `latest` is a strictly higher version than `current`. Strips a leading
    /// v/V, compares integer components left-to-right (missing components = 0). Any
    /// non-integer component makes the result false — fail-safe: never offer an update
    /// we can't parse.
    public static func isNewer(_ latest: String, than current: String) -> Bool {
        guard let l = parse(latest), let c = parse(current) else { return false }
        for i in 0..<max(l.count, c.count) {
            let a = i < l.count ? l[i] : 0
            let b = i < c.count ? c[i] : 0
            if a != b { return a > b }
        }
        return false
    }

    private static func parse(_ s: String) -> [Int]? {
        var t = s.trimmingCharacters(in: .whitespaces)
        if let f = t.first, f == "v" || f == "V" { t.removeFirst() }
        let parts = t.split(separator: ".", omittingEmptySubsequences: false)
        guard !parts.isEmpty else { return nil }
        var out: [Int] = []
        for p in parts { guard let n = Int(p) else { return nil }; out.append(n) }
        return out
    }
}
