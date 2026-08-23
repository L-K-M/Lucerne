import Foundation
import XCTest
@testable import LucerneCore

/// The shared `.luce` conformance corpus (docs/ubuntu-port.md §3): every fixture
/// under Tests/Fixtures must open and round-trip through the reference
/// reader/writer without losing modelled state, and the invalid/ fixtures must
/// be rejected for the reason their name states. The Qt port's test suite
/// (linux/tests) walks the SAME directory — a fixture added to the corpus is
/// exercised against both implementations, which is what keeps the two apps
/// file-level compatible. Regenerate with Scripts/make-fixtures.py.
final class SpecFixtureTests: XCTestCase {

    private static let fixturesURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // LucerneCoreTests/
        .deletingLastPathComponent()   // Tests/
        .appendingPathComponent("Fixtures", isDirectory: true)

    private func fixture(_ name: String) throws -> Data {
        try Data(contentsOf: Self.fixturesURL.appendingPathComponent(name))
    }

    private static let validFixtures = [
        "minimal.luce", "kitchen-sink.luce", "lists.luce",
        "tables.luce", "history.luce", "deflate.luce",
    ]

    /// Guards against the corpus and this test drifting apart: every .luce at
    /// the fixture root must be in `validFixtures` (invalid ones live under
    /// invalid/), so adding a fixture without wiring it up here fails loudly.
    func testCorpusIsFullyEnumerated() throws {
        let onDisk = try FileManager.default
            .contentsOfDirectory(atPath: Self.fixturesURL.path)
            .filter { $0.hasSuffix(".luce") }
            .sorted()
        XCTAssertEqual(onDisk, Self.validFixtures.sorted())
    }

    // MARK: - Every valid fixture opens and round-trips

    func testValidFixturesOpenAndRoundTrip() throws {
        for name in Self.validFixtures {
            let contents = try LuceArchive.read(fixture(name))

            // JSON round-trip: encode with the reference writer, decode again,
            // and the models must be identical (no state lost in our own coding).
            let reencoded = try DocumentCoding.encode(contents.model)
            let redecoded = try DocumentCoding.decode(reencoded)
            XCTAssertEqual(redecoded, contents.model, "JSON round-trip drifted for \(name)")

            // Archive round-trip. The reference writer refuses dangling image
            // references (stricter than the read side, which must tolerate
            // them), so supply a stand-in payload for any missing source.
            var images = contents.images
            for object in contents.model.objects where object.type == "image" {
                guard let src = object.src else { continue }
                if images[src] == nil { images[src] = Data([0x89, 0x50, 0x4e, 0x47]) }
            }
            let rewritten = try LuceArchive.write(model: contents.model, images: images,
                                                  history: contents.history)
            let reread = try LuceArchive.read(rewritten)
            XCTAssertEqual(reread.model, contents.model, "archive round-trip drifted for \(name)")
            XCTAssertEqual(reread.history, contents.history.sorted { $0.timestamp < $1.timestamp },
                           "history did not survive the archive round-trip for \(name)")
        }
    }

    // MARK: - Spot checks per fixture

    func testKitchenSinkDecodesEveryModelledFeature() throws {
        let contents = try LuceArchive.read(fixture("kitchen-sink.luce"))
        let model = contents.model

        // Page: custom size is authoritative; fold marks on.
        XCTAssertEqual(model.page.size, "custom")
        XCTAssertEqual(model.page.width, 500)
        XCTAssertEqual(model.page.height, 700)
        XCTAssertEqual(model.page.margins.right, 40)
        XCTAssertEqual(model.page.foldMarks, true)

        // Furniture + numbering offset.
        XCTAssertEqual(model.header?.left, "{title}")
        XCTAssertEqual(model.footer?.center, "Page {page} of {pages}")
        XCTAssertEqual(model.pageNumberStart, 2)

        // Style table: underline, negative first-line indent, 8-digit color.
        let fancy = try XCTUnwrap(model.styles["fancy"])
        XCTAssertEqual(fancy.underline, true)
        XCTAssertEqual(fancy.firstLineIndent, -10)
        XCTAssertEqual(fancy.color, "#8000FF80")

        // Paragraph overrides: all four tab-stop types survive in order.
        let p2 = try XCTUnwrap(model.body.first { $0.id == "p2" })
        XCTAssertEqual(p2.tabStops?.map(\.kind), [.left, .center, .right, .decimal])
        XCTAssertEqual(p2.align, "right")
        XCTAssertEqual(p2.indent?.firstLine, 18)
        XCTAssertEqual(p2.lineSpacing, 1.5)

        // Run overrides.
        XCTAssertEqual(p2.runs[1].italic, true)
        XCTAssertEqual(p2.runs[2].bold, true)
        XCTAssertEqual(p2.runs[3].font, "Courier")
        XCTAssertEqual(p2.runs[3].color, "#123456")

        // Unknown style role resolves through the body fallback.
        let p3 = try XCTUnwrap(model.body.first { $0.id == "p3" })
        XCTAssertEqual(model.resolvedStyle(for: p3.style).name, "Body")

        // Empty runs array is tolerated (spec §6.1).
        XCTAssertEqual(model.body.first { $0.id == "p4" }?.runs.isEmpty, true)

        XCTAssertEqual(model.body.first { $0.id == "p5" }?.pageBreakBefore, true)

        // Objects: defaults for omitted members (spec Appendix C).
        let img2 = try XCTUnwrap(model.objects.first { $0.id == "img2" })
        XCTAssertEqual(img2.type, "image")
        XCTAssertEqual(img2.anchorMode, .page)
        XCTAssertEqual(img2.standoff, 12)
        XCTAssertEqual(img2.wrapMode, .none)

        // Paragraph-anchored object.
        let anchored = try XCTUnwrap(model.objects.first { $0.id == "anchored" })
        XCTAssertEqual(anchored.anchorMode, .paragraph)
        XCTAssertEqual(anchored.anchorParagraph, "p2")
        XCTAssertEqual(anchored.offset, PointModel(x: 10, y: 20))

        // Unknown object type is kept, not dropped (readers ignore, not destroy).
        XCTAssertNotNil(model.objects.first { $0.id == "future" })

        // Image payloads: the referenced file is loaded; the unreferenced one is
        // read too (it is a legal images/ entry); the dangling reference simply
        // has no payload.
        XCTAssertNotNil(contents.images["images/lake.png"])
        XCTAssertNil(contents.images["images/missing.png"])

        // The wrapping objects on page 0 produce exclusion rects in z order.
        let metrics = PageMetrics(page: model.page)
        let rects = ExclusionPathController.exclusionRects(forPage: 0,
                                                           objects: model.objects,
                                                           metrics: metrics)
        XCTAssertEqual(rects.count, 2, "img3 (irregular→rect) and img1; img2 wraps none")
    }

