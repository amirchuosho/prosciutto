import SwiftUI
import ProsciuttoKit

@MainActor
final class AppEnvironment: ObservableObject {
    let store = CoreDataClipStore()
    let paste = PasteService()
    let reader = SystemPasteboardReader()
    let hotkey = HotkeyManager()
    let theme = ThemeManager()
    private(set) var monitor: ClipboardMonitor!
    private(set) var panel: GalleryPanel!
    private(set) var vm: GalleryViewModel!
    private var pruneTimer: Timer?
    private var keyMonitor: Any?

    @Published var isPaused = false

    init() {
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

        panel.onResign = { [weak self] in self?.hideGallery() }
        vm.onDismiss = { [weak self] in self?.hideGallery() }
        vm.onPaste = { [weak self] item, plain in
            guard let self else { return }
            self.paste.write(item, asPlainText: plain)       // always put it on the clipboard
            let auto = Preferences.shared.pasteAutomatically
            // Hide first; only synthesize ⌘V AFTER the panel is gone and the
            // previous app is active, so the keystroke never lands in our search.
            self.panel.hide {
                guard auto else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.07) {
                    self.paste.synthesizePaste()
                }
            }
        }

        let ttl = TimeInterval(Preferences.shared.maxAgeDays) * 86_400
        monitor = ClipboardMonitor(reader: reader, store: store,
                                   exclusion: ExclusionPolicy(blockedBundleIDs: Preferences.shared.blockedBundleIDs),
                                   clock: SystemClock(), ttl: ttl)
        monitor.onCapture = { [weak self] in
            Task { @MainActor in
                self?.playCaptureSound()
                if self?.panel.isVisible == true { await self?.vm.reload() }
            }
        }
        isPaused = Preferences.shared.isPaused
        monitor.isPaused = isPaused
        monitor.start(interval: 0.3)

        hotkey.onTrigger = { [weak self] in self?.toggleGallery() }
        hotkey.register()
        installKeyMonitor()

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
        Task { await vm.reload() }       // populate (cards animate in)
    }

    func hideGallery() {
        panel.hide()
    }

    /// Intercept navigation keys before the focused search field swallows them.
    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.panel.isVisible, !self.panel.hasSheet,
                  !self.vm.isEditingTitle else { return event }
            let mods = event.modifierFlags.intersection([.command, .option, .control, .shift])

            // ⌘ combinations first
            if mods.contains(.command) {
                if mods == .command, let s = event.charactersIgnoringModifiers,
                   let n = Int(s), (1...9).contains(n) {
                    self.vm.pasteIndex(n); return nil               // ⌘1–9 paste
                }
                if mods == [.command, .option],
                   event.charactersIgnoringModifiers?.lowercased() == "v" {
                    self.vm.pasteSelected(asPlainText: true); return nil  // ⌘⌥V plain paste
                }
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
