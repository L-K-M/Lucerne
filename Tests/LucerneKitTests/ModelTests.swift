import XCTest
@testable import LucerneKit

final class ModelTests: XCTestCase {

    func testDocumentRoundTripsThroughJSON() throws {
        let original = DefaultDocuments.sampleLetter()
        let data = try DocumentCoding.encode(original)
        let restored = try DocumentCoding.decode(data)
        XCTAssertEqual(original, restored)
    }

    func testPlacedObjectAppliesDefaultsForMissingFields() throws {
        // A minimal object: only id + page + frame. wrap/standoff/z/anchor/type
        // should fall back to their defaults.
        let json = """
        { "id": "x", "page": 0, "frame": { "x": 10, "y": 20, "width": 30, "height": 40 } }
        """.data(using: .utf8)!
        let object = try JSONDecoder().decode(PlacedObject.self, from: json)
        XCTAssertEqual(object.type, "image")
        XCTAssertEqual(object.anchorMode, .page)
        XCTAssertEqual(object.wrapMode, .rectangular)
        XCTAssertEqual(object.standoff, 12)
        XCTAssertEqual(object.z, 0)
        XCTAssertEqual(object.frame, RectModel(x: 10, y: 20, width: 30, height: 40))
    }

    func testContentSizeSubtractsMargins() {
        let page = PageConfig.a4
        let content = page.contentSize
        XCTAssertEqual(content.width, page.width - 144, accuracy: 0.001)   // 72 each side
        XCTAssertEqual(content.height, page.height - 144, accuracy: 0.001)
    }

    func testResolvedStyleFallsBackToBody() {
        let model = DefaultDocuments.empty()
        XCTAssertEqual(model.resolvedStyle(for: "nonexistent").name, "Body")
        XCTAssertEqual(model.resolvedStyle(for: "heading1").name, "Heading 1")
    }
}

final class GeometryTests: XCTestCase {

    func testInsetExpandsWithNegativeAmount() {
        let r = RectModel(x: 10, y: 10, width: 20, height: 20)
        let expanded = r.insetBy(-5)   // standoff-style outward inflation
        XCTAssertEqual(expanded, RectModel(x: 5, y: 5, width: 30, height: 30))
    }

    func testIntersection() {
        let a = RectModel(x: 0, y: 0, width: 10, height: 10)
        let b = RectModel(x: 5, y: 5, width: 10, height: 10)
        XCTAssertEqual(a.intersection(b), RectModel(x: 5, y: 5, width: 5, height: 5))
        XCTAssertTrue(a.intersects(b))

        let c = RectModel(x: 100, y: 100, width: 1, height: 1)
        XCTAssertNil(a.intersection(c))
        XCTAssertFalse(a.intersects(c))
    }
}

final class MarkdownExportTests: XCTestCase {

    func testHeadingsListsAndQuotes() {
        let model = LucerneDocumentModel(
            page: .a4,
            styles: DefaultDocuments.defaultStyles(),
            body: [
                Paragraph(id: "1", style: "heading1", runs: [Run(text: "Title")]),
                Paragraph(id: "2", style: "body", runs: [Run(text: "A plain sentence.")]),
                Paragraph(id: "3", style: "listItem", runs: [Run(text: "First item")]),
                Paragraph(id: "4", style: "quote", runs: [Run(text: "Quoted line")]),
            ],
            objects: [])
        let md = MarkdownExporter.export(model)
        XCTAssertTrue(md.contains("# Title"))
        XCTAssertTrue(md.contains("A plain sentence."))
        XCTAssertTrue(md.contains("- First item"))
        XCTAssertTrue(md.contains("> Quoted line"))
    }

    func testInlineBoldItalicMapping() {
        let model = LucerneDocumentModel(
            page: .a4,
            styles: DefaultDocuments.defaultStyles(),
            body: [Paragraph(id: "1", style: "body", runs: [
                Run(text: "normal "),
                Run(text: "bold", bold: true),
                Run(text: " and "),
                Run(text: "italic", italic: true),
                Run(text: " and "),
                Run(text: "both", bold: true, italic: true),
            ])],
            objects: [])
        let md = MarkdownExporter.export(model)
        XCTAssertTrue(md.contains("**bold**"), md)
        XCTAssertTrue(md.contains("*italic*"), md)
        XCTAssertTrue(md.contains("***both***"), md)
    }

    func testEmphasisMarkersDoNotHugWhitespace() {
        // A run that is "wonderful " (trailing space) marked italic must export as
        // "*wonderful* " — the space outside the markers — or it won't render.
        let model = LucerneDocumentModel(
            page: .a4,
            styles: DefaultDocuments.defaultStyles(),
            body: [Paragraph(id: "1", style: "body", runs: [
                Run(text: "a "),
                Run(text: "wonderful ", italic: true),
                Run(text: "day"),
            ])],
            objects: [])
        let md = MarkdownExporter.export(model)
        XCTAssertTrue(md.contains("*wonderful* "), md)
        XCTAssertFalse(md.contains("*wonderful *"), md)
    }

    func testImagesEmittedAsLinks() {
        let model = DefaultDocuments.sampleLetter()
        let md = MarkdownExporter.export(model)
        XCTAssertTrue(md.contains("![lake](images/lake.png)"), md)
    }
}
