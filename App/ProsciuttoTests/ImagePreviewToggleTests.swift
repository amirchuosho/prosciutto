import XCTest
import ProsciuttoKit
@testable import Prosciutto

@MainActor
final class ImagePreviewToggleTests: XCTestCase {
    private func clip(kind: ClipKind, hash: String) -> ClipItem {
        ClipItem(id: UUID(), createdAt: Date(), lastUsedAt: Date(), useCount: 0, kind: kind,
                 textPlain: kind == .text ? "hi" : nil,
                 imageData: kind == .image ? Data([0x1, 0x2, 0x3]) : nil,
                 contentHash: hash)
    }

    private func makeVM(_ items: [ClipItem]) -> GalleryViewModel {
        let vm = GalleryViewModel(store: CoreDataClipStore(inMemory: true))
        vm.items = items          // filtered() with the default (.all, empty query) returns these as-is
        return vm
    }

    func testTogglePreviewOnImageSelectionSetsThenClears() {
        let img = clip(kind: .image, hash: "img")
        let vm = makeVM([img, clip(kind: .text, hash: "txt")])
        vm.selection = 0

        XCTAssertNil(vm.previewID)
        XCTAssertTrue(vm.togglePreview())
        XCTAssertEqual(vm.previewID, img.id)
        XCTAssertTrue(vm.togglePreview())
        XCTAssertNil(vm.previewID, "second toggle closes it")
    }

    func testTogglePreviewOnNonImageIsNoOp() {
        let vm = makeVM([clip(kind: .image, hash: "img"), clip(kind: .text, hash: "txt")])
        vm.selection = 1   // the text clip

        XCTAssertFalse(vm.togglePreview())
        XCTAssertNil(vm.previewID)
    }

    func testChangingSelectionClosesPreview() {
        let img = clip(kind: .image, hash: "img")
        let vm = makeVM([img, clip(kind: .text, hash: "txt")])
        vm.selection = 0
        XCTAssertTrue(vm.togglePreview())
        XCTAssertEqual(vm.previewID, img.id)

        vm.selection = 1   // moving the highlight off the card closes its preview
        XCTAssertNil(vm.previewID)
    }
}
