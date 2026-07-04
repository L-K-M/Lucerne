import AppKit
import XCTest
@testable import LucerneKit

/// The toolbar List chooser's item table and label mapping — pure static helpers,
/// so they lock the wiring (each row's id must be a marker the editor understands)
/// without needing a live view.
final class ListToolbarTests: XCTestCase {

    func testListItemsCoverEveryMarkerPlusNone() {
        let items = FloatingPalette.listItems()
        let ids = items.filter { !$0.isSeparator }.map(\.id)
        XCTAssertEqual(ids.first, "none")
        for style in ListMarkers.unorderedStyles {
            XCTAssertTrue(ids.contains(style.marker), "missing bullet row: \(style.marker)")
        }
        for style in ListMarkers.orderedStyles {
            XCTAssertTrue(ids.contains(style.marker), "missing number row: \(style.marker)")
        }
        // Two section captions (Bullets / Numbers).
        XCTAssertEqual(items.filter(\.isSeparator).count, 2)
    }

    func testListStyleTitleIsConcise() {
        XCTAssertEqual(ToolbarView.listStyleTitle(for: "none"), "List")   // names the control at rest
        XCTAssertEqual(ToolbarView.listStyleTitle(for: "disc"), "Bulleted")
        XCTAssertEqual(ToolbarView.listStyleTitle(for: "square"), "Bulleted")
        XCTAssertEqual(ToolbarView.listStyleTitle(for: "decimal"), "Numbered")
        XCTAssertEqual(ToolbarView.listStyleTitle(for: "upper-roman"), "Numbered")
    }
}
