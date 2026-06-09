import XCTest
import AppKit
@testable import LucerneKit

// Round-trip tests for the trickiest hand-written subsystems: the model⇆attributed
// string bridge, the ZIP layer, and the .luce package. These run on the macOS CI
// runner (they need AppKit) and guard against regressions in the parts most likely
// to break silently.

final class TextBridgeRoundTripTests: XCTestCase {

    func testParagraphTextRolesAndIDsRoundTrip() {
        let model = DefaultDocuments.sampleLetter()
        let attributed = AttributedStringBuilder.attributedString(for: model)
        let restored = AttributedStringReader.paragraphs(from: attributed, styles: model.styles)

        XCTAssertEqual(restored.count, model.body.count)
        for (original, round) in zip(model.body, restored) {
            XCTAssertEqual(round.plainText, original.plainText, "text should survive")
            XCTAssertEqual(round.style, original.style, "style role should survive")
            XCTAssertEqual(round.id, original.id, "paragraph id should survive")
        }
    }

    func testItalicRunSurvivesRoundTrip() {
        let model = LucerneDocumentModel(
            page: .a4, styles: DefaultDocuments.defaultStyles(),
            body: [Paragraph(id: "p", style: "body", runs: [
                Run(text: "a "), Run(text: "b", italic: true), Run(text: " c")
            ])],
            objects: [])
        let attributed = AttributedStringBuilder.attributedString(for: model)
        let restored = AttributedStringReader.paragraphs(from: attributed, styles: model.styles)

        XCTAssertEqual(restored.count, 1)
        XCTAssertEqual(restored[0].plainText, "a b c")
        let italicRun = restored[0].runs.first { $0.italic == true }
        XCTAssertEqual(italicRun?.text, "b")
    }

    func testEmptyDocumentRoundTrip() {
        let model = DefaultDocuments.empty()
        let attributed = AttributedStringBuilder.attributedString(for: model)
        let restored = AttributedStringReader.paragraphs(from: attributed, styles: model.styles)
        XCTAssertEqual(restored.count, 1)
        XCTAssertEqual(restored[0].plainText, "")
        XCTAssertEqual(restored[0].style, "body")
    }

    func testAlignmentOverrideSurvivesRoundTrip() {
        let model = LucerneDocumentModel(
            page: .a4, styles: DefaultDocuments.defaultStyles(),
            body: [Paragraph(id: "p", style: "body", align: "center", runs: [Run(text: "centered")])],
            objects: [])
        let attributed = AttributedStringBuilder.attributedString(for: model)
        let restored = AttributedStringReader.paragraphs(from: attributed, styles: model.styles)
        XCTAssertEqual(restored[0].align, "center")
    }
}

final class MiniZipTests: XCTestCase {

