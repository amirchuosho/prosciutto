import SwiftUI
import ProsciuttoKit
import Carbon.HIToolbox

@MainActor
final class AppEnvironment: ObservableObject {
    /// Single shared instance. The App struct can be constructed more than once
    /// by SwiftUI; a plain `@StateObject = AppEnvironment()` would then run the
    /// init side-effects (monitor.start, Core Data stack, observers) multiple
    /// times, spawning duplicate pollers that race the same store. A singleton
    /// guarantees the setup happens exactly once.
    static let shared = AppEnvironment()

    let store = CoreDataClipStore()
    let paste = PasteService()
    let reader = SystemPasteboardReader()
    private let hotkeys = HotkeyCenter.shared
    let theme = ThemeManager()
    private let screenshotWatcher = ScreenshotWatcher()
    private let imageEditor = ImageEditService()
    private(set) var monitor: ClipboardMonitor!
    private(set) var panel: GalleryPanel!
    private(set) var vm: GalleryViewModel!
    private var pruneTimer: Timer?
    private var keyMonitor: Any?

    @Published var isPaused = false

    private init() {
        let vm = GalleryViewModel(store: store)
        self.vm = vm
        let theme = self.theme

        let panel = GalleryPanel {
            AnyView(
                GalleryView(model: vm)
                    .environmentObject(theme)
            )
        }
        self.panel = panel

        // Click-away / app-switch dismissal: DON'T restore focus — the app the user
        // switched to is already frontmost, and yanking it back would shove it behind.
        panel.onResign = { [weak self] in self?.hideGallery(restoreFocus: false) }
        vm.onDismiss = { [weak self] in self?.hideGallery() }
        vm.editImage = { [weak self] item in self?.imageEditor.edit(item) }
        vm.onPaste = { [weak self] item, plain in
            guard let self else { return }
            self.paste.write(item, asPlainText: plain)       // always put it on the clipboard
            self.monitor.acknowledgeSelfWrite()               // ...but don't re-capture it as a dup
            Task { await self.vm.recordUse(item) }            // bump recency: bring it to the front
            self.deactivateSlotHotkeys()                      // gallery closing → release ⌘1–9

            let auto = Preferences.shared.pasteAutomatically
            // Hide first; only synthesize ⌘V AFTER the panel is gone and the
            // previous app is active, so the keystroke never lands in our search.
            self.panel.hide {
                guard auto else { return }
                // The open hotkey may BE ⌘V (the user can rebind it to replace
                // system paste). Our synthesized ⌘V would then be caught by our
                // own global hotkey and reopen the gallery instead of pasting.
                // Drop the hotkey while we synthesize, then restore it.
                self.hotkeys.unregister(id: HotkeyCenter.ID.open)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.07) {
                    self.paste.synthesizePaste()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        self.reloadHotkey()
                    }
                }
            }
        }

        let ttl = TimeInterval(Preferences.shared.maxAgeDays) * 86_400
        monitor = ClipboardMonitor(reader: reader, store: store,
                                   exclusion: ExclusionPolicy(blockedBundleIDs: Preferences.shared.blockedBundleIDs),
                                   clock: SystemClock(), ttl: ttl,
                                   captureFilter: Preferences.shared.captureFilter)
        monitor.onCapture = { [weak self] in
            Task { @MainActor in
                self?.playCaptureSound()
                if self?.panel.isVisible == true { await self?.vm.reload() }
            }
        }
        isPaused = Preferences.shared.isPaused
        monitor.isPaused = isPaused
        monitor.start(interval: 0.3)

        vm.query.fuzzy = Preferences.shared.useFuzzySearch
        reloadHotkey()
        installKeyMonitor()
        applyScreenshotWatch()

        NotificationCenter.default.addObserver(forName: .prosciuttoSettingsChanged, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.applyCaptureSettings()
                self?.applyScreenshotWatch()
                self?.reloadHotkey()
                self?.vm.query.fuzzy = Preferences.shared.useFuzzySearch
                await self?.vm.reload()
            }
        }

        // Show the gallery when the user re-opens the app from Launchpad/Dock.
        NotificationCenter.default.addObserver(forName: .prosciuttoOpenGallery, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.openGallery() }
        }

        startPruneTimer()

        if !AccessibilityAuthorizer.isTrusted {
            AccessibilityAuthorizer.prompt()
        }
    }

    deinit {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        pruneTimer?.invalidate()
    }

    func toggleGallery() {
        panel.isVisible ? hideGallery() : openGallery()
    }

    func openGallery() {
        panel.show()                    // show instantly, no delay
        activateSlotHotkeys()           // grab ⌘1–9 while open, before the front app can
        Task {
            vm.sectionFilter = .all     // always start on All, no leftover group
            vm.query.text = ""          // cleared search
            await vm.reload()
            vm.selectNewestUnpinned()   // land on the newest clip, not the last-paste spot
            vm.homeScrollToken += 1     // reset the strip to the start (pins visible)
        }
    }

    func hideGallery(restoreFocus: Bool = true) {
        deactivateSlotHotkeys()         // release ⌘1–9 back to the rest of the system
        panel.hide(restoreFocus: restoreFocus)
    }

    /// ⌘1–9 paste the pinned quick-slots, grabbed globally *only* while the gallery is
    /// open so they beat the front app's own ⌘1–9 (tab switching) — then released so
    /// they behave normally everywhere else.
    private func activateSlotHotkeys() {
        for n in 1...9 {
            hotkeys.register(id: HotkeyCenter.ID.slot(n),
                             keyCode: HotkeyCenter.digitKeyCodes[n - 1],
                             modifiers: UInt32(cmdKey)) { [weak self] in
                self?.vm.pasteIndex(n)
            }
        }
    }

    private func deactivateSlotHotkeys() {
        for n in 1...9 { hotkeys.unregister(id: HotkeyCenter.ID.slot(n)) }
    }

    /// Intercept navigation keys before the focused search field swallows them.
    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.panel.isVisible, !self.panel.hasSheet,
                  !self.vm.isEditingTitle else { return event }
            let mods = event.modifierFlags.intersection([.command, .option, .control, .shift])

            // Configurable plain-paste — checked first and matched by its exact
            // combo, so it works no matter which modifier the user bound it to
            // (not only ⌘-combos).
            let plain = KeyCombo(storedKeyCode: Preferences.shared.plainPasteKeyCode,
                                 storedModifiers: Preferences.shared.plainPasteModifiers)
            if plain.matches(keyCode: event.keyCode, modifiers: mods) {
                self.vm.pasteSelected(asPlainText: true); return nil  // plain paste
            }

            // ⌘ combinations. Note ⌘1–9 are NOT handled here: a non-activating panel
            // never wins them from the front app's menu, so they're grabbed globally
            // via HotkeyCenter while the gallery is open (see activateSlotHotkeys).
            if mods.contains(.command) {
                if mods == .command, event.keyCode == 123 { self.vm.moveToStart(); return nil }  // ⌘← start
                if mods == .command, event.keyCode == 124 { self.vm.moveToEnd(); return nil }     // ⌘→ end
                if mods == .command, event.keyCode == 51 {                // ⌘⌫ delete
                    Task { await self.vm.deleteSelected() }; return nil
                }
                return event
            }

            // Navigation keys. Arrow keys carry .function/.numericPad flags, so
            // match on keyCode and ignore non-command modifiers here.
            switch event.keyCode {
            case 123, 126: self.vm.moveSelection(-1); return nil   // left / up
            case 124, 125: self.vm.moveSelection(1); return nil    // right / down
            case 36, 76:   self.vm.pasteSelected(); return nil     // return / enter
            case 53:       self.hideGallery(); return nil          // esc
            case 51:                                               // delete: only when not mid-search
                if self.vm.query.text.isEmpty { Task { await self.vm.deleteSelected() }; return nil }
                return event
            default:       return event                             // typing → search
            }
        }
    }

    /// Rebuild capture policy from Preferences and push it into the live monitor.
    func applyCaptureSettings() {
        monitor.exclusion = ExclusionPolicy(blockedBundleIDs: Preferences.shared.blockedBundleIDs)
        monitor.captureFilter = Preferences.shared.captureFilter
    }

    /// Start/stop the screenshot watcher to match the current preference.
    func applyScreenshotWatch() {
        if Preferences.shared.autoCopyScreenshots { screenshotWatcher.start() }
        else { screenshotWatcher.stop() }
    }

    /// (Re)register the global open-gallery hotkey from Preferences.
    func reloadHotkey() {
        let combo = KeyCombo(storedKeyCode: Preferences.shared.openHotkeyKeyCode,
                             storedModifiers: Preferences.shared.openHotkeyModifiers)
        hotkeys.register(id: HotkeyCenter.ID.open,
                         keyCode: UInt32(combo.keyCode),
                         modifiers: combo.carbonModifiers) { [weak self] in
            self?.toggleGallery()
        }
    }

    func togglePause() {
        isPaused.toggle()
        monitor.isPaused = isPaused
        Preferences.shared.isPaused = isPaused
    }

    private func playCaptureSound() {
        guard Preferences.shared.captureSoundEnabled else { return }
        NSSound(named: Preferences.shared.captureSoundName)?.play()
    }

    private func startPruneTimer() {
        pruneTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { try? await self.store.prune(keeping: Preferences.shared.retentionPolicy, now: Date()) }
        }
    }
}

extension Notification.Name {
    static let prosciuttoSettingsChanged = Notification.Name("prosciutto.settingsChanged")
}