    func testListsFixtureNumbering() throws {
        let model = try LuceArchive.read(fixture("lists.luce")).model
        let resolved = ListMarkers.resolve(model.body.map(\.list))
        let byID = Dictionary(uniqueKeysWithValues: zip(model.body.map(\.id), resolved))
        XCTAssertEqual(byID["l1"]??.text, "1.")
        XCTAssertEqual(byID["l3"]??.text, "a.")
        XCTAssertEqual(byID["l4"]??.text, "b.")
        XCTAssertEqual(byID["l5"]??.text, "3.", "outdent resumes the level-0 counter")
        XCTAssertEqual(byID["l6"]??.text, "\u{2013}")
        XCTAssertEqual(byID["l7"]??.text, "4.", "a bullet must not eat a number")
        XCTAssertEqual(byID["break"] ?? nil, nil)
        XCTAssertEqual(byID["l8"]??.text, "X.", "start: 10 upper-roman after a break")
        XCTAssertEqual(byID["l9"]??.text, "\u{25E6}")
    }

    func testTablesFixtureGridAndMarkdown() throws {
        let model = try LuceArchive.read(fixture("tables.luce")).model
        let cells = model.body.compactMap(\.cell)
        XCTAssertEqual(cells.count, 7)
        let columnCount = cells.map { $0.column + $0.columnSpan }.max()
        XCTAssertEqual(columnCount, 3)

        // The derived Markdown renders one GFM table with the pipe escaped.
        let markdown = MarkdownExporter.export(model)
        XCTAssertTrue(markdown.contains("| Header A | Header B | Header C |"), markdown)
        XCTAssertTrue(markdown.contains("y \\| pipe"), markdown)
    }

    func testHistoryFixtureSnapshots() throws {
        let contents = try LuceArchive.read(fixture("history.luce"))
        XCTAssertEqual(contents.history.count, 2, "the unparseable name is skipped")
        let sorted = contents.history.sorted { $0.timestamp < $1.timestamp }
        XCTAssertEqual(sorted.first?.markdown, "Older prose.\n")
        XCTAssertEqual(sorted.last?.markdown, "Newer prose.\n")
    }

    // MARK: - Invalid fixtures are rejected for the right reason

    func testWrongFormatIsRejected() throws {
        XCTAssertThrowsError(try LuceArchive.read(fixture("invalid/wrong-format.luce"))) { error in
            guard case DocumentCoding.DocumentError.wrongFormat(let found) = error else {
                return XCTFail("expected wrongFormat, got \(error)")
            }
            XCTAssertEqual(found, "somebody-elses-document")
        }
    }

    func testTooNewFormatVersionIsRejected() throws {
        XCTAssertThrowsError(try LuceArchive.read(fixture("invalid/format-too-new.luce"))) { error in
            guard case DocumentCoding.DocumentError.formatTooNew(let found, let supported) = error else {
                return XCTFail("expected formatTooNew, got \(error)")
            }
            XCTAssertEqual(found, 99)
            XCTAssertEqual(supported, LucerneDocumentModel.currentFormatVersion)
        }
    }
}
