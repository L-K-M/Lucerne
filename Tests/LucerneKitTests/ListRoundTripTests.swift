import AppKit
import XCTest
@testable import LucerneKit

/// List membership survives the model → NSAttributedString → model round trip that
/// every save runs through, including nesting, the derived-indent strip, and a
/// trailing empty list item.
final class ListRoundTripTests: XCTestCase {

    private let styles = DefaultDocuments.defaultStyles()

    private func roundTrip(_ body: [Paragraph]) -> [Paragraph] {
        let model = LucerneDocumentModel(page: .a4, styles: styles, body: body, objects: [])
        let attributed = AttributedStringBuilder.attributedString(for: model)
        return AttributedStringReader.paragraphs(from: attributed, styles: styles)
    }

    func testBulletMembershipSurvives() {
        let list = ListItemModel(list: "L", ordered: false, marker: "square", level: 0)
        let out = roundTrip([
            Paragraph(id: "p1", style: "body", list: list, runs: [Run(text: "Item")]),
            Paragraph(id: "p2", style: "body", runs: [Run(text: "Plain")]),
        ])
        XCTAssertEqual(out.count, 2)
        XCTAssertEqual(out[0].list, list)
        XCTAssertNil(out[1].list)
    }

    func testOrderedNestingSurvives() {
        let level0 = ListItemModel(list: "L", ordered: true, marker: "decimal", level: 0)
        let level1 = ListItemModel(list: "L", ordered: true, marker: "decimal", level: 1)
        let out = roundTrip([
            Paragraph(id: "p1", style: "body", list: level0, runs: [Run(text: "One")]),
            Paragraph(id: "p2", style: "body", list: level1, runs: [Run(text: "Sub")]),
        ])
        XCTAssertEqual(out[0].list?.level, 0)
        XCTAssertEqual(out[1].list?.level, 1)
        XCTAssertEqual(out[1].list?.list, "L")
    }

    func testDerivedIndentIsNotRecorded() {
        // A list item's hanging indent is derived from its level, so it must not leak
        // into the model as a manual left/first-line indent override.
        let list = ListItemModel(list: "L", ordered: false, marker: "disc", level: 2)
        let out = roundTrip([
            Paragraph(id: "p1", style: "body", list: list, runs: [Run(text: "Deep")]),
        ])
        XCTAssertEqual(out[0].list?.level, 2)
        XCTAssertNil(out[0].indent?.left)
        XCTAssertNil(out[0].indent?.firstLine)
    }

    func testTrailingEmptyListItemSurvives() {
        let list = ListItemModel(list: "L", ordered: true, marker: "decimal", level: 0)
        let out = roundTrip([
            Paragraph(id: "p1", style: "body", list: list, runs: [Run(text: "First")]),
            Paragraph(id: "p2", style: "body", list: list, runs: [Run(text: "")]),
        ])
        XCTAssertEqual(out.count, 2)
        XCTAssertEqual(out[1].plainText, "")
        XCTAssertEqual(out[1].list, list)
    }

    func testNonListDocumentIsUnaffected() {
        let out = roundTrip([
            Paragraph(id: "p1", style: "body", runs: [Run(text: "Hello")]),
        ])
        XCTAssertNil(out[0].list)
    }

    /// The trailing-paragraph fallback (storage lacking the trailing keys) must not
    /// inherit the final newline's `.lucerneList` — that belongs to the *preceding*
    /// list item, so copying it would conjure a spurious extra list item.
    func testTrailingFallbackDoesNotInheritPrecedingList() throws {
        let encoded = try XCTUnwrap(ListItemCodec.encode(
            ListItemModel(list: "L", ordered: false, marker: "disc")))
        // A bullet paragraph whose terminating newline carries the bullet's membership
        // but NO trailing-paragraph keys (as non-builder storage might).
        let attrs: [NSAttributedString.Key: Any] = [
            .lucerneStyleRole: "body", .lucerneParagraphID: "p1", .lucerneList: encoded,
        ]
        let attributed = NSMutableAttributedString(string: "Item", attributes: attrs)
        attributed.append(NSAttributedString(string: "\n", attributes: attrs))

        let out = AttributedStringReader.paragraphs(from: attributed, styles: styles)
        XCTAssertEqual(out.count, 2)
        XCTAssertEqual(out[0].list?.list, "L")   // the real bullet survives
        XCTAssertNil(out[1].list)                // the trailing empty paragraph is NOT a bullet
    }
}
