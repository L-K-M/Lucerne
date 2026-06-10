import XCTest
@testable import LucerneKit

/// Robustness tests for MiniZip against malformed / hostile archives: a corrupt
/// .luce must produce a clean `ZipError`, never an index-out-of-range crash or a
/// multi-gigabyte allocation, and bit rot must be caught by the stored CRCs.
final class MiniZipHardeningTests: XCTestCase {

    private let payload = Data("hello, lake".utf8)

    private func sampleArchive() -> Data {
        MiniZip.archive([MiniZip.Entry(name: "a.txt", data: payload)])
    }

    /// Offset of the (single) central-directory header in `archive`.
    private func centralDirectoryOffset(in archive: Data) -> Int {
        let sig = Data([0x50, 0x4b, 0x01, 0x02])
        guard let range = archive.range(of: sig) else {
            XCTFail("central directory signature not found")
            return 0
        }
        return range.lowerBound
    }

    private func assertThrowsZipError(_ data: Data, _ message: String,
                                      file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try MiniZip.entries(from: data), message, file: file, line: line) {
            XCTAssertTrue($0 is MiniZip.ZipError, "expected ZipError, got \($0)", file: file, line: line)
        }
    }

    func testIntactArchiveStillRoundTrips() throws {
        let entries = try MiniZip.entries(from: sampleArchive())
        XCTAssertEqual(entries, [MiniZip.Entry(name: "a.txt", data: payload)])
    }

    func testOverlongNameLengthThrowsInsteadOfCrashing() {
        var data = sampleArchive()
        let central = centralDirectoryOffset(in: data)
        // Declare a 65535-byte name that reaches far past the end of the file.
        data[central + 28] = 0xff
        data[central + 29] = 0xff
        assertThrowsZipError(data, "an overlong declared name must throw, not crash")
    }

    func testOverlongExtraAndCommentLengthsThrow() {
        var data = sampleArchive()
        let central = centralDirectoryOffset(in: data)
        data[central + 30] = 0xff   // extra length
        data[central + 31] = 0xff
        data[central + 32] = 0xff   // comment length
        data[central + 33] = 0xff
        assertThrowsZipError(data, "overlong extra/comment fields must throw, not crash")
    }

    func testHugeDeclaredUncompressedSizeIsRejected() {
        var data = sampleArchive()
        let central = centralDirectoryOffset(in: data)
        data[central + 10] = 8      // method: deflate (so the size drives an inflate buffer)
        data[central + 11] = 0
        for i in 0 ..< 4 {          // uncompressed size: 0xFFFFFFFF (≈ 4 GiB)
            data[central + 24 + i] = 0xff
        }
        assertThrowsZipError(data, "a 4 GiB declared size must be rejected, not allocated")
    }

    func testCorruptedPayloadFailsCRCCheck() {
        var data = sampleArchive()
        // The stored payload sits right after the 30-byte local header + name.
        let payloadStart = 30 + "a.txt".utf8.count
        data[payloadStart] ^= 0xff
        assertThrowsZipError(data, "a flipped payload byte must fail the CRC check")
    }

    func testBogusLocalHeaderOffsetThrows() {
        var data = sampleArchive()
        let central = centralDirectoryOffset(in: data)
        for i in 0 ..< 4 {          // local header offset: 0xFFFFFFFF
            data[central + 42 + i] = 0xff
        }
        assertThrowsZipError(data, "an out-of-range local header offset must throw")
    }

    func testTruncatedArchiveThrows() {
        let data = sampleArchive()
        // Slicing off the tail removes the end-of-central-directory record.
        assertThrowsZipError(data.prefix(data.count - 8), "a truncated archive must throw")
    }

    // MARK: - Droppable (best-effort) entries

    func testCorruptDroppableEntryIsSkippedNotFatal() throws {
        let keep = MiniZip.Entry(name: "document.json", data: Data("{\"k\":1}".utf8))
        let bestEffort = MiniZip.Entry(name: "history/2026.md", data: Data("old prose".utf8))
        var data = MiniZip.archive([keep, bestEffort])
        let needle = Data("old prose".utf8)
        guard let range = data.range(of: needle) else { return XCTFail("payload not found") }
        data[range.lowerBound] ^= 0xff

        // Strict read refuses the whole archive…
        assertThrowsZipError(data, "strict read must fail on any CRC mismatch")
        // …while the lenient read drops only the rotted best-effort entry.
        let entries = try MiniZip.entries(from: data,
                                          droppingCorruptEntriesWhere: { $0.hasPrefix("history/") })
        XCTAssertEqual(entries, [keep], "the intact entry must survive; the rotted one is dropped")
    }

    func testCorruptAuthoritativeEntryStillThrowsUnderLenientRead() {
        var data = sampleArchive()   // single entry "a.txt"
        let payloadStart = 30 + "a.txt".utf8.count
        data[payloadStart] ^= 0xff
        XCTAssertThrowsError(try MiniZip.entries(
            from: data, droppingCorruptEntriesWhere: { $0.hasPrefix("history/") }),
            "corruption in a non-droppable entry must stay fatal")
    }

    func testRottedHistorySnapshotDoesNotBlockOpeningTheDocument() throws {
        let model = DefaultDocuments.empty()
        let snapshot = HistorySnapshot(timestamp: Date(timeIntervalSince1970: 1_700_000_000),
                                       markdown: "recoverable prose")
        var data = try LuceArchive.write(model: model, images: [:], history: [snapshot])
        let needle = Data("recoverable prose".utf8)
        guard let range = data.range(of: needle) else { return XCTFail("snapshot payload not found") }
        data[range.lowerBound] ^= 0xff

        let contents = try LuceArchive.read(data)    // must still open
        XCTAssertEqual(contents.model, model)
        XCTAssertTrue(contents.history.isEmpty, "the rotted snapshot is dropped, not fatal")
    }
}
