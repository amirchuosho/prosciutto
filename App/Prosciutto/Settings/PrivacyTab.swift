import SwiftUI
import AppKit

struct PrivacyTab: View {
    @State private var blocked: [String] = Array(Preferences.shared.blockedBundleIDs).sorted()

    private func persist() {
        Preferences.shared.blockedBundleIDs = Set(blocked)
        NotificationCenter.default.post(name: .prosciuttoSettingsChanged, object: nil)
    }

    private var addableApps: [NSRunningApplication] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil }
            .filter { !blocked.contains($0.bundleIdentifier!) }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
    }

    var body: some View {
        Form {
            Section("Don't capture from these apps") {
                if blocked.isEmpty {
                    Text("No ignored apps.").foregroundStyle(.secondary)
                }
                ForEach(blocked, id: \.self) { id in
                    HStack {
                        if let icon = AppIconProvider.icon(forBundleID: id) {
                            Image(nsImage: icon).resizable().frame(width: 18, height: 18)
                        }
                        Text(appName(for: id))
                        Spacer()
                        Button(role: .destructive) {
                            blocked.removeAll { $0 == id }; persist()
                        } label: { Image(systemName: "minus.circle.fill") }
                        .buttonStyle(.plain).foregroundStyle(.red)
                    }
                }
            }
            Section {
                Menu("Add app…") {
                    ForEach(addableApps, id: \.bundleIdentifier) { app in
                        Button(app.localizedName ?? app.bundleIdentifier!) {
                            if let id = app.bundleIdentifier, !blocked.contains(id) {
                                blocked.append(id); blocked.sort(); persist()
                            }
                        }
                    }
                }
                Text("Useful for password managers and other sensitive apps.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func appName(for bundleID: String) -> String {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID),
           let name = FileManager.default.displayName(atPath: url.path) as String? {
            return name.replacingOccurrences(of: ".app", with: "")
        }
        return bundleID
    }
}
