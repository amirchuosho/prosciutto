import Foundation

public final class ClipboardMonitor {
    private let reader: PasteboardReader
    private let store: ClipStore
    private let exclusion: ExclusionPolicy
    private let clock: Clock
    private let ttl: TimeInterval
    private var lastChangeCount: Int
    private var pollingTask: Task<Void, Never>?
    public var isPaused = false
    /// Fired after a new item is captured and stored.
    public var onCapture: (() -> Void)?

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
        onCapture?()
    }

    /// Polls on a single serialized loop. Each poll (including the async store
    /// write) completes before the next begins, so overlapping polls can't
    /// double-process the same pasteboard change.
    public func start(interval: TimeInterval) {
        pollingTask?.cancel()
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await self?.poll()
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            }
        }
    }

    public func stop() {
        pollingTask?.cancel()
        pollingTask = nil
    }
}
