import SwiftUI
import AppKit

struct SettingsView: View {
    @EnvironmentObject var theme: ThemeManager
    @State private var maxItems = Preferences.shared.maxItems
    @State private var maxAgeDays = Preferences.shared.maxAgeDays
    @State private var soundEnabled = Preferences.shared.captureSoundEnabled
    @State private var soundName = Preferences.shared.captureSoundName

    private let systemSounds = ["Pop", "Tink", "Glass", "Bottle", "Frog", "Submarine", "Morse"]

    var body: some View {
        TabView {
            general.tabItem { Label("General", systemImage: "gearshape") }
            appearance.tabItem { Label("Appearance", systemImage: "paintbrush") }
            PermissionView().tabItem { Label("Permissions", systemImage: "hand.raised") }
        }
        .frame(width: 460, height: 360)
    }

    // MARK: General

    private var general: some View {
        Form {
            Section("History") {
                Stepper("Keep up to \(maxItems) items", value: $maxItems, in: 100...10_000, step: 100)
                    .onChange(of: maxItems) { _, v in Preferences.shared.maxItems = v }
                Stepper("Expire unpinned after \(maxAgeDays) days", value: $maxAgeDays, in: 1...90)
                    .onChange(of: maxAgeDays) { _, v in Preferences.shared.maxAgeDays = v }
            }
            Section("Sound") {
                Toggle("Play a sound when copying", isOn: $soundEnabled)
                    .onChange(of: soundEnabled) { _, v in Preferences.shared.captureSoundEnabled = v }
                Picker("Sound", selection: $soundName) {
                    ForEach(systemSounds, id: \.self) { Text($0).tag($0) }
                }
                .disabled(!soundEnabled)
                .onChange(of: soundName) { _, v in
                    Preferences.shared.captureSoundName = v
                    NSSound(named: v)?.play()
                }
            }
            Section("Hotkey") {
                LabeledContent("Open gallery", value: "⌘⇧V")
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
        HStack(spacing: 12) {
            ForEach(AccentTheme.allCases) { t in
                let color = t.color(customHex: theme.customAccentHex)
                Button { theme.accentTheme = t } label: {
                    VStack(spacing: 5) {
                        ZStack {
                            Circle().fill(color).frame(width: 28, height: 28)
                            if t == .custom {
                                Image(systemName: "eyedropper").font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                            if theme.accentTheme == t {
                                Circle().strokeBorder(.primary, lineWidth: 2).frame(width: 34, height: 34)
                            }
                        }
                        .frame(width: 34, height: 34)
                        Text(t.label).font(.system(size: 9)).foregroundStyle(.secondary)
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

extension Color {
    /// Hex string like "#RRGGBB" from this color (best-effort via NSColor).
    func toHex() -> String? {
        guard let rgb = NSColor(self).usingColorSpace(.sRGB) else { return nil }
        let r = Int(round(rgb.redComponent * 255))
        let g = Int(round(rgb.greenComponent * 255))
        let b = Int(round(rgb.blueComponent * 255))
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
