import SwiftUI

struct SettingsView: View {
    @State private var maxItems = Preferences.shared.maxItems
    @State private var maxAgeDays = Preferences.shared.maxAgeDays

    var body: some View {
        TabView {
            general.tabItem { Label("General", systemImage: "gearshape") }
            PermissionView().tabItem { Label("Permissions", systemImage: "hand.raised") }
        }
        .frame(width: 420, height: 260)
    }

    private var general: some View {
        Form {
            Section("History") {
                Stepper("Keep up to \(maxItems) items", value: $maxItems, in: 100...10_000, step: 100)
                    .onChange(of: maxItems) { _, v in Preferences.shared.maxItems = v }
                Stepper("Expire unpinned after \(maxAgeDays) days", value: $maxAgeDays, in: 1...90)
                    .onChange(of: maxAgeDays) { _, v in Preferences.shared.maxAgeDays = v }
            }
            Section("Hotkey") {
                LabeledContent("Open gallery", value: "⌘⇧V")
            }
        }
        .padding()
    }
}
