import Foundation

public enum FuzzyMatch {
    /// Case-insensitive subsequence match. Returns nil when `needle` is not a
    /// subsequence of `haystack`; otherwise a score where contiguous runs and
    /// early matches score higher.
    public static func score(_ needle: String, _ haystack: String) -> Int? {
        let n = Array(needle.lowercased())
        guard !n.isEmpty else { return 0 }
        let h = Array(haystack.lowercased())
        var ni = 0, score = 0, lastMatch = -2
        for (hi, ch) in h.enumerated() where ni < n.count {
            if ch == n[ni] {
                score += (hi == lastMatch + 1) ? 3 : 1   // contiguity bonus
                if hi < 8 { score += 1 }                  // early-match bonus
                lastMatch = hi
                ni += 1
            }
        }
        return ni == n.count ? score : nil
    }
}
