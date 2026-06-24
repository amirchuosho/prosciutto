import Foundation

public final class ClipboardMonitor {
    private let reader: PasteboardReader
    private let store: ClipStore
    private let exclusion: ExclusionPolicy
    private let clock: Clock
    private let ttl: TimeInterval
    private var lastChangeCount: Int
    private var timer: Timer?
    public var isPaused = false

    public init(reader: PasteboardReader, store: ClipStore, exclusion: ExclusionPolicy,
                clock: Clock, ttl: TimeInterval) {
        self.reader = reader
        self.store = store
        self.exclusion = exclusion
        self.clock = clock
        self.ttl = ttl
        self.lastChangeCount = reader.changeCount
    }

    public func poll() async throws {
        guard !isPaused else { return }
        let current = reader.changeCount
        guard current != lastChangeCount else { return }
        lastChangeCount = current
        guard let snap = reader.snapshot(), exclusion.shouldCapture(snap),
              let kind = KindDetector.detect(snap) else { return }
        let item = ClipItem.make(from: snap, kind: kind, now: clock.now(), ttl: ttl)
        try await store.upsert(item)
    }

    public func start(interval: TimeInterval) {
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { try? await self.poll() }
        }
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
    }
}
