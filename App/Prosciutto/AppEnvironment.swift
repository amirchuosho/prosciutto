import SwiftUI
import ProsciuttoKit

@MainActor
final class AppEnvironment: ObservableObject {
    let store = CoreDataClipStore()
    let paste = PasteService()
    let reader = SystemPasteboardReader()
    let hotkey = HotkeyManager()
    private(set) var monitor: ClipboardMonitor!
    private(set) var panel: GalleryPanel!
    private(set) var vm: GalleryViewModel!
    private var pruneTimer: Timer?

    @Published var isPaused = false

    init() {
        let vm = GalleryViewModel(store: store, paste: paste)
        self.vm = vm

        let panel = GalleryPanel {
            AnyView(GalleryView(model: vm, onDismiss: { [weak self] in self?.panel.hide() }))
        }
        self.panel = panel
        vm.onPasted = { [weak self] in self?.panel.hide() }

        let ttl = TimeInterval(Preferences.shared.maxAgeDays) * 86_400
        monitor = ClipboardMonitor(reader: reader, store: store,
                                   exclusion: ExclusionPolicy(blockedBundleIDs: Preferences.shared.blockedBundleIDs),
                                   clock: SystemClock(), ttl: ttl)
        isPaused = Preferences.shared.isPaused
        monitor.isPaused = isPaused
        monitor.start(interval: 0.3)

        hotkey.onTrigger = { [weak self] in
            guard let self else { return }
            Task { await self.vm.reload(); self.panel.show() }
        }
        hotkey.register()

        startPruneTimer()

        if !AccessibilityAuthorizer.isTrusted {
            AccessibilityAuthorizer.prompt()
        }
    }

    func openGallery() {
        Task { await vm.reload(); panel.show() }
    }

    func togglePause() {
        isPaused.toggle()
        monitor.isPaused = isPaused
        Preferences.shared.isPaused = isPaused
    }

    private func startPruneTimer() {
        pruneTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { try? await self.store.prune(keeping: Preferences.shared.retentionPolicy, now: Date()) }
        }
    }
}
