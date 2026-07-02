import XCTest
import AppKit
@testable import LucerneKit

// Guards for the model⇆attributed-string bridge's font-intent preservation and
// trailing-paragraph identity (reviews 1.3, 1.8, 1.37). These need AppKit's font
// system, so they run on the macOS CI runner.
final class TextBridgeIntentTests: XCTestCase {

    private func roundTrip(_ model: LucerneDocumentModel) -> [Paragraph] {
        let attributed = AttributedStringBuilder.attributedString(for: model)
        return AttributedStringReader.paragraphs(from: attributed, styles: model.styles)
    }

    // 1.3 — a run naming a font the machine doesn't have must keep that family name
    // on save, not be rewritten as the substitute (system) font.
    func testMissingFontFamilyIsPreservedOnRun() {
        let missing = "LucerneNoSuchFont-XYZ"
        let model = LucerneDocumentModel(
            page: .a4, styles: DefaultDocuments.defaultStyles(),
            body: [Paragraph(id: "p1", style: "body",
                             runs: [Run(text: "hello", font: missing)])],
            objects: [])

        let restored = roundTrip(model)
        XCTAssertEqual(restored.count, 1)
        let run = restored[0].runs.first { $0.text == "hello" }
        XCTAssertEqual(run?.font, missing,
                       "a missing family must round-trip as the requested name, not the substitute")
    }

    // 1.8 — a document ending in an empty Heading 1 paragraph must keep that role and
    // its id, instead of inheriting the preceding paragraph's style and a fresh id.
    func testTrailingEmptyParagraphKeepsRoleAndID() {
        let model = LucerneDocumentModel(
            page: .a4, styles: DefaultDocuments.defaultStyles(),
            body: [
                Paragraph(id: "p1", style: "body", runs: [Run(text: "Hello")]),
                Paragraph(id: "trailer-1", style: "heading1", runs: [Run(text: "")])
            ],
            objects: [])

        let restored = roundTrip(model)
        XCTAssertEqual(restored.count, 2)
        XCTAssertEqual(restored[0].style, "body", "the preceding paragraph is untouched")
        XCTAssertEqual(restored[1].plainText, "", "the trailing paragraph stays empty")
        XCTAssertEqual(restored[1].style, "heading1", "the trailing role must survive")
        XCTAssertEqual(restored[1].id, "trailer-1", "the trailing id must not churn")
    }

    // 1.37 — bold+italic on a real family must resolve to a face with *both* traits,
    // and survive the bridge round-trip as run overrides.
    func testBoldItalicResolvesAndRoundTrips() {
        let font = FontResolver.font(family: "Helvetica", size: 14, bold: true, italic: true)
        XCTAssertTrue(FontResolver.isBold(font), "resolved font should be bold")
        XCTAssertTrue(FontResolver.isItalic(font), "resolved font should be italic")

        let model = LucerneDocumentModel(
            page: .a4, styles: DefaultDocuments.defaultStyles(),
            body: [Paragraph(id: "p1", style: "body",
                             runs: [Run(text: "x", bold: true, italic: true)])],
            objects: [])
        let restored = roundTrip(model)
        let run = restored[0].runs.first { $0.text == "x" }
        XCTAssertEqual(run?.bold, true, "bold must survive the resolver round-trip")
        XCTAssertEqual(run?.italic, true, "italic must survive the resolver round-trip")
    }
}
