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
        // Pinned first (in manual pinOrder), then most-recently-used.
        items = all.sorted { a, b in
            if a.isPinned != b.isPinned { return a.isPinned }
            if a.isPinned && b.isPinned { return a.pinOrder < b.pinOrder }
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

    /// Pinned cards in slot order. The slot a card occupies (its ⌘-number) is its
    /// rank here — stable across every section view, never a position in the
    /// current filter.
    var pinnedSlots: [ClipItem] { items.filter(\.isPinned).sorted { $0.pinOrder < $1.pinOrder } }

    /// Number of assignable quick-slots (capped at 9, the ⌘-key range).
    var slotCount: Int { min(pinnedSlots.count, 9) }

    /// The quick-paste slot (1–9) a card occupies, or nil if it isn't pinned /
    /// is beyond slot 9. Same value in All and in any section.
    func slot(for item: ClipItem) -> Int? {
        guard item.isPinned, let r = pinnedSlots.firstIndex(where: { $0.id == item.id }), r < 9
        else { return nil }
        return r + 1
    }

    /// ⌘N pastes the pinned card in slot N — globally, regardless of the current
    /// section filter, so the key always matches the displayed number.
    func pasteIndex(_ i: Int) {
        let pinned = pinnedSlots
        guard i >= 1, pinned.indices.contains(i - 1) else { return }
        onPaste(pinned[i - 1], false)
    }

    func togglePin(_ item: ClipItem) async {
        var updated = item
        updated.isPinned.toggle()
        if updated.isPinned {
            updated.pinOrder = (items.filter(\.isPinned).map(\.pinOrder).max() ?? -1) + 1
            updated.expiresAt = nil
        }
        try? await store.update(updated)
        await reload()
    }

    /// Assign a card to quick-paste slot `slot` (1-based). A quick-slot is a pin,
    /// so this pins the card and places it at pinned-rank `slot`, insert-shifting
    /// the others. Picking a slot beyond the current pinned count clamps to the
    /// end (you can't be #5 if only 3 are pinned).
    func assignSlot(_ item: ClipItem, slot: Int) async {
        var pinned = items.filter(\.isPinned).sorted { $0.pinOrder < $1.pinOrder }
        pinned.removeAll { $0.id == item.id }
        var moved = item
        moved.isPinned = true
        moved.expiresAt = nil
        let rank = max(0, min(slot - 1, pinned.count))
        pinned.insert(moved, at: rank)
        for (i, p) in pinned.enumerated() {
            var u = p
            u.pinOrder = i
            u.isPinned = true
            u.expiresAt = nil
            try? await store.update(u)
        }
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
