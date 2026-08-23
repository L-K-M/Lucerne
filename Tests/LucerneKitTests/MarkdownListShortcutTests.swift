import XCTest
@testable import LucerneKit

/// Markdown list-shortcut recognition ("- ", "1. ", "3) " ... start a list).
/// The recognizer lives on EditorController (AppKit), so these run in the
/// macOS test target; the pure numbering engine is covered in LucerneCoreTests.
final class MarkdownListShortcutTests: XCTestCase {


    func testBulletMarkersStartUnorderedLists() {
        for marker in ["-", "*", "+"] {
            let spec = EditorController.markdownListShortcut(forMarker: marker)
            XCTAssertEqual(spec?.ordered, false, "\(marker)")
            XCTAssertEqual(spec?.marker, "disc")
            XCTAssertNil(spec?.start)
        }
    }

    func testNumberMarkersStartOrderedLists() {
        XCTAssertEqual(EditorController.markdownListShortcut(forMarker: "1.")?.ordered, true)
        XCTAssertNil(EditorController.markdownListShortcut(forMarker: "1.")?.start)   // 1 is the default
        XCTAssertEqual(EditorController.markdownListShortcut(forMarker: "3.")?.start, 3)
        XCTAssertEqual(EditorController.markdownListShortcut(forMarker: "10)")?.start, 10)
    }

    func testNonListMarkersAreRejected() {
        for marker in ["#", "##", ">", "1", "a.", ".", ")", "", "1a."] {
            XCTAssertNil(EditorController.markdownListShortcut(forMarker: marker), "\(marker)")
        }
    }
}
