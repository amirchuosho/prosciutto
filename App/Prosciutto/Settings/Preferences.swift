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
        static let pasteAutomatically = "paste.automatically"
        static let customAccentHex = "theme.customAccentHex"
        static let theme = "theme.name"
        static let openKeyCode = "hotkey.open.keyCode"
        static let openModifiers = "hotkey.open.modifiers"
        static let plainKeyCode = "hotkey.plain.keyCode"
        static let plainModifiers = "hotkey.plain.modifiers"
        static let saveText = "capture.saveText"
        static let saveImages = "capture.saveImages"
        static let saveFiles = "capture.saveFiles"
        static let saveVideos = "capture.saveVideos"
        static let maxItemSizeBytes = "capture.maxItemSizeBytes"
        static let useFuzzySearch = "search.useFuzzy"
        static let autoCopyScreenshots = "capture.autoCopyScreenshots"
        static let autoCopyRecordings = "capture.autoCopyRecordings"
    }

    var customAccentHex: String {
        get { defaults.string(forKey: Keys.customAccentHex) ?? "#F56B8C" }
        set { defaults.set(newValue, forKey: Keys.customAccentHex) }
    }

    /// Selected full theme. Migrates once from the old accent key.
    var themeRaw: String {
        get {
            if let v = defaults.string(forKey: Keys.theme) { return v }
            // one-time migration: everyone lands on Prosciutto (old accent/appearance retired)
            let migrated = "prosciutto"
            defaults.set(migrated, forKey: Keys.theme)
            return migrated
        }
        set { defaults.set(newValue, forKey: Keys.theme) }
    }

    var captureSoundEnabled: Bool {
        get { defaults.object(forKey: Keys.soundEnabled) as? Bool ?? false }
        set { defaults.set(newValue, forKey: Keys.soundEnabled) }
    }

    var captureSoundName: String {
        get { defaults.string(forKey: Keys.soundName) ?? "Pop" }
        set { defaults.set(newValue, forKey: Keys.soundName) }
    }

    /// true: selecting an item pastes it immediately. false: it's loaded onto
    /// the clipboard so the next ⌘V pastes it.
    var pasteAutomatically: Bool {
        get { defaults.object(forKey: Keys.pasteAutomatically) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Keys.pasteAutomatically) }
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

    // Hotkeys are stored as keyCode + Cocoa NSEvent.ModifierFlags rawValue.
    // Defaults: open = ⌘⇧V, plain-paste = ⌘⌥V (kVK_ANSI_V == 9).
    var openHotkeyKeyCode: Int {
        get { defaults.object(forKey: Keys.openKeyCode) as? Int ?? 9 }
        set { defaults.set(newValue, forKey: Keys.openKeyCode) }
    }
    var openHotkeyModifiers: Int {
        get { defaults.object(forKey: Keys.openModifiers) as? Int ?? Preferences.defaultCmdShift }
        set { defaults.set(newValue, forKey: Keys.openModifiers) }
    }
    var plainPasteKeyCode: Int {
        get { defaults.object(forKey: Keys.plainKeyCode) as? Int ?? 9 }
        set { defaults.set(newValue, forKey: Keys.plainKeyCode) }
    }
    var plainPasteModifiers: Int {
        get { defaults.object(forKey: Keys.plainModifiers) as? Int ?? Preferences.defaultCmdOption }
        set { defaults.set(newValue, forKey: Keys.plainModifiers) }
    }
    var saveText: Bool {
        get { defaults.object(forKey: Keys.saveText) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Keys.saveText) }
    }
    var saveImages: Bool {
        get { defaults.object(forKey: Keys.saveImages) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Keys.saveImages) }
    }
    var saveFiles: Bool {
        get { defaults.object(forKey: Keys.saveFiles) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Keys.saveFiles) }
    }
    var saveVideos: Bool {
        get { defaults.object(forKey: Keys.saveVideos) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Keys.saveVideos) }
    }
    var maxItemSizeBytes: Int {
        get { defaults.object(forKey: Keys.maxItemSizeBytes) as? Int ?? 0 }   // 0 = no limit
        set { defaults.set(newValue, forKey: Keys.maxItemSizeBytes) }
    }
    var useFuzzySearch: Bool {
        get { defaults.bool(forKey: Keys.useFuzzySearch) }                     // default false
        set { defaults.set(newValue, forKey: Keys.useFuzzySearch) }
    }
    var autoCopyScreenshots: Bool {
        get { defaults.object(forKey: Keys.autoCopyScreenshots) as? Bool ?? false }   // default off
        set { defaults.set(newValue, forKey: Keys.autoCopyScreenshots) }
    }
    var autoCopyRecordings: Bool {
        get { defaults.object(forKey: Keys.autoCopyRecordings) as? Bool ?? false }     // default off
        set { defaults.set(newValue, forKey: Keys.autoCopyRecordings) }
    }

    var captureFilter: CaptureFilter {
        CaptureFilter.from(saveText: saveText, saveImages: saveImages,
                           saveFiles: saveFiles, saveVideos: saveVideos, maxBytes: maxItemSizeBytes)
    }

    // NSEvent.ModifierFlags rawValues (avoids importing AppKit here):
    // .command = 1<<20 = 1_048_576, .shift = 1<<17 = 131_072, .option = 1<<19 = 524_288
    static let defaultCmdShift = 1_048_576 | 131_072
    static let defaultCmdOption = 1_048_576 | 524_288
}
