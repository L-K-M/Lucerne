import XCTest
@testable import LucerneKit

/// Data-safety tests for the save / archive path: oversize entries and ZIP64
/// archives fail cleanly, non-ASCII names declare UTF-8, a referenced-but-missing
/// image aborts the save, and two same-second history snapshots don't collide.
final class IOSafetyTests: XCTestCase {

    private enum ExpectedError: Error { case archiveFailed }

    // (a) An entry above the (injected) size cap is rejected, not written. The real
    // cap is 512 MiB; injecting a tiny cap keeps the test cheap.
    func testArchiveRejectsEntryOverSizeCap() {
        let entry = MiniZip.Entry(name: "big.bin", data: Data(count: 64))
        XCTAssertThrowsError(try MiniZip.archive([entry], maxEntrySize: 8)) {
            XCTAssertTrue($0 is MiniZip.ZipError, "expected ZipError, got \($0)")
        }
    }

    func testArchiveAcceptsEntryAtCap() throws {
        let entry = MiniZip.Entry(name: "ok.bin", data: Data(count: 8))
        let data = try MiniZip.archive([entry], maxEntrySize: 8)
        XCTAssertEqual(try MiniZip.entries(from: data), [entry])
    }

    // (b) A non-ASCII name round-trips and the local header declares UTF-8 (bit 11).
    func testNonASCIINameRoundTripsAndSetsUTF8Flag() throws {
        let entry = MiniZip.Entry(name: "images/Zürich.png", data: Data("photo".utf8))
        let archive = MiniZip.archive([entry])

        XCTAssertEqual(try MiniZip.entries(from: archive), [entry],
                       "a non-ASCII entry name must survive a round trip")

        // Local file header: bytes 0–3 signature, 4–5 version, 6–7 general-purpose
        // flag. Bit 11 (0x0800) marks the name as UTF-8.
        let flag = UInt16(archive[6]) | (UInt16(archive[7]) << 8)
        XCTAssertEqual(flag & 0x0800, 0x0800, "the UTF-8 (EFS) name flag must be set")
    }

    // (c) A ZIP64 sentinel EOCD is reported as unsupported, not corrupt / notAZip.
    func testZip64SentinelReportsUnsupported() {
        var data = MiniZip.archive([MiniZip.Entry(name: "a.txt", data: Data("hi".utf8))])
        let eocdSig = Data([0x50, 0x4b, 0x05, 0x06])
        guard let eocd = data.range(of: eocdSig, options: .backwards)?.lowerBound else {
            return XCTFail("EOCD signature not found")
        }
        // Central-directory offset field (eocd + 16) → the ZIP64 sentinel 0xFFFFFFFF.
        for i in 0 ..< 4 { data[eocd + 16 + i] = 0xff }
        XCTAssertThrowsError(try MiniZip.entries(from: data)) {
            guard let error = $0 as? MiniZip.ZipError, case .unsupported = error else {
                return XCTFail("expected .unsupported, got \($0)")
            }
        }
    }

    // (d) Saving a model that references an image with no bytes must throw, not
    // quietly write a document that lost the picture.
    func testWriteThrowsWhenReferencedImageMissing() {
        var model = DefaultDocuments.empty()
        model.objects = [PlacedObject(id: "img1", type: "image", src: "images/missing.png")]
        XCTAssertThrowsError(try LuceArchive.write(model: model, images: [:]))
    }

    func testWriteSucceedsWhenReferencedImagePresent() throws {
        var model = DefaultDocuments.empty()
        model.objects = [PlacedObject(id: "img1", type: "image", src: "images/lake.png")]
        let data = try LuceArchive.write(model: model, images: ["images/lake.png": Data("bytes".utf8)])
        let contents = try LuceArchive.read(data)
        XCTAssertEqual(contents.images["images/lake.png"], Data("bytes".utf8))
    }

    // (e) Two snapshots whose timestamps land in the same second get distinct names.
    func testSameSecondSnapshotsGetDistinctEntryNames() {
        let t = Date(timeIntervalSince1970: 1_700_000_000)
        let existing = [HistorySnapshot(timestamp: t, markdown: "old prose")]
        let updated = HistoryPruner.updated(history: existing, addingMarkdown: "new prose", now: t)
        XCTAssertEqual(updated.count, 2, "a differing snapshot must be appended")
        let names = updated.map { HistoryPruner.entryName(for: $0.timestamp) }
        XCTAssertEqual(Set(names).count, names.count, "history entry names must be unique")
    }

    func testHistoryUpdateCommitsOnlyAfterArchiveSucceeds() throws {
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let original = [HistorySnapshot(timestamp: timestamp, markdown: "old prose")]
        var history = original

        XCTAssertThrowsError(try HistoryArchiveWriter.write(
            history: &history, addingMarkdown: "new prose", now: timestamp
        ) { _ in
            throw ExpectedError.archiveFailed
        })
        XCTAssertEqual(history, original, "a failed save must not advance in-memory history")

        let data = try HistoryArchiveWriter.write(
            history: &history, addingMarkdown: "new prose", now: timestamp
        ) { updatedHistory in
            Data(updatedHistory.last!.markdown.utf8)
        }
        XCTAssertEqual(data, Data("new prose".utf8))
        XCTAssertEqual(history.last?.markdown, "new prose")
        XCTAssertEqual(history.count, 2)
    }
}
