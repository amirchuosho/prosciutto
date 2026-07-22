import SwiftUI
import ProsciuttoKit
import Carbon.HIToolbox
import QuartzCore

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
    private let videoEditor = VideoEditService()
    /// Built lazily on first preview — not at launch — so the app never constructs a
    /// material-backed hosting view before it has finished launching.
    private var imagePreviewPanel: ImagePreviewPanel?
    private(set) var monitor: ClipboardMonitor!
    private(set) var panel: GalleryPanel!
    private(set) var vm: GalleryViewModel!
    private var pruneTimer: Timer?
    private var keyMonitor: Any?
    private var scrollMonitor: Any?
    private var scrollAccum: CGFloat = 0   // trackpad delta accumulator (points per step)

    @Published var isPaused = false
    /// Menu-bar ham pulse: 0 = idle, 1 = full pink. Eased 0→1→0 per capture. See `HamBarLabel`.
    @Published var pulseLevel: CGFloat = 0
    private var pulseTimer: Timer?
    private var pulseStart: CFTimeInterval = 0
    private static let pulseDuration: CFTimeInterval = 0.55

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
        vm.editMedia = { [weak self] item in
            if item.kind == .video { self?.videoEditor.edit(item) }
            else { self?.imageEditor.edit(item) }
        }
        vm.cropMedia = { [weak self] item in self?.videoEditor.crop(item) }
        vm.onPreviewAnchor = { [weak self] anchor in self?.updateImagePreview(anchor) }
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
                self?.pulseIcon()
                if self?.panel.isVisible == true { await self?.vm.reload() }
            }
        }
        isPaused = Preferences.shared.isPaused
        monitor.isPaused = isPaused
        monitor.start(interval: 0.3)

        vm.query.fuzzy = Preferences.shared.useFuzzySearch
        reloadHotkey()
        installKeyMonitor()
        installScrollMonitor()
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
        if let scrollMonitor { NSEvent.removeMonitor(scrollMonitor) }
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
            vm.resetToHome()            // newest clip + strip reset to start (pins visible)
        }
    }

    func hideGallery(restoreFocus: Bool = true) {
        deactivateSlotHotkeys()         // release ⌘1–9 back to the rest of the system
        vm.previewID = nil              // never reopen with a stale image preview up
        imagePreviewPanel?.hide()       // close the floating preview with the gallery (if built)
        panel.hide(restoreFocus: restoreFocus)
    }

    /// Position or hide the floating image preview from the previewed card's on-screen
    /// frame (SwiftUI global coords: origin top-left, y-down within the strip window).
    /// nil `anchor` → hide.
    private func updateImagePreview(_ anchor: (id: UUID, rect: CGRect)?) {
        guard let anchor,
              let item = vm.items.first(where: { $0.id == anchor.id }),
              let image = ImageDecodeCache.image(for: item),
              let screen = panel.screen else {
            imagePreviewPanel?.hide()
            return
        }
        let previewPanel = imagePreviewPanel ?? {
            let p = ImagePreviewPanel(); imagePreviewPanel = p; return p
        }()
        // Convert the card's window-relative (y-down) frame to screen coords (y-up).
        let win = panel.windowFrame
        let centerX = win.minX + anchor.rect.midX
        let topY = win.maxY - anchor.rect.minY   // screen Y of the card's TOP edge
        previewPanel.show(image: image, anchorCenterX: centerX, anchorTopY: topY,
                          on: screen, animated: !reduceMotion)
    }

    private var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
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
                if mods == .command, event.keyCode == 6 {                 // ⌘Z undo delete
                    Task { await self.vm.undoDelete() }; return nil
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
            case 49:   // space → toggle the image preview, only when not typing into search
                if self.vm.query.text.isEmpty, self.vm.togglePreview() { return nil }
                return event   // no image / active search → space types as before
            default:       return event                             // typing → search
            }
        }
    }

    /// Scroll over the strip moves the SELECTION like the arrow keys, rather than
    /// panning. The gallery is selection-driven (the selected card is what pastes), a
    /// bare mouse wheel doesn't pan a horizontal SwiftUI ScrollView well, and panning
    /// wouldn't move the highlight anyway. Reuses the local-monitor pattern from
    /// `installKeyMonitor`; scoped to the panel window so it never hijacks scrolling
    /// in Settings.
    private func installScrollMonitor() {
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self, self.panel.isVisible, !self.panel.hasSheet, !self.vm.isEditingTitle,
                  self.panel.owns(event.window) else { return event }
            // Horizontal strip: take whichever axis was scrolled (mouse wheel = Y,
            // trackpad horizontal swipe = X). Normalize so a natural forward gesture
            // (scroll down / swipe left) advances to the NEXT card.
            let raw = abs(event.scrollingDeltaX) >= abs(event.scrollingDeltaY)
                ? event.scrollingDeltaX : event.scrollingDeltaY
            guard raw != 0 else { return event }
            let forward = event.isDirectionInvertedFromDevice ? raw : -raw

            if event.hasPreciseScrollingDeltas {
                // Trackpad. Ignore the inertial momentum phase — otherwise a flick
                // keeps stepping the selection after the fingers lift, which feels
                // runaway. Only the active gesture moves the highlight. Accumulate the
                // small deltas and step once per threshold so a swipe doesn't blur
                // through the whole strip.
                guard event.momentumPhase == [] else { return nil }
                self.scrollAccum += forward
                // Points of active swipe per one-card step. Higher = slower/calmer;
                // this is purely a feel constant, tune to taste.
                let threshold: CGFloat = 36
                while abs(self.scrollAccum) >= threshold {
                    self.vm.moveSelection(self.scrollAccum > 0 ? 1 : -1)
                    self.scrollAccum -= self.scrollAccum > 0 ? threshold : -threshold
                }
            } else {
                // Mouse wheel: one notch = one card.
                self.vm.moveSelection(forward > 0 ? 1 : -1)
            }
            return nil   // consume so the ScrollView doesn't also pan
        }
    }

    /// Rebuild capture policy from Preferences and push it into the live monitor.
    func applyCaptureSettings() {
        monitor.exclusion = ExclusionPolicy(blockedBundleIDs: Preferences.shared.blockedBundleIDs)
        monitor.captureFilter = Preferences.shared.captureFilter
    }

    /// Start/stop the screen-capture watcher to match the current preferences. One
    /// watcher covers both screenshots and recordings; per-type flags decide which it
    /// copies. It runs whenever either is enabled.
    func applyScreenshotWatch() {
        let shots = Preferences.shared.autoCopyScreenshots
        let recs = Preferences.shared.autoCopyRecordings
        screenshotWatcher.copyScreenshots = shots
        screenshotWatcher.copyRecordings = recs
        if shots || recs { screenshotWatcher.start() }
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

    /// Eases the ham through a pink pulse. A rapid second capture resets the start time,
    /// so the envelope restarts rather than stacking timers.
    private func pulseIcon() {
        pulseStart = CACurrentMediaTime()
        guard pulseTimer == nil else { return }
        // ~60fps; each tick drives `pulseLevel`. See `HamBarLabel` for why we re-render.
        pulseTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self else { timer.invalidate(); return }
                let elapsed = CACurrentMediaTime() - self.pulseStart
                self.pulseLevel = Self.pulseEnvelope(elapsed)
                if elapsed >= Self.pulseDuration {
                    self.pulseLevel = 0
                    timer.invalidate()
                    self.pulseTimer = nil
                }
            }
        }
    }

    /// 0→1→0 pulse shape: ease-in, hold at full pink, ease-out.
    private static func pulseEnvelope(_ t: CFTimeInterval) -> CGFloat {
        let attack = 0.15, hold = 0.12, release = 0.28
        func smooth(_ x: Double) -> Double { let c = min(max(x, 0), 1); return c * c * (3 - 2 * c) }
        if t < attack { return CGFloat(smooth(t / attack)) }
        let t2 = t - attack
        if t2 < hold { return 1 }
        let t3 = t2 - hold
        if t3 < release { return CGFloat(1 - smooth(t3 / release)) }
        return 0
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
