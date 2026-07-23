import XCTest
@testable import Prosciutto

final class ScreenshotWatcherTests: XCTestCase {
    func testShouldProcessRespectsStartTimeAndProcessedSet() {
        let start = Date()
        let older = start.addingTimeInterval(-5)
        let newer = start.addingTimeInterval(5)
        // created before the watcher started → ignore (backlog)
        XCTAssertFalse(ScreenshotWatcher.shouldProcess(path: "/a.png", created: older, startedAt: start, processed: []))
        // created after start, not seen → process
        XCTAssertTrue(ScreenshotWatcher.shouldProcess(path: "/a.png", created: newer, startedAt: start, processed: []))
        // already processed → ignore
        XCTAssertFalse(ScreenshotWatcher.shouldProcess(path: "/a.png", created: newer, startedAt: start, processed: ["/a.png"]))
    }

    func testFreshWatcherIsNotArmed() {
        XCTAssertFalse(ScreenshotWatcher().isArmed)
    }

    func testRetryArmIsNoOpWhenDisabled() {
        let w = ScreenshotWatcher()   // both copy flags default off
        w.retryArmIfNeeded()          // disabled → must not arm
        XCTAssertFalse(w.isArmed)
    }
}
