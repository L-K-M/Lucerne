import XCTest
@testable import LucerneKit

/// The Markdown block-shortcut mapping (typing "## " → the Heading 2 style). The
/// caret/undo mechanics live in AppKit (PageTextView + EditorController), but the
/// marker → style-role resolution is pure and stylesheet-driven, so it's tested
/// here without a GUI.
final class MarkdownShortcutTests: XCTestCase {

    /// A stylesheet exercising the handled hints — plus one the shortcuts ignore
    /// (`li`) and one style whose hint has no marker (`p`).
    private let styles: [String: ParagraphStyleDef] = [
        "body": ParagraphStyleDef(name: "Body", order: 0, markdown: "p"),
        "h1key": ParagraphStyleDef(name: "Heading 1", order: 1, markdown: "h1"),
        "h2key": ParagraphStyleDef(name: "Heading 2", order: 2, markdown: "h2"),
        "quote": ParagraphStyleDef(name: "Block Quote", order: 3, markdown: "blockquote"),
        "list": ParagraphStyleDef(name: "List Item", order: 4, markdown: "li"),
    ]

    func testHeadingAndQuoteMarkersResolveToTheirStyle() {
        XCTAssertEqual(EditorController.markdownShortcutRole(forMarker: "#", in: styles), "h1key")
        XCTAssertEqual(EditorController.markdownShortcutRole(forMarker: "##", in: styles), "h2key")
        XCTAssertEqual(EditorController.markdownShortcutRole(forMarker: ">", in: styles), "quote")
    }

    func testMarkerWithoutAStyleInTheDocumentIsIgnored() {
        // "###" maps to h3, which this stylesheet doesn't define — so it stays literal.
        XCTAssertNil(EditorController.markdownShortcutRole(forMarker: "###", in: styles))
        XCTAssertNil(EditorController.markdownShortcutRole(forMarker: "####", in: styles))
    }

    func testUnhandledMarkersAreIgnored() {
        // List markers are intentionally out of scope (no real lists yet), and
        // arbitrary text is never a marker.
        XCTAssertNil(EditorController.markdownShortcutRole(forMarker: "-", in: styles))
        XCTAssertNil(EditorController.markdownShortcutRole(forMarker: "*", in: styles))
        XCTAssertNil(EditorController.markdownShortcutRole(forMarker: "1.", in: styles))
        XCTAssertNil(EditorController.markdownShortcutRole(forMarker: "Hello", in: styles))
        XCTAssertNil(EditorController.markdownShortcutRole(forMarker: "", in: styles))
    }

    func testResolutionFollowsDocumentListOrder() {
        // Two styles share the h2 hint; the first in list order wins, deterministically.
        var twoHeadingTwos = styles
        twoHeadingTwos["alth2"] = ParagraphStyleDef(name: "Subhead", order: 9, markdown: "h2")
        XCTAssertEqual(EditorController.markdownShortcutRole(forMarker: "##", in: twoHeadingTwos), "h2key")
    }
}
