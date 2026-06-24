import SwiftUI
import ProsciuttoKit

@MainActor
final class GalleryViewModel: ObservableObject {
    @Published var items: [ClipItem] = []
    @Published var query = ClipQuery()
    @Published var selection: Int = 0

    private let store: ClipStore
    private let paste: PasteService
    var onPasted: () -> Void = {}

    init(store: ClipStore, paste: PasteService) {
        self.store = store
        self.paste = paste
    }

    func reload() async {
        items = (try? await store.all()) ?? []
        selection = 0
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
        paste.paste(list[selection], asPlainText: asPlainText)
        onPasted()
    }

    func pasteIndex(_ i: Int) {
        let list = filtered()
        guard i >= 1, list.indices.contains(i - 1) else { return }
        paste.paste(list[i - 1])
        onPasted()
    }

    func togglePin(_ item: ClipItem) async {
        try? await store.setPinned(id: item.id, !item.isPinned)
        await reload()
    }
}
