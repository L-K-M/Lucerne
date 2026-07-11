import XCTest
@testable import LucerneKit

/// Edge cases for the Markdown escape hatch: GFM table export (spec §8.7) and
/// block-level escaping of prose that would otherwise start a block construct
/// (review 1.27 / spec §8.8).
final class MarkdownExportEdgeTests: XCTestCase {

    // MARK: - Helpers

    private func makeModel(body: [Paragraph]) -> LucerneDocumentModel {
        LucerneDocumentModel(page: .a4,
                             styles: DefaultDocuments.defaultStyles(),
                             body: body,
                             objects: [])
    }

    private func makeModel(imageSource: String) -> LucerneDocumentModel {
        LucerneDocumentModel(page: .a4,
                             styles: DefaultDocuments.defaultStyles(),
                             body: [],
                             objects: [PlacedObject(id: "image", src: imageSource)])
    }

    private func cellParagraph(_ text: String, table: String, row: Int, column: Int) -> Paragraph {
        Paragraph(id: "\(table)-\(row)-\(column)", style: "body",
                  cell: TableCellModel(table: table, row: row, column: column),
                  runs: [Run(text: text)])
    }

    // MARK: - Tables

    func testTwoByTwoTableExportsAsGFMPipeTable() {
        let model = makeModel(body: [
            cellParagraph("A", table: "t1", row: 0, column: 0),
            cellParagraph("B", table: "t1", row: 0, column: 1),
            cellParagraph("C", table: "t1", row: 1, column: 0),
            cellParagraph("D", table: "t1", row: 1, column: 1),
        ])
        let md = MarkdownExporter.export(model)
        XCTAssertTrue(md.contains("| A | B |"), md)   // header row (row 0)
        XCTAssertTrue(md.contains("| --- | --- |"), md)   // GFM delimiter row
        XCTAssertTrue(md.contains("| C | D |"), md)   // body row
    }

    func testPipeInsideCellIsEscaped() {
        let model = makeModel(body: [
            cellParagraph("a|b", table: "t2", row: 0, column: 0),
            cellParagraph("x", table: "t2", row: 0, column: 1),
        ])
        let md = MarkdownExporter.export(model)
        XCTAssertTrue(md.contains("a\\|b"), md)
    }

    // MARK: - Block-level escaping

    func testPlainParagraphEscapesLeadingHash() {
        let md = MarkdownExporter.export(makeModel(body: [
            Paragraph(id: "1", style: "body", runs: [Run(text: "# not a heading")]),
        ]))
        XCTAssertTrue(md.hasPrefix("\\# not a heading"), md)
    }

    func testPlainParagraphEscapesOtherBlockMarkers() {
        let cases: [(String, String)] = [
            ("> not a quote", "\\> not a quote"),
            ("- not a bullet", "\\- not a bullet"),
            ("1. not a list", "1\\. not a list"),
        ]
        for (input, expected) in cases {
            let md = MarkdownExporter.export(makeModel(body: [
                Paragraph(id: "1", style: "body", runs: [Run(text: input)]),
            ]))
            XCTAssertTrue(md.hasPrefix(expected), "\(input) → \(md)")
        }
    }

    func testStyleRolesStillEmitUnescapedPrefixes() {
        let model = LucerneDocumentModel(
            page: .a4,
            styles: DefaultDocuments.defaultStyles(),
            body: [
                Paragraph(id: "1", style: "heading1", runs: [Run(text: "Real Heading")]),
                Paragraph(id: "2", style: "quote", runs: [Run(text: "Real Quote")]),
                Paragraph(id: "3", style: "listItem", runs: [Run(text: "Real Item")]),
            ],
            objects: [])
        let md = MarkdownExporter.export(model)
        XCTAssertTrue(md.contains("# Real Heading"), md)
        XCTAssertFalse(md.contains("\\# Real Heading"), md)   // role prefixes are not escaped
        XCTAssertTrue(md.contains("> Real Quote"), md)
        XCTAssertFalse(md.contains("\\> Real Quote"), md)
        XCTAssertTrue(md.contains("- Real Item"), md)
    }

    // MARK: - Image references

    func testImageAltTextAndDestinationEscapeUnsafeFilenameCharacters() {
        let source = "images/na]me)\\ snow 東京\nline.png"
        let md = MarkdownExporter.export(makeModel(imageSource: source))

        XCTAssertEqual(
            md,
            "![na\\]me)\\\\ snow 東京 line](images/na%5Dme%29%5C%20snow%20%E6%9D%B1%E4%BA%AC%0Aline.png)\n"
        )
    }
}
