import XCTest
import ProsciuttoKit
@testable import Prosciutto

@MainActor
final class AddNoteTests: XCTestCase {
    // Hold the store locally so tests can seed it directly (GalleryViewModel.store is private).
    private func makeVM() -> (GalleryViewModel, CoreDataClipStore) {
        let store = CoreDataClipStore(inMemory: true)
        return (GalleryViewModel(store: store), store)
    }

    func testAddNoteInsertsEmptyTextClipSelectedAndPending() async {
        let (vm, _) = makeVM()
        await vm.addNote()
        let note = try! XCTUnwrap(vm.items.first { $0.kind == .text })
        XCTAssertEqual(note.textPlain, "")
        XCTAssertEqual(vm.newNoteID, note.id)
        XCTAssertEqual(vm.selectedItem?.id, note.id)
    }

    func testAddNoteUnderCustomSectionSetsSectionID() async throws {
        let (vm, store) = makeVM()
        let s = try await store.createSection(name: "Notes", colorHex: "#abc")
        vm.sectionFilter = .section(s.id)
        await vm.addNote()
        let note = try XCTUnwrap(vm.items.first { $0.kind == .text })
        XCTAssertEqual(note.sectionID, s.id)
    }

    func testAddNoteUnderPinnedSwitchesToAllAndNilSection() async {
        let (vm, _) = makeVM()
        vm.sectionFilter = .pinned
        await vm.addNote()
        let note = try! XCTUnwrap(vm.items.first { $0.kind == .text })
        XCTAssertNil(note.sectionID)
        XCTAssertEqual(vm.sectionFilter, .all)
    }

    func testAddNoteClearsTypeFilter() async {
        let (vm, _) = makeVM()
        vm.query.kinds = [.link]
        await vm.addNote()
        XCTAssertTrue(vm.query.kinds.isEmpty)
    }

    func testCommitBlankNewNoteDeletesIt() async {
        let (vm, _) = makeVM()
        await vm.addNote()
        let note = try! XCTUnwrap(vm.items.first { $0.kind == .text })
        await vm.commitBody(note, text: "   ")
        XCTAssertFalse(vm.items.contains { $0.id == note.id }, "blank new note discarded")
    }

    func testCommitTypedNewNoteKeepsIt() async {
        let (vm, _) = makeVM()
        await vm.addNote()
        let note = try! XCTUnwrap(vm.items.first { $0.kind == .text })
        await vm.commitBody(note, text: "hello")
        XCTAssertEqual(vm.items.first { $0.id == note.id }?.textPlain, "hello")
    }

    func testCommitBlankOnExistingClipDoesNotDelete() async throws {
        let (vm, store) = makeVM()
        let clip = ClipItem(id: UUID(), createdAt: Date(), lastUsedAt: Date(), useCount: 1,
                            kind: .text, textPlain: "keep me", contentHash: "h")
        try await store.upsert(clip)
        await vm.reload()
        await vm.commitBody(clip, text: "")   // not a pending new note
        XCTAssertTrue(vm.items.contains { $0.id == clip.id }, "existing clip not auto-deleted")
    }
}
