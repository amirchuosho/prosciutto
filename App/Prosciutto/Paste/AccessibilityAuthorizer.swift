import ApplicationServices

enum AccessibilityAuthorizer {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    static func prompt() {
        let opts = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true]
        _ = AXIsProcessTrustedWithOptions(opts as CFDictionary)
    }
}
