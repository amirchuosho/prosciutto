import XCTest
@testable import Prosciutto

@MainActor
final class SearchFocusTests: XCTestCase {
    private func vm() -> GalleryViewModel { GalleryViewModel(store: CoreDataClipStore(inMemory: true)) }

    func testBeginSearchSeedsQueryAndRequestsFocus() {
        let m = vm()
        m.beginSearch(seed: "a")
        XCTAssertEqual(m.query.text, "a")
        XCTAssertEqual(m.wantsSearchFocus, true)
    }
    func testFocusSearchRaisesRequestWithoutSeeding() {
        let m = vm()
        m.focusSearch()
        XCTAssertEqual(m.wantsSearchFocus, true)
        XCTAssertEqual(m.query.text, "")   // focus only — never touches the query
    }
    func testResignSearchLowersRequest() {
        let m = vm()
        m.resignSearch()
        XCTAssertEqual(m.wantsSearchFocus, false)
    }
    // searchSeed classifier
    func testSeedLetter() { XCTAssertEqual(GalleryViewModel.searchSeed(chars: "a", keyCode: 0, hasModifier: false), "a") }
    func testSeedDigit()  { XCTAssertEqual(GalleryViewModel.searchSeed(chars: "5", keyCode: 23, hasModifier: false), "5") }
    func testSeedPunct()  { XCTAssertEqual(GalleryViewModel.searchSeed(chars: "/", keyCode: 44, hasModifier: false), "/") }
    func testSeedSpaceRejected()   { XCTAssertNil(GalleryViewModel.searchSeed(chars: " ", keyCode: 49, hasModifier: false)) }
    func testSeedArrowRejected()   { XCTAssertNil(GalleryViewModel.searchSeed(chars: "", keyCode: 123, hasModifier: false)) }
    func testSeedReturnRejected()  { XCTAssertNil(GalleryViewModel.searchSeed(chars: "\r", keyCode: 36, hasModifier: false)) }
    func testSeedModifierRejected(){ XCTAssertNil(GalleryViewModel.searchSeed(chars: "a", keyCode: 0, hasModifier: true)) }
    func testSeedFunctionKeyRejected() { XCTAssertNil(GalleryViewModel.searchSeed(chars: "\u{F704}", keyCode: 122, hasModifier: false)) }
}
