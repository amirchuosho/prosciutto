import XCTest
@testable import ProsciuttoKit

final class VersionComparatorTests: XCTestCase {
    func testNewerPatch() { XCTAssertTrue(VersionComparator.isNewer("v0.5.0", than: "0.4.3")) }
    func testEqualIsNotNewer() { XCTAssertFalse(VersionComparator.isNewer("0.4.3", than: "0.4.3")) }
    func testOlderIsNotNewer() { XCTAssertFalse(VersionComparator.isNewer("0.4.2", than: "0.4.3")) }
    func testMissingComponentsEqual() { XCTAssertFalse(VersionComparator.isNewer("v1.0", than: "1.0.0")) }
    func testMinorBump() { XCTAssertTrue(VersionComparator.isNewer("1.2.0", than: "1.1.9")) }
    func testDoubleDigitComponent() { XCTAssertTrue(VersionComparator.isNewer("0.10.0", than: "0.9.0")) }
    func testUnparseableIsNotNewer() { XCTAssertFalse(VersionComparator.isNewer("abc", than: "0.4.3")) }
    func testVPrefixOnBoth() { XCTAssertTrue(VersionComparator.isNewer("V2.0.0", than: "v1.9.9")) }
}
