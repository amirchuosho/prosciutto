import XCTest
@testable import ProsciuttoKit

final class ExclusionPolicyTests: XCTestCase {
    let policy = ExclusionPolicy(blockedBundleIDs: ["com.agilebits.onepassword7"])

    func testConcealedSkipped() {
        let s = PasteboardSnapshot(plainText: "secret", markerTypes: [ExclusionPolicy.concealedType])
        XCTAssertFalse(policy.shouldCapture(s))
    }
    func testTransientSkipped() {
        let s = PasteboardSnapshot(plainText: "x", markerTypes: [ExclusionPolicy.transientType])
        XCTAssertFalse(policy.shouldCapture(s))
    }
    func testBlockedAppSkipped() {
        let s = PasteboardSnapshot(plainText: "x", sourceAppBundleID: "com.agilebits.onepassword7")
        XCTAssertFalse(policy.shouldCapture(s))
    }
    func testNormalCaptured() {
        XCTAssertTrue(policy.shouldCapture(PasteboardSnapshot(plainText: "hi", sourceAppBundleID: "com.apple.Safari")))
    }
}
