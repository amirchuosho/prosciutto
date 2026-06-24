import SwiftUI

struct PermissionView: View {
    @State private var trusted = AccessibilityAuthorizer.isTrusted

    var body: some View {
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
                Button("Grant Access…") {
                    AccessibilityAuthorizer.prompt()
                }
                Button("Refresh") { trusted = AccessibilityAuthorizer.isTrusted }
            }
        }
        .padding()
        .frame(width: 380)
    }
}
