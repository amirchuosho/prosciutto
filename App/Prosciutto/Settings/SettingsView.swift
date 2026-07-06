import SwiftUI
import AppKit
import ProsciuttoKit

struct SettingsView: View {
    @EnvironmentObject var theme: ThemeManager

    // General
    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var pasteAutomatically = Preferences.shared.pasteAutomatically
    @State private var autoCopyScreenshots = Preferences.shared.autoCopyScreenshots
    @State private var autoCopyRecordings = Preferences.shared.autoCopyRecordings
    @State private var soundEnabled = Preferences.shared.captureSoundEnabled
    @State private var soundName = Preferences.shared.captureSoundName
    @State private var useFuzzy = Preferences.shared.useFuzzySearch
    // Hotkeys
    @State private var openCombo = KeyCombo(storedKeyCode: Preferences.shared.openHotkeyKeyCode,
                                            storedModifiers: Preferences.shared.openHotkeyModifiers)
    @State private var plainCombo = KeyCombo(storedKeyCode: Preferences.shared.plainPasteKeyCode,
                                             storedModifiers: Preferences.shared.plainPasteModifiers)
    // History
    @State private var limitItems = Preferences.shared.maxItems > 0
    @State private var maxItems = max(Preferences.shared.maxItems, 100)
    @State private var expire = Preferences.shared.maxAgeDays > 0
    @State private var maxAgeDays = max(Preferences.shared.maxAgeDays, 1)
    @State private var limitSize = Preferences.shared.maxItemSizeBytes > 0
    @State private var maxSizeMB = max(Preferences.shared.maxItemSizeBytes / 1_000_000, 1)
    @State private var saveText = Preferences.shared.saveText
    @State private var saveImages = Preferences.shared.saveImages
    @State private var saveVideos = Preferences.shared.saveVideos
    @State private var saveFiles = Preferences.shared.saveFiles

    private let systemSounds = ["Pop", "Tink", "Glass", "Bottle", "Frog", "Submarine", "Morse"]

    private func changed() { NotificationCenter.default.post(name: .prosciuttoSettingsChanged, object: nil) }

    var body: some View {
        TabView {
            general.tabItem { Label("General", systemImage: "gearshape") }
            hotkeys.tabItem { Label("Hotkeys", systemImage: "command") }
            history.tabItem { Label("History", systemImage: "clock") }
            PrivacyTab().tabItem { Label("Privacy", systemImage: "hand.raised") }
            appearance.tabItem { Label("Appearance", systemImage: "paintbrush") }
            PermissionView().tabItem { Label("Permissions", systemImage: "lock.shield") }
        }
        .frame(width: 480, height: 420)
    }