    func testStoredEntriesRoundTrip() throws {
        let entries = [
            MiniZip.Entry(name: "document.json", data: Data(#"{"hello":true}"#.utf8)),
            MiniZip.Entry(name: "images/a.bin", data: Data((0 ..< 1000).map { UInt8($0 % 256) })),
            MiniZip.Entry(name: "content.md", data: Data("# Title\n\nbody".utf8)),
        ]
        let archive = MiniZip.archive(entries)
        let restored = try MiniZip.entries(from: archive)

        XCTAssertEqual(Set(restored.map(\.name)), Set(entries.map(\.name)))
        for entry in entries {
            XCTAssertEqual(restored.first { $0.name == entry.name }?.data, entry.data, entry.name)
        }
    }

    func testEmptyEntryRoundTrips() throws {
        let archive = MiniZip.archive([MiniZip.Entry(name: "empty", data: Data())])
        let restored = try MiniZip.entries(from: archive)
        XCTAssertEqual(restored.count, 1)
        XCTAssertEqual(restored[0].data.count, 0)
    }

    func testRejectsNonZipData() {
        XCTAssertThrowsError(try MiniZip.entries(from: Data("definitely not a zip".utf8)))
    }
}

final class LuceArchiveRoundTripTests: XCTestCase {

    func testPackageRoundTripsModelAndImages() throws {
        let model = DefaultDocuments.sampleLetter()
        let imageBytes = Data((0 ..< 512).map { UInt8(($0 * 7) % 256) })
        let images = ["images/lake.png": imageBytes]

        let packaged = try LuceArchive.write(model: model, images: images)
        let contents = try LuceArchive.read(packaged)

        XCTAssertEqual(contents.model, model, "document.json should round-trip exactly")
        XCTAssertEqual(contents.images["images/lake.png"], imageBytes, "image bytes should be byte-identical")

        // content.md must be present (write-only escape hatch) but is not read back.
        let rawEntries = try MiniZip.entries(from: packaged)
        XCTAssertTrue(rawEntries.contains { $0.name == LuceArchive.markdownEntryName })
        XCTAssertTrue(rawEntries.contains { $0.name == LuceArchive.documentEntryName })
    }
}

final class PageMetricsTests: XCTestCase {

    func testExclusionRectShiftsByMarginAndStandoff() {
        let metrics = PageMetrics(page: .a4)   // 72pt margins
        // Object at page (320, 180), 200x140, standoff 12.
        let rect = metrics.exclusionRect(
            forObjectFrame: RectModel(x: 320, y: 180, width: 200, height: 140), standoff: 12)
        // container x = 320 - 72 - 12 = 236; y = 180 - 72 - 12 = 96
        XCTAssertEqual(rect.origin.x, 236, accuracy: 0.001)
        XCTAssertEqual(rect.origin.y, 96, accuracy: 0.001)
        XCTAssertEqual(rect.width, 224, accuracy: 0.001)   // 200 + 24
        XCTAssertEqual(rect.height, 164, accuracy: 0.001)  // 140 + 24
    }

    func testNarrowRightGapSnapsExclusionToRightMargin() {
        let metrics = PageMetrics(page: .a4)
        // Image whose right edge sits ~23pt from the right margin → unusable column.
        let rect = metrics.exclusionRect(
            forObjectFrame: RectModel(x: 380, y: 200, width: 120, height: 100), standoff: 12)
        XCTAssertEqual(rect.maxX, metrics.contentSize.width, accuracy: 0.001,
                       "a too-narrow right gap should be absorbed into the exclusion")
    }

    func testNarrowLeftGapSnapsExclusionToLeftMargin() {
        let metrics = PageMetrics(page: .a4)
        // Image near the left margin leaving a ~16pt sliver on the left.
        let rect = metrics.exclusionRect(
            forObjectFrame: RectModel(x: 100, y: 200, width: 200, height: 100), standoff: 12)
        XCTAssertEqual(rect.minX, 0, accuracy: 0.001,
                       "a too-narrow left gap should be absorbed into the exclusion")
    }

    func testUsableColumnsAreKept() {
        let metrics = PageMetrics(page: .a4)
        // A centered-ish image leaving generous columns on both sides keeps them.
        let rect = metrics.exclusionRect(
            forObjectFrame: RectModel(x: 220, y: 200, width: 150, height: 100), standoff: 12)
        XCTAssertGreaterThan(rect.minX, 0)
        XCTAssertLessThan(rect.maxX, metrics.contentSize.width)
    }

    func testClampKeepsObjectOnPage() {
        let metrics = PageMetrics(page: .a4)
        let clamped = metrics.clampObjectFrame(CGRect(x: -50, y: -50, width: 100, height: 100))
        XCTAssertGreaterThanOrEqual(clamped.minX, 0)
        XCTAssertGreaterThanOrEqual(clamped.minY, 0)
        XCTAssertLessThanOrEqual(clamped.maxX, metrics.pageSize.width)
        XCTAssertLessThanOrEqual(clamped.maxY, metrics.pageSize.height)
    }
}
