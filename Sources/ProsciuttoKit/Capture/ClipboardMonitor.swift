import Foundation

public final class ClipboardMonitor {
    private let reader: PasteboardReader
    private let store: ClipStore
    public var exclusion: ExclusionPolicy
    public var captureFilter: CaptureFilter
    private let clock: Clock
    private let ttl: TimeInterval
    private var lastChangeCount: Int
    /// Guards `lastChangeCount`: `poll()` runs on a background Task while
    /// `acknowledgeSelfWrite()` is called from the main thread.
    private let changeLock = NSLock()
    private var pollingTask: Task<Void, Never>?
    public var isPaused = false
    /// Fired after a new item is captured and stored.
    public var onCapture: (() -> Void)?

    public init(reader: PasteboardReader, store: ClipStore, exclusion: ExclusionPolicy,
                clock: Clock, ttl: TimeInterval, captureFilter: CaptureFilter = .unrestricted) {
        self.reader = reader
        self.store = store
        self.exclusion = exclusion
        self.captureFilter = captureFilter
        self.clock = clock
        self.ttl = ttl
        self.lastChangeCount = reader.changeCount
    }

    public func poll() async throws {
        guard !isPaused else { return }
        let current = reader.changeCount           // may hop to main; read before locking
        changeLock.lock()
        let isNew = current != lastChangeCount
        if isNew { lastChangeCount = current }
        changeLock.unlock()
        guard isNew else { return }
        guard let snap = reader.snapshot(), exclusion.shouldCapture(snap),
              let kind = KindDetector.detect(snap) else { return }
        let item = ClipItem.make(from: snap, kind: kind, now: clock.now(), ttl: ttl)
        let byteSize = item.imageData?.count ?? item.textPlain?.utf8.count ?? 0
        guard captureFilter.shouldCapture(kind: kind, byteSize: byteSize) else { return }
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

    /// The app itself just wrote to the pasteboard (e.g. a paste) — swallow that
    /// change so the next poll doesn't re-capture it as a brand-new clip.
    public func acknowledgeSelfWrite() {
        let current = reader.changeCount           // read before locking
        changeLock.lock()
        lastChangeCount = current
        changeLock.unlock()
    }
}