    // MARK: General
    private var general: some View {
        Form {
            Section("Startup") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, v in
                        do { try LoginItem.setEnabled(v) }
                        catch { launchAtLogin = LoginItem.isEnabled }   // revert on failure
                    }
            }
            Section("Behavior") {
                Toggle("Paste automatically on select", isOn: $pasteAutomatically)
                    .onChange(of: pasteAutomatically) { _, v in Preferences.shared.pasteAutomatically = v }
                Toggle("Fuzzy search", isOn: $useFuzzy)
                    .onChange(of: useFuzzy) { _, v in Preferences.shared.useFuzzySearch = v; changed() }
                Toggle("Copy screenshots to clipboard automatically", isOn: $autoCopyScreenshots)
                    .onChange(of: autoCopyScreenshots) { _, v in Preferences.shared.autoCopyScreenshots = v; changed() }
                Toggle("Copy screen recordings to clipboard automatically", isOn: $autoCopyRecordings)
                    .onChange(of: autoCopyRecordings) { _, v in Preferences.shared.autoCopyRecordings = v; changed() }
            }
            Section("Sound") {
                Toggle("Play a sound when copying", isOn: $soundEnabled)
                    .onChange(of: soundEnabled) { _, v in Preferences.shared.captureSoundEnabled = v }
                Picker("Sound", selection: $soundName) {
                    ForEach(systemSounds, id: \.self) { Text($0).tag($0) }
                }
                .disabled(!soundEnabled)
                .onChange(of: soundName) { _, v in Preferences.shared.captureSoundName = v; NSSound(named: v)?.play() }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: Hotkeys
    private var hotkeys: some View {
        Form {
            Section("Shortcuts") {
                LabeledContent("Open gallery") {
                    KeyRecorderField(combo: $openCombo).frame(width: 180, height: 24)
                        .onChange(of: openCombo) { _, c in
                            Preferences.shared.openHotkeyKeyCode = Int(c.keyCode)
                            Preferences.shared.openHotkeyModifiers = Int(c.modifiers.rawValue)
                            changed()
                        }
                }
                LabeledContent("Paste as plain text") {
                    KeyRecorderField(combo: $plainCombo).frame(width: 180, height: 24)
                        .onChange(of: plainCombo) { _, c in
                            Preferences.shared.plainPasteKeyCode = Int(c.keyCode)
                            Preferences.shared.plainPasteModifiers = Int(c.modifiers.rawValue)
                            changed()
                        }
                }
            }
            Text("Click a field, then press the new shortcut. A modifier (⌘/⌥/⌃) is required.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }

    // MARK: History
    private var history: some View {
        Form {
            Section("Storage") {
                Toggle("Limit number of items", isOn: $limitItems)
                    .onChange(of: limitItems) { _, v in Preferences.shared.maxItems = v ? maxItems : 0; changed() }
                if limitItems {
                    Stepper("Keep up to \(maxItems) items", value: $maxItems, in: 100...10_000, step: 100)
                        .onChange(of: maxItems) { _, v in Preferences.shared.maxItems = v; changed() }
                }
                Toggle("Expire unpinned items", isOn: $expire)
                    .onChange(of: expire) { _, v in Preferences.shared.maxAgeDays = v ? maxAgeDays : 0; changed() }
                if expire {
                    Stepper("After \(maxAgeDays) days", value: $maxAgeDays, in: 1...365)
                        .onChange(of: maxAgeDays) { _, v in Preferences.shared.maxAgeDays = v; changed() }
                }
            }
            Section("Size") {
                Toggle("Skip items larger than a size", isOn: $limitSize)
                    .onChange(of: limitSize) { _, v in Preferences.shared.maxItemSizeBytes = v ? maxSizeMB * 1_000_000 : 0; changed() }
                if limitSize {
                    Stepper("Max \(maxSizeMB) MB", value: $maxSizeMB, in: 1...500)
                        .onChange(of: maxSizeMB) { _, v in Preferences.shared.maxItemSizeBytes = v * 1_000_000; changed() }
                }
            }
            Section("Save which types") {
                Toggle("Text", isOn: $saveText).onChange(of: saveText) { _, v in Preferences.shared.saveText = v; changed() }
                Toggle("Images", isOn: $saveImages).onChange(of: saveImages) { _, v in Preferences.shared.saveImages = v; changed() }
                Toggle("Videos", isOn: $saveVideos).onChange(of: saveVideos) { _, v in Preferences.shared.saveVideos = v; changed() }
                Toggle("Files", isOn: $saveFiles).onChange(of: saveFiles) { _, v in Preferences.shared.saveFiles = v; changed() }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: Appearance
    private var appearance: some View {
        Form {
            Section("Theme") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                    ForEach(AppTheme.allCases) { t in
                        let p = ThemePalette(t.spec(customAccentHex: theme.customAccentHex))
                        Button { theme.theme = t } label: {
                            VStack(spacing: 6) {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(p.background.style)
                                    .frame(height: 54)
                                    .overlay(
                                        HStack(spacing: 4) {
                                            ForEach([ClipKind.text, .code, .link], id: \.self) { k in
                                                RoundedRectangle(cornerRadius: 4).fill(p.color(for: k)).frame(width: 26, height: 30)
                                            }
                                        })
                                    .overlay(RoundedRectangle(cornerRadius: 10)
                                        .strokeBorder(theme.theme == t ? AnyShapeStyle(p.accentGradient) : AnyShapeStyle(p.hairline),
                                                      lineWidth: theme.theme == t ? 3 : 1))
                                Text(t.label).font(.system(size: 12, weight: .semibold))
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                if theme.theme == .custom {
                    ColorPicker("Custom accent", selection: Binding(
                        get: { Color(hex: theme.customAccentHex) ?? .accentColor },
                        set: { theme.customAccentHex = $0.toHex() ?? theme.customAccentHex }), supportsOpacity: false)
                }
            }
        }
        .formStyle(.grouped)
    }

}
