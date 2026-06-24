import XCTest
@testable import ProsciuttoKit

final class ContentHasherTests: XCTestCase {
    func testSameContentSameHash() {
        let a = ContentHasher.hash(kind: .text, primary: Data("hello".utf8))
        let b = ContentHasher.hash(kind: .text, primary: Data("hello".utf8))
        XCTAssertEqual(a, b)
    }
    func testDifferentKindDifferentHash() {
        let a = ContentHasher.hash(kind: .text, primary: Data("hello".utf8))
        let b = ContentHasher.hash(kind: .code, primary: Data("hello".utf8))
        XCTAssertNotEqual(a, b)
    }
}
