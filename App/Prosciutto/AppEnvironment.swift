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

        vm.onDismiss = { [weak self] in self?.panel.hide() }
        vm.onPaste = { [weak self] item, plain in
            guard let self else { return }
            self.panel.hide()                       // restores previous app focus
            self.paste.write(item, asPlainText: plain)
            // Give the target app a beat to become active, then paste.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                self.paste.synthesizePaste()
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

        hotkey.onTrigger = { [weak self] in self?.openGallery() }
        hotkey.register()

        startPruneTimer()

        if !AccessibilityAuthorizer.isTrusted {
            AccessibilityAuthorizer.prompt()
        }
    }

    func openGallery() {
        panel.show()                    // show instantly, no delay
        Task { await vm.reload() }       // populate (cards animate in)
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
