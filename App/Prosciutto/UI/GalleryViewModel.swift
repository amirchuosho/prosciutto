import SwiftUI
import ProsciuttoKit

enum SectionFilter: Equatable {
    case all, pinned, section(UUID)
}

@MainActor
final class GalleryViewModel: ObservableObject {
    @Published var items: [ClipItem] = []
    @Published var sections: [ClipSection] = []
    @Published var sectionFilter: SectionFilter = .all
    @Published var query = ClipQuery()
    @Published var selection: Int = 0
    /// True while a card title is being edited inline — the key monitor then
    /// leaves arrows/return/esc to the text field instead of navigating cards.
    @Published var isEditingTitle = false

    private let store: ClipStore
    private let sectionPalette = ["#F56B8C", "#5C8FFF", "#52CC85", "#FFAA5C", "#4ECDC8", "#C77DFF"]

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
        sections = (try? await store.sections()) ?? []
        selection = min(selection, max(0, filtered().count - 1))
    }

    func filtered() -> [ClipItem] {
        let base: [ClipItem]
        switch sectionFilter {
        case .all: base = items
        case .pinned: base = items.filter(\.isPinned)
        case .section(let id): base = items.filter { $0.sectionID == id }
        }
        return query.apply(to: base)
    }

    func createSection(name: String) async {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let color = sectionPalette[sections.count % sectionPalette.count]
        _ = try? await store.createSection(name: trimmed, colorHex: color)
        await reload()
    }

    func deleteSection(_ section: ClipSection) async {
        try? await store.deleteSection(id: section.id)
        if sectionFilter == .section(section.id) { sectionFilter = .all }
        await reload()
    }

    var sectionColors: [String] { sectionPalette }

    func assign(_ item: ClipItem, to sectionID: UUID?) async {
        await assignID(item.id, to: sectionID)
    }

    func assignID(_ itemID: UUID, to sectionID: UUID?) async {
        try? await store.assign(itemID: itemID, to: sectionID)
        await reload()
    }

    func updateSection(_ section: ClipSection, name: String, hex: String) async {
        var updated = section
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty { updated.name = trimmed }
        updated.colorHex = hex
        try? await store.updateSection(updated)
        await reload()
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

    func deleteSelected() async {
        let list = filtered()
        guard list.indices.contains(selection) else { return }
        await delete(list[selection])
    }

    private func cleaned(_ title: String?) -> String? {
        let t = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (t?.isEmpty == false) ? t : nil
    }

    /// Set just the custom title (any kind, including images/files).
    func setTitle(_ item: ClipItem, _ title: String?) async {
        var updated = item
        updated.title = cleaned(title)
        try? await store.update(updated)
        await reload()
    }

    /// Edit body text (title preserved); recomputes the content hash.
    func updateText(_ item: ClipItem, newText: String) async {
        var updated = item
        updated.textPlain = newText
        updated.rtfData = nil
        updated.htmlString = nil
        updated.contentHash = ContentHasher.hash(kind: item.kind, primary: Data(newText.utf8))
        try? await store.update(updated)
        await reload()
    }
}
