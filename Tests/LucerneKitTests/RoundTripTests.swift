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

    func testHistorySnapshotsRoundTrip() throws {
        let model = DefaultDocuments.empty()
        let history = [
            HistorySnapshot(timestamp: Date(timeIntervalSince1970: 1_700_000_000), markdown: "v1"),
            HistorySnapshot(timestamp: Date(timeIntervalSince1970: 1_700_086_400), markdown: "v2")
        ]
        let packaged = try LuceArchive.write(model: model, images: [:], history: history)
        let contents = try LuceArchive.read(packaged)
        XCTAssertEqual(contents.history.count, 2)
        XCTAssertEqual(contents.history.map(\.markdown).sorted(), ["v1", "v2"])
    }
}

final class HistoryPrunerTests: XCTestCase {

    func testEntryNameRoundTrips() throws {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let name = HistoryPruner.entryName(for: date)
        XCTAssertTrue(name.hasPrefix("history/"))
        XCTAssertTrue(name.hasSuffix(".md"))
        let parsed = try XCTUnwrap(HistoryPruner.timestamp(fromEntryName: name))
        XCTAssertEqual(parsed.timeIntervalSince1970, date.timeIntervalSince1970, accuracy: 1)
        XCTAssertNil(HistoryPruner.timestamp(fromEntryName: "content.md"))
    }

    func testNoDuplicateSnapshotWhenTextUnchanged() {
        let now = Date()
        let h1 = HistoryPruner.updated(history: [], addingMarkdown: "hello", now: now)
        XCTAssertEqual(h1.count, 1)
        let h2 = HistoryPruner.updated(history: h1, addingMarkdown: "hello", now: now.addingTimeInterval(60))
        XCTAssertEqual(h2.count, 1, "identical text must not add a snapshot")
        let h3 = HistoryPruner.updated(history: h2, addingMarkdown: "hello world", now: now.addingTimeInterval(120))
        XCTAssertEqual(h3.count, 2)
    }

    func testRetentionThinsOldSnapshotsButKeepsRecent() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let day: TimeInterval = 86_400
        let timestamps = (0 ..< 200).map { now.addingTimeInterval(-Double($0) * day) }
        let kept = HistoryPruner.keep(timestamps: timestamps, now: now)
        XCTAssertLessThan(kept.count, timestamps.count, "old snapshots should be thinned")
        XCTAssertLessThanOrEqual(kept.count, 120)
        for recent in timestamps.prefix(12) {
            XCTAssertTrue(kept.contains(recent), "the most recent snapshots must be kept")
        }
    }

    func testFrequentEditsThinToAboutHourly() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let timestamps = (0 ..< 100).map { now.addingTimeInterval(-Double($0) * 900) }  // every 15 min
        let kept = HistoryPruner.keep(timestamps: timestamps, now: now, recent: 4, maxCount: 120)
        XCTAssertLessThan(kept.count, 40, "sub-hour edits should collapse to roughly hourly")
    }
}

final class TableOfContentsLeaderTests: XCTestCase {

    private let font = NSFont.systemFont(ofSize: 12)

    func testMoreWidthFitsMoreDots() {
        let narrow = EditorController.leaderDotCount(title: "Chapter One", page: "12",
                                                     availableWidth: 220, font: font)
        let wide = EditorController.leaderDotCount(title: "Chapter One", page: "12",
                                                   availableWidth: 440, font: font)
        XCTAssertGreaterThan(wide, narrow)
    }

    func testNoRoomYieldsNoDots() {
        let n = EditorController.leaderDotCount(title: String(repeating: "x", count: 90), page: "100",
                                                availableWidth: 60, font: font)
        XCTAssertEqual(n, 0)
    }

    func testLeaderLineStaysWithinAvailableWidth() {
        let width: CGFloat = 360
        let title = "Introduction", page = "7"
        let n = EditorController.leaderDotCount(title: title, page: page,
                                                availableWidth: width, font: font)
        XCTAssertGreaterThan(n, 0)
        let line = "\(title) " + String(repeating: ".", count: n) + " \(page)"
        let laidOut = (line as NSString).size(withAttributes: [.font: font]).width
        XCTAssertLessThanOrEqual(laidOut, width + 0.5, "the leader line must not overflow the column")
    }
}

final class TableRoundTripTests: XCTestCase {

    private func table2x2() -> LucerneDocumentModel {
        func cell(_ r: Int, _ c: Int, _ text: String) -> Paragraph {
            Paragraph(id: "c\(r)\(c)", style: "body",
                      cell: TableCellModel(table: "t1", row: r, column: c), runs: [Run(text: text)])
        }
        return LucerneDocumentModel(
            page: .a4, styles: DefaultDocuments.defaultStyles(),
            body: [cell(0, 0, "A"), cell(0, 1, "B"), cell(1, 0, "C"), cell(1, 1, "D")],
            objects: [])
    }

    func testTableCellsSurviveTextBridge() {
        let model = table2x2()
        let attributed = AttributedStringBuilder.attributedString(for: model)
        let restored = AttributedStringReader.paragraphs(from: attributed, styles: model.styles)

        let cells = restored.compactMap { $0.cell }
        XCTAssertEqual(cells.count, 4, "all four cells should round-trip as table cells")
        XCTAssertEqual(Set(cells.map(\.table)).count, 1, "cells of one table must share one id")
        XCTAssertEqual(cells.map { "\($0.row)\($0.column)" }.sorted(), ["00", "01", "10", "11"])
        XCTAssertEqual(restored.compactMap { $0.cell != nil ? $0.plainText : nil }, ["A", "B", "C", "D"])
    }

