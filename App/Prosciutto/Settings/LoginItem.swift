import ServiceManagement

/// Launch-at-login backed by SMAppService. The OS is the source of truth, so the
/// settings toggle reads `isEnabled` and writes via `setEnabled`.
enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static func setEnabled(_ on: Bool) throws {
        if on {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
