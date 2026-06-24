import Foundation
import ProsciuttoKit

final class Preferences {
    static let shared = Preferences()
    private let defaults = UserDefaults.standard

    private enum Keys {
        static let maxItems = "retention.maxItems"
        static let maxAge = "retention.maxAgeDays"
        static let isPaused = "capture.isPaused"
        static let blocked = "exclusion.blockedBundleIDs"
        static let soundEnabled = "capture.soundEnabled"
        static let soundName = "capture.soundName"
        static let appearance = "theme.appearance"
        static let accentTheme = "theme.accent"
        static let customAccentHex = "theme.customAccentHex"
    }

    var appearanceRaw: String {
        get { defaults.string(forKey: Keys.appearance) ?? "system" }
        set { defaults.set(newValue, forKey: Keys.appearance) }
    }

    var accentThemeRaw: String {
        get { defaults.string(forKey: Keys.accentTheme) ?? "prosciutto" }
        set { defaults.set(newValue, forKey: Keys.accentTheme) }
    }

    var customAccentHex: String {
        get { defaults.string(forKey: Keys.customAccentHex) ?? "#F56B8C" }
        set { defaults.set(newValue, forKey: Keys.customAccentHex) }
    }

    var captureSoundEnabled: Bool {
        get { defaults.object(forKey: Keys.soundEnabled) as? Bool ?? false }
        set { defaults.set(newValue, forKey: Keys.soundEnabled) }
    }

    var captureSoundName: String {
        get { defaults.string(forKey: Keys.soundName) ?? "Pop" }
        set { defaults.set(newValue, forKey: Keys.soundName) }
    }

    var maxItems: Int {
        get { defaults.object(forKey: Keys.maxItems) as? Int ?? 1000 }
        set { defaults.set(newValue, forKey: Keys.maxItems) }
    }

    var maxAgeDays: Int {
        get { defaults.object(forKey: Keys.maxAge) as? Int ?? 7 }
        set { defaults.set(newValue, forKey: Keys.maxAge) }
    }

    var isPaused: Bool {
        get { defaults.bool(forKey: Keys.isPaused) }
        set { defaults.set(newValue, forKey: Keys.isPaused) }
    }

    var blockedBundleIDs: Set<String> {
        get {
            if let saved = defaults.array(forKey: Keys.blocked) as? [String] {
                return Set(saved)
            }
            return ExclusionPolicy.defaultBlocked
        }
        set { defaults.set(Array(newValue), forKey: Keys.blocked) }
    }

    var retentionPolicy: RetentionPolicy {
        RetentionPolicy(maxItems: maxItems, maxAge: TimeInterval(maxAgeDays) * 86_400)
    }
}
