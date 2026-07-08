import XCTest
import AppKit
@testable import Prosciutto

/// The gallery strip must sit flush at the true bottom edge of its screen (over the
/// dock, like Paste), sized to its actual content — never anchored above the dock and
/// never a hardcoded height. On tiny screens the height clamps so it always fits.
final class GalleryPanelFrameTests: XCTestCase {

    /// Normal large screen: strip hugs the true bottom (screen frame, not visible
    /// frame), full width minus side margins, height == the measured content height.
    func testAnchorsToTrueScreenBottomWithContentHeight() {
        let screen = NSRect(x: 0, y: 0, width: 2560, height: 1440)
        let frame = GalleryPanel.panelFrame(inScreen: screen, contentHeight: 452, margin: 18)

        XCTAssertEqual(frame.minX, 18, "left margin off the screen's left edge")
        XCTAssertEqual(frame.minY, 18, "bottom margin off the TRUE bottom (y=0), not above the dock")
        XCTAssertEqual(frame.width, 2560 - 36, "full width minus both side margins")
        XCTAssertEqual(frame.height, 452, "height tracks the real content height, no magic number")
    }

    /// The screen's origin can be non-zero (secondary display, notch offsets). The
    /// strip must anchor to THAT screen's bottom, not global zero.
    func testRespectsScreenOrigin() {
        let screen = NSRect(x: -1440, y: -300, width: 1440, height: 900)
        let frame = GalleryPanel.panelFrame(inScreen: screen, contentHeight: 452, margin: 18)

        XCTAssertEqual(frame.minX, -1440 + 18)
        XCTAssertEqual(frame.minY, -300 + 18)
        XCTAssertEqual(frame.height, 452)
    }

    /// Tiny screen, content taller than it fits: height clamps so the panel never
    /// exceeds the screen, while staying anchored at the bottom margin.
    func testClampsHeightOnTinyScreen() {
        let screen = NSRect(x: 0, y: 0, width: 900, height: 400)
        let frame = GalleryPanel.panelFrame(inScreen: screen, contentHeight: 452, margin: 18)

        XCTAssertEqual(frame.minY, 18, "still anchored at the bottom margin")
        XCTAssertEqual(frame.height, 400 - 36, "clamped to fit within screen height minus top+bottom margin")
        XCTAssertLessThanOrEqual(frame.maxY, 400, "never spills past the top of the screen")
    }
}
