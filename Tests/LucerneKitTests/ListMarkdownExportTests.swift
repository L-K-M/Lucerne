import XCTest
@testable import LucerneKit

/// The Markdown exporter's list output: bullets, numbering, nesting, and coexistence
/// with other blocks.
final class ListMarkdownExportTests: XCTestCase {

    private func model(_ body: [Paragraph]) -> LucerneDocumentModel {
        LucerneDocumentModel(page: .a4, styles: DefaultDocuments.defaultStyles(), body: body, objects: [])
    }

    private func bullet(_ id: String, _ text: String, level: Int = 0) -> Paragraph {
        Paragraph(id: id, style: "body",
                  list: ListItemModel(list: "L", ordered: false, marker: "disc", level: level),
                  runs: [Run(text: text)])
    }

    private func numbered(_ id: String, _ text: String, level: Int = 0, start: Int? = nil) -> Paragraph {
        Paragraph(id: id, style: "body",
                  list: ListItemModel(list: "L", ordered: true, marker: "decimal", level: level, start: start),
                  runs: [Run(text: text)])
    }

    func testBulletList() {
        let md = MarkdownExporter.export(model([
            bullet("1", "Milk"), bullet("2", "Eggs"), bullet("3", "Bread"),
        ]))
        XCTAssertEqual(md, "- Milk\n- Eggs\n- Bread\n")
    }

    func testNumberedList() {
        let md = MarkdownExporter.export(model([
            numbered("1", "First"), numbered("2", "Second"), numbered("3", "Third"),
        ]))
        XCTAssertEqual(md, "1. First\n2. Second\n3. Third\n")
    }

    func testNumberedListHonoursStart() {
        let md = MarkdownExporter.export(model([
            numbered("1", "Five", start: 5), numbered("2", "Six"),
        ]))
        XCTAssertEqual(md, "5. Five\n6. Six\n")
    }

    func testNestedNumberedList() {
        let md = MarkdownExporter.export(model([
            numbered("1", "A", level: 0),
            numbered("2", "B", level: 1),
            numbered("3", "C", level: 1),
            numbered("4", "D", level: 0),
        ]))
        XCTAssertEqual(md, "1. A\n    1. B\n    2. C\n2. D\n")
    }

    func testListSitsBetweenOtherBlocks() {
        let md = MarkdownExporter.export(model([
            Paragraph(id: "h", style: "heading1", runs: [Run(text: "Groceries")]),
            bullet("1", "Milk"), bullet("2", "Eggs"),
            Paragraph(id: "p", style: "body", runs: [Run(text: "Thanks.")]),
        ]))
        XCTAssertEqual(md, "# Groceries\n\n- Milk\n- Eggs\n\nThanks.\n")
    }

    /// A paragraph with the legacy "li" role but no real list membership still exports
    /// as a bullet (backward compatibility with pre-list documents).
    func testLegacyListItemRoleStillExportsAsBullet() {
        let md = MarkdownExporter.export(model([
            Paragraph(id: "1", style: "listItem", runs: [Run(text: "Old bullet")]),
        ]))
        XCTAssertEqual(md, "- Old bullet\n")
    }
}
