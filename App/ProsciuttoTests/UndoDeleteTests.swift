import XCTest
import ProsciuttoKit
@testable import Prosciutto

@MainActor
final class UndoDeleteTests: XCTestCase {

    /// ⌘Z restores the clip that delete removed.
    func testUndoRestoresDeletedClip() async throws {
        let store = CoreDataClipStore(inMemory: true)
        let item = ClipItem.make(from: .init(plainText: "restore me"), kind: .text,
                                 now: Date(timeIntervalSince1970: 0), ttl: 60)
        try await store.upsert(item)
        let vm = GalleryViewModel(store: store)
        await vm.reload()
        XCTAssertTrue(vm.items.contains { $0.id == item.id })

        await vm.delete(item)
        XCTAssertFalse(vm.items.contains { $0.id == item.id }, "delete removed it")

        await vm.undoDelete()
        XCTAssertTrue(vm.items.contains { $0.id == item.id }, "undo restored it")
    }

    /// Undo with nothing deleted is a harmless no-op.
    func testUndoWithEmptyStackIsNoOp() async throws {
        let store = CoreDataClipStore(inMemory: true)
        let vm = GalleryViewModel(store: store)
        await vm.reload()
        await vm.undoDelete()
        XCTAssertTrue(vm.items.isEmpty)
    }

    /// Repeated ⌘Z restores deletes newest-first (LIFO).
    func testUndoIsLIFO() async throws {
        let store = CoreDataClipStore(inMemory: true)
        let now = Date(timeIntervalSince1970: 0)
        let a = ClipItem.make(from: .init(plainText: "a"), kind: .text, now: now, ttl: 60)
        let b = ClipItem.make(from: .init(plainText: "b"), kind: .text, now: now, ttl: 60)
        try await store.upsert(a); try await store.upsert(b)
        let vm = GalleryViewModel(store: store)
        await vm.reload()

        await vm.delete(a)
        await vm.delete(b)
        await vm.undoDelete()   // restores b first
        XCTAssertTrue(vm.items.contains { $0.id == b.id })
        XCTAssertFalse(vm.items.contains { $0.id == a.id })
        await vm.undoDelete()   // then a
        XCTAssertTrue(vm.items.contains { $0.id == a.id })
    }
}
