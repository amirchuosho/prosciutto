import SwiftUI
import AppKit

struct SettingsView: View {
    @EnvironmentObject var theme: ThemeManager

    // General
    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var pasteAutomatically = Preferences.shared.pasteAutomatically
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
                Toggle("Files", isOn: $saveFiles).onChange(of: saveFiles) { _, v in Preferences.shared.saveFiles = v; changed() }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: Appearance
    private var appearance: some View {
        Form {
            Section("Theme") {
                Picker("Appearance", selection: $theme.appearance) {
                    ForEach(Appearance.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            Section("Accent") {
                accentSwatches
                if theme.accentTheme == .custom {
                    ColorPicker("Custom color", selection: customBinding, supportsOpacity: false)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var accentSwatches: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(40), spacing: 10), count: 6), spacing: 12) {
            ForEach(AccentTheme.allCases) { t in
                let color = t.color(customHex: theme.customAccentHex)
                Button { theme.accentTheme = t } label: {
                    VStack(spacing: 5) {
                        ZStack {
                            if t == .custom {
                                // Rainbow wheel signals "pick any colour".
                                Circle().fill(AngularGradient(
                                    colors: [.red, .orange, .yellow, .green, .cyan, .blue, .purple, .pink, .red],
                                    center: .center)).frame(width: 28, height: 28)
                                Image(systemName: "eyedropper").font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(.white)
                                    .shadow(color: .black.opacity(0.4), radius: 1)
                            } else {
                                Circle().fill(color).frame(width: 28, height: 28)
                            }
                            if theme.accentTheme == t {
                                Circle().strokeBorder(.primary, lineWidth: 2).frame(width: 34, height: 34)
                            }
                        }
                        .frame(width: 34, height: 34)
                        Text(t.label).font(.system(size: 9)).foregroundStyle(.secondary)
                            .lineLimit(1).minimumScaleFactor(0.55).frame(width: 44)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }

    private var customBinding: Binding<Color> {
        Binding(
            get: { Color(hex: theme.customAccentHex) ?? .pink },
            set: { theme.customAccentHex = $0.toHex() ?? theme.customAccentHex }
        )
    }
}