    func testTableModelRoundTripsThroughJSON() throws {
        let model = table2x2()
        let data = try JSONEncoder().encode(model)
        let decoded = try JSONDecoder().decode(LucerneDocumentModel.self, from: data)
        XCTAssertEqual(decoded, model)
        XCTAssertEqual(decoded.body.first?.cell?.column, 0)
        XCTAssertEqual(decoded.body.first?.cell?.rowSpan, 1)
    }

    func testMergedCellSpanSurvivesTextBridge() {
        // A merged cell at (0,0) spanning 2×2; covered positions have no paragraph.
        let model = LucerneDocumentModel(
            page: .a4, styles: DefaultDocuments.defaultStyles(),
            body: [Paragraph(id: "m", style: "body",
                             cell: TableCellModel(table: "t1", row: 0, column: 0, rowSpan: 2, columnSpan: 2),
                             runs: [Run(text: "merged")])],
            objects: [])
        let attributed = AttributedStringBuilder.attributedString(for: model)
        let restored = AttributedStringReader.paragraphs(from: attributed, styles: model.styles)
        let cell = restored.compactMap { $0.cell }.first
        XCTAssertEqual(cell?.rowSpan, 2)
        XCTAssertEqual(cell?.columnSpan, 2)
        XCTAssertEqual(restored.compactMap { $0.cell }.count, 1, "covered positions have no cell paragraph")
    }

    func testColumnWidthsSurviveTextBridge() {
        func cell(_ r: Int, _ c: Int, _ width: Double) -> Paragraph {
            Paragraph(id: "c\(r)\(c)", style: "body",
                      cell: TableCellModel(table: "t1", row: r, column: c, width: width), runs: [Run(text: "x")])
        }
        // Two columns split 70% / 30%.
        let model = LucerneDocumentModel(
            page: .a4, styles: DefaultDocuments.defaultStyles(),
            body: [cell(0, 0, 70), cell(0, 1, 30), cell(1, 0, 70), cell(1, 1, 30)], objects: [])
        let attributed = AttributedStringBuilder.attributedString(for: model)
        let restored = AttributedStringReader.paragraphs(from: attributed, styles: model.styles)
        let cells = restored.compactMap { $0.cell }
        XCTAssertTrue(cells.filter { $0.column == 0 }.allSatisfy { abs(($0.width ?? 0) - 70) < 0.5 })
        XCTAssertTrue(cells.filter { $0.column == 1 }.allSatisfy { abs(($0.width ?? 0) - 30) < 0.5 })
    }

    func testRowInsertionPreservesEveryParagraphInMultiParagraphCell() throws {
        func cell(_ id: String, _ column: Int, _ text: String,
                  italic: Bool? = nil) -> Paragraph {
            Paragraph(id: id, style: "body",
                      cell: TableCellModel(table: "t1", row: 0, column: column),
                      runs: [Run(text: text, italic: italic)])
        }
        let model = LucerneDocumentModel(
            page: .a4, styles: DefaultDocuments.defaultStyles(),
            body: [
                cell("first", 0, "First paragraph"),
                cell("second", 0, "Second paragraph", italic: true),
                cell("right", 1, "Right cell"),
                Paragraph(id: "after", style: "body", runs: [Run(text: "After table")]),
            ],
            objects: [])
        let editor = EditorController(model: model)
        let textView = try XCTUnwrap(
            editor.layoutManager.textContainers.first?.textView as? PageTextView)
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        editor.textViewBecameActive(textView)

        editor.insertTableRow(below: true)

        let restored = editor.snapshotModel()
        let firstCell = restored.body.filter { paragraph in
            paragraph.cell?.row == 0 && paragraph.cell?.column == 0
        }
        XCTAssertEqual(firstCell.map(\.id), ["first", "second"])
        XCTAssertEqual(firstCell.map(\.plainText), ["First paragraph", "Second paragraph"])
        let secondParagraph = try XCTUnwrap(firstCell.last)
        XCTAssertEqual(secondParagraph.runs.first?.italic, true,
                       "later paragraphs must retain their attributed runs")
        XCTAssertEqual(restored.body.filter { $0.cell?.row == 1 }.count, 2,
                       "the requested row should still be inserted")
        XCTAssertTrue(restored.body.contains { $0.id == "right" && $0.plainText == "Right cell" })
        XCTAssertTrue(restored.body.contains { $0.id == "after" && $0.plainText == "After table" })
    }
}

final class FurnitureModelTests: XCTestCase {

    func testHeaderFooterAndPageNumberStartRoundTripThroughJSON() throws {
        var model = DefaultDocuments.empty()
        model.header = PageFurniture(center: "{title}")
        model.footer = PageFurniture(left: "{date}", center: "{page}")
        model.pageNumberStart = 3

        let data = try JSONEncoder().encode(model)
        let decoded = try JSONDecoder().decode(LucerneDocumentModel.self, from: data)
        XCTAssertEqual(decoded, model)
        XCTAssertEqual(decoded.pageNumberStart, 3)
    }

    func testAbsentPageNumberStartDecodesAsNil() throws {
        // A v1 file without the (additive, optional) key must still load.
        let model = DefaultDocuments.empty()
        let data = try JSONEncoder().encode(model)
        let decoded = try JSONDecoder().decode(LucerneDocumentModel.self, from: data)
        XCTAssertNil(decoded.pageNumberStart)
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
