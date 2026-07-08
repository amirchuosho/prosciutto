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
    /// Bumped each time the gallery (re)opens so the strip resets to the start —
    /// keeps the pinned tiles visible on the left even after a previous session
    /// scrolled far right. Kept separate from `selection` so navigating (which
    /// follows the selection and must scroll among many pinned tiles) isn't affected.
    @Published var homeScrollToken = 0
    /// True while a card title is being edited inline — the key monitor then
    /// leaves arrows/return/esc to the text field instead of navigating cards.
    @Published var isEditingTitle = false

    private let store: ClipStore
    private let sectionPalette = ["#F56B8C", "#5C8FFF", "#52CC85", "#FFAA5C", "#4ECDC8", "#C77DFF"]

    /// Set by AppEnvironment. Hides the panel, restores the previous app, then synthesizes paste.
    var onPaste: (ClipItem, Bool) -> Void = { _, _ in }
    /// Set by AppEnvironment. Dismisses the gallery without pasting.
    var onDismiss: () -> Void = {}
    /// Set by AppEnvironment. Opens the clip for editing — an image in Preview, a
    /// recording in QuickTime Player.
    var editMedia: (ClipItem) -> Void = { _ in }
    /// Set by AppEnvironment. Opens a recording in QuickTime and jumps to its Trim UI.
    var cropMedia: (ClipItem) -> Void = { _ in }

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

    /// Reorder custom sections: move the dragged section to just before the one it was
    /// dropped on, renumber `sortIndex`, and persist only the sections that moved. "All"
    /// and "Pinned" aren't sections, so they're untouched and stay fixed at the front.
    func moveSection(_ draggedID: UUID, before targetID: UUID) async {
        guard draggedID != targetID,
              let from = sections.firstIndex(where: { $0.id == draggedID }) else { return }
        var arr = sections
        let moved = arr.remove(at: from)
        let insertAt = arr.firstIndex(where: { $0.id == targetID }) ?? arr.count
        arr.insert(moved, at: insertAt)
        for (i, var s) in arr.enumerated() where s.sortIndex != i {
            s.sortIndex = i
            try? await store.updateSection(s)
        }
        await reload()
    }

    func moveSelection(_ delta: Int) {
        let count = filtered().count
        guard count > 0 else { return }
        selection = min(max(0, selection + delta), count - 1)
    }

    func moveToStart() { selection = 0 }
    func moveToEnd() { selection = max(0, filtered().count - 1) }

    /// Select the newest non-pinned clip (what the user most likely just copied),
    /// so each gallery open starts at the front instead of the last-paste spot.
    /// Falls back to the first item if everything is pinned / the list is empty.
    func selectNewestUnpinned() {
        let list = filtered()
        selection = list.firstIndex(where: { !$0.isPinned }) ?? 0
    }

    /// Land the gallery at its "home" position for the CURRENT filter: the newest
    /// unpinned clip, strip scrolled back to the start (pins visible). Called on open
    /// and on every visible-set change (section, type, search) so all four behave
    /// identically and the highlight can never point at a stale / out-of-range slot.
    func resetToHome() {
        selectNewestUnpinned()
        homeScrollToken += 1
    }

    func pasteSelected(asPlainText: Bool = false) {
        let list = filtered()
        guard list.indices.contains(selection) else { return }
        onPaste(list[selection], asPlainText)
    }

    /// Paste a specific clip (what the user clicked), by identity — never by the
    /// positional selection index, which can point at a different clip if the list
    /// reordered (e.g. the 0.3s poller captured something) between the card being
    /// laid out and the tap landing. Also syncs `selection` so keyboard nav resumes
    /// from the clicked card.
    func paste(_ item: ClipItem, asPlainText: Bool = false) {
        select(item)
        onPaste(item, asPlainText)
    }

    /// Move the selection to a specific clip by identity (e.g. when its title/body edit
    /// starts), so keyboard actions act on it rather than a stale selection elsewhere.
    func select(_ item: ClipItem) {
        if let i = filtered().firstIndex(where: { $0.id == item.id }) { selection = i }
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

    /// The latest known version of a clip (from the last reload), falling back to the
    /// passed-in copy. Edits apply their change onto THIS rather than a stale render-time
    /// snapshot, so a title edit and a body edit committed in turn don't clobber each
    /// other by each writing back the whole item with its own field only.
    private func current(_ item: ClipItem) -> ClipItem {
        items.first(where: { $0.id == item.id }) ?? item
    }

    /// Set just the custom title (any kind, including images/files).
    func setTitle(_ item: ClipItem, _ title: String?) async {
        var updated = current(item)
        updated.title = cleaned(title)
        try? await store.update(updated)
        await reload()
    }

    /// Mark a clip as just used: bump its recency so it sorts to the front of the
    /// unpinned clips (below pinned) on the next reload — a paste should bring the
    /// tile back to the front, like re-copying it would. Pinned clips keep their
    /// manual order, so this is a no-op for their position.
    func recordUse(_ item: ClipItem) async {
        var u = item
        u.lastUsedAt = Date()
        u.useCount += 1
        try? await store.update(u)
        await reload()
    }

    /// Edit body text (title preserved); recomputes the content hash.
    func updateText(_ item: ClipItem, newText: String) async {
        var updated = current(item)
        updated.textPlain = newText
        updated.rtfData = nil
        updated.htmlString = nil
        updated.contentHash = ContentHasher.hash(kind: item.kind, primary: Data(newText.utf8))
        try? await store.update(updated)
        await reload()
    }
}
