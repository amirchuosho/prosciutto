import XCTest
@testable import ProsciuttoKit

final class SmokeTests: XCTestCase {
    func testVersion() { XCTAssertEqual(ProsciuttoKit.version, "0.1.0") }
}
