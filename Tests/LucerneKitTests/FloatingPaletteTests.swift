import AppKit
import RigiUI
import XCTest
@testable import LucerneKit

/// The floating palettes live in Rigi's palette panels now; the chooser
/// contract (open flag, visibility notification, tear-off hand-off) is the
/// adapter's job and must survive the move.
@MainActor
final class FloatingPaletteTests: XCTestCase {

    func testATearOffFloatsThePaletteAndClosingItRestoresTheChoosers() {
        _ = NSApplication.shared
        let palette = FloatingPalette.lists
        var notifications = 0
        let observer = NotificationCenter.default.addObserver(
            forName: FloatingPalette.visibilityDidChangeNotification, object: palette,
            queue: nil) { _ in notifications += 1 }
        defer {
            NotificationCenter.default.removeObserver(observer)
            palette.close()
        }

        let window = palette.windowForDetach(selecting: "none")
        // Prepared only: AppKit has not committed the detach yet.
        XCTAssertTrue(window is ClassicPaletteWindow)
        XCTAssertFalse(palette.isOpen)
        XCTAssertEqual(notifications, 0)

        palette.didDetach()
        XCTAssertTrue(palette.isOpen)
        XCTAssertTrue(palette.isShowingPanel)
        XCTAssertEqual(window.title, "Lists")
        XCTAssertEqual(notifications, 1)

        palette.close()
        XCTAssertFalse(palette.isOpen)
        XCTAssertFalse(window.isVisible)
        XCTAssertEqual(notifications, 2)
    }

    func testAnAbandonedTearOffLeavesNoPaletteOpen() {
        _ = NSApplication.shared
        let palette = FloatingPalette.typefaces

        let window = palette.windowForDetach(selecting: nil)
        palette.cancelDetach()

        XCTAssertFalse(palette.isOpen)
        XCTAssertFalse(palette.isShowingPanel)
        XCTAssertFalse(window.isVisible)
    }
}
