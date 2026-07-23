import SwiftUI
import AppKit

struct PermissionView: View {
    @State private var trusted = AccessibilityAuthorizer.isTrusted
    // Probing folder access can trigger the macOS prompt, so don't do it at view
    // construction — check on appear (this tab is exactly where a grant belongs).
    @State private var folderAccess = false
    @State private var copiedDiagnostics = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            accessibilityCard
            Divider()
            folderCard
        }
        .padding()
        .frame(width: 440)
        .onAppear {
            folderAccess = ScreenshotWatcher.hasFolderAccess()
            copiedDiagnostics = false
        }
    }

    private var accessibilityCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Accessibility Permission", systemImage: "hand.raised.fill")
                .font(.headline)
            Text("Prosciutto needs Accessibility access to paste items into the app you're using. "
                 + "Without it, items are copied to the clipboard and you press ⌘V yourself.")
                .font(.callout)
                .foregroundStyle(.secondary)
            HStack {
                Circle().fill(trusted ? .green : .orange).frame(width: 10, height: 10)
                Text(trusted ? "Granted" : "Not granted")
                Spacer()
                Button("Grant Access…") { AccessibilityAuthorizer.prompt() }
                Button("Refresh") { trusted = AccessibilityAuthorizer.isTrusted }
            }
        }
    }

    private var folderCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Screenshot & Recording Folder", systemImage: "photo.on.rectangle")
                .font(.headline)
            Text("To copy screenshots and screen recordings automatically, Prosciutto needs to "
                 + "read the folder they're saved to (usually the Desktop). Without access this "
                 + "feature silently does nothing.")
                .font(.callout)
                .foregroundStyle(.secondary)
            HStack {
                Circle().fill(folderAccess ? .green : .orange).frame(width: 10, height: 10)
                Text(folderAccess ? "Granted" : "Not granted")
                Spacer()
                Button("Grant Access…") { grantFolderAccess() }
            }
            Text("Not working? Send this so we can see what happened:")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Reveal Log…") { Self.revealLog() }
                Button(copiedDiagnostics ? "Copied ✓" : "Copy Diagnostics") { copyDiagnostics() }
            }
        }
    }

    /// Attempt access, which shows the macOS prompt the FIRST time. After the user has
    /// explicitly denied, macOS won't prompt again on access — so if we still don't have
    /// it, send them straight to System Settings, where the toggle actually lives.
    private func grantFolderAccess() {
        let granted = ScreenshotWatcher.hasFolderAccess()
        folderAccess = granted
        if !granted { Self.openFilesAndFoldersSettings() }
    }

    private func copyDiagnostics() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(ScreenshotWatcher.diagnosticsReport(), forType: .string)
        copiedDiagnostics = true
        // Revert the button label after a moment (onAppear only fires on tab switches).
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copiedDiagnostics = false }
    }

    private static func revealLog() {
        guard let url = ScreenshotWatcher.logURL else { return }
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            NSWorkspace.shared.open(url.deletingLastPathComponent())   // no log yet — show the folder
        }
    }

    /// Deep-link to System Settings › Privacy & Security › Files and Folders, where the
    /// user can toggle folder access by hand if the prompt didn't appear.
    private static func openFilesAndFoldersSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders") {
            NSWorkspace.shared.open(url)
        }
    }
}
