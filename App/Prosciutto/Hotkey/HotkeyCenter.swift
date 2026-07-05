import Carbon.HIToolbox
import AppKit

/// One place that owns every global (Carbon) hotkey in the app: the open-gallery
/// shortcut and the ⌘1–9 quick-paste slots. A single shared event handler dispatches
/// by hotkey id to the registered action.
///
/// Why one center instead of a manager per hotkey: Carbon delivers every
/// `kEventHotKeyPressed` to *all* installed handlers on the app target until one
/// returns `noErr`. Two independent handlers therefore race on install order and,
/// worse, each sees the *other's* hotkeys — so an open-hotkey press could be read as
/// a slot press (and vice-versa). Routing everything through one handler keyed by a
/// unique id removes both problems.
final class HotkeyCenter {
    static let shared = HotkeyCenter()

    /// Stable ids. Kept distinct so no two hotkeys ever collide in dispatch.
    enum ID {
        static let open: UInt32 = 1
        /// ⌘1–9 quick-paste slots occupy 11…19.
        static func slot(_ n: Int) -> UInt32 { UInt32(10 + n) }
    }

    /// Key codes for the number row 1…9 (kVK_ANSI_1…_9 are not sequential).
    static let digitKeyCodes: [UInt32] = [
        UInt32(kVK_ANSI_1), UInt32(kVK_ANSI_2), UInt32(kVK_ANSI_3),
        UInt32(kVK_ANSI_4), UInt32(kVK_ANSI_5), UInt32(kVK_ANSI_6),
        UInt32(kVK_ANSI_7), UInt32(kVK_ANSI_8), UInt32(kVK_ANSI_9),
    ]

    private let signature = OSType(0x50524f53) // 'PROS'
    private var actions: [UInt32: () -> Void] = [:]
    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var handler: EventHandlerRef?

    private init() {}

    /// Register (or replace) a global hotkey. `action` runs on the main thread when
    /// the combo is pressed, anywhere in the system.
    func register(id: UInt32, keyCode: UInt32, modifiers: UInt32, action: @escaping () -> Void) {
        installHandlerIfNeeded()
        unregister(id: id)
        actions[id] = action
        var ref: EventHotKeyRef?
        RegisterEventHotKey(keyCode, modifiers,
                            EventHotKeyID(signature: signature, id: id),
                            GetApplicationEventTarget(), 0, &ref)
        refs[id] = ref
    }

    func unregister(id: UInt32) {
        if let ref = refs[id] { UnregisterEventHotKey(ref) }
        refs[id] = nil
        actions[id] = nil
    }

    private func installHandlerIfNeeded() {
        guard handler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            guard let event else { return OSStatus(eventNotHandledErr) }
            var hkID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject),
                              EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &hkID)
            return HotkeyCenter.shared.dispatch(hkID.id)
        }, 1, &spec, nil, &handler)
    }

    private func dispatch(_ id: UInt32) -> OSStatus {
        guard let action = actions[id] else { return OSStatus(eventNotHandledErr) }
        action()
        return noErr
    }
}
