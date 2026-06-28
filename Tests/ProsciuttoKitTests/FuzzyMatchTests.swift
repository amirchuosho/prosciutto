import XCTest
@testable import ProsciuttoKit

final class FuzzyMatchTests: XCTestCase {
    func testSubsequenceMatches() {
        XCTAssertNotNil(FuzzyMatch.score("prsc", "prosciutto"))
        XCTAssertNotNil(FuzzyMatch.score("clip", "Clipboard Manager"))
    }
    func testNonSubsequenceFails() {
        XCTAssertNil(FuzzyMatch.score("xyz", "prosciutto"))
        XCTAssertNil(FuzzyMatch.score("ppp", "prosciutto"))
    }
    func testEmptyNeedleScoresZero() {
        XCTAssertEqual(FuzzyMatch.score("", "anything"), 0)
    }
    func testContiguousScoresHigher() {
        let contiguous = FuzzyMatch.score("pros", "prosciutto")!
        let scattered = FuzzyMatch.score("psct", "prosciutto")!
        XCTAssertGreaterThan(contiguous, scattered)
    }
}
