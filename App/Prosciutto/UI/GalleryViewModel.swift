import SwiftUI
import ProsciuttoKit

@MainActor
final class GalleryViewModel: ObservableObject {
    @Published var items: [ClipItem] = []
    @Published var query = ClipQuery()
    @Published var selection: Int = 0

    private let store: ClipStore

    /// Set by AppEnvironment. Hides the panel, restores the previous app, then synthesizes paste.
    var onPaste: (ClipItem, Bool) -> Void = { _, _ in }
    /// Set by AppEnvironment. Dismisses the gallery without pasting.
    var onDismiss: () -> Void = {}

    init(store: ClipStore) {
        self.store = store
    }

    func reload() async {
        let all = (try? await store.all()) ?? []
        // Pinned float to the front, then most-recently-used.
        items = all.sorted { a, b in
            if a.isPinned != b.isPinned { return a.isPinned && !b.isPinned }
            return a.lastUsedAt > b.lastUsedAt
        }
        selection = min(selection, max(0, filtered().count - 1))
    }

    func filtered() -> [ClipItem] {
        query.apply(to: items)
    }

    func moveSelection(_ delta: Int) {
        let count = filtered().count
        guard count > 0 else { return }
        selection = min(max(0, selection + delta), count - 1)
    }

    func pasteSelected(asPlainText: Bool = false) {
        let list = filtered()
        guard list.indices.contains(selection) else { return }
        onPaste(list[selection], asPlainText)
    }

    func pasteIndex(_ i: Int) {
        let list = filtered()
        guard i >= 1, list.indices.contains(i - 1) else { return }
        onPaste(list[i - 1], false)
    }

    func togglePin(_ item: ClipItem) async {
        try? await store.setPinned(id: item.id, !item.isPinned)
        await reload()
    }

    func delete(_ item: ClipItem) async {
        try? await store.delete(id: item.id)
        await reload()
    }
}
