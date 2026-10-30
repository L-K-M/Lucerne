import XCTest
@testable import LucerneCore

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

    private func endOfCentralDirectoryOffset(in archive: Data) -> Int {
        let sig = Data([0x50, 0x4b, 0x05, 0x06])
        guard let range = archive.range(of: sig, options: .backwards) else {
            XCTFail("end of central directory signature not found")
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

    func testExpectedZeroCRCIsStillValidated() {
        var data = sampleArchive()
        let central = centralDirectoryOffset(in: data)
        for i in 0 ..< 4 { data[central + 16 + i] = 0 }
        assertThrowsZipError(data, "a zero expected CRC must not disable CRC validation")
    }

    func testEmptyPayloadWithValidZeroCRCRoundTrips() throws {
        let entry = MiniZip.Entry(name: "empty.txt", data: Data())
        XCTAssertEqual(try MiniZip.entries(from: MiniZip.archive([entry])), [entry])
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

    func testEOCDSignatureInsideValidArchiveCommentIsIgnored() throws {
        var data = sampleArchive()
        let eocd = endOfCentralDirectoryOffset(in: data)
        let signature: [UInt8] = [0x50, 0x4b, 0x05, 0x06]
        let comment = Data(signature + Array(repeating: UInt8(0), count: 26))
        data[eocd + 20] = UInt8(comment.count & 0xff)
        data[eocd + 21] = UInt8(comment.count >> 8)
        data.append(comment)

        XCTAssertEqual(try MiniZip.entries(from: data),
                       [MiniZip.Entry(name: "a.txt", data: payload)])
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

/// Positive coverage for the DEFLATE (method 8) read path — the reference writer
/// only ever emits STORED entries, so without this fixture the inflate branch
/// (Apple Compression on macOS, zlib on Linux) would go untested. The archive was
/// built externally: one entry "deflated.txt", 268 bytes of text deflated to 72.
final class MiniZipDeflateReadTests: XCTestCase {

    private let fixtureBase64 = "UEsDBBQAAAgIAAAAIQD6e05fSAAAAAwBAAAMAAAAZGVmbGF0ZWQudHh080jNyclXSCvKz1VIVHBxdfNxDHHVTc7PLShKLS5OTVFIzSspqlTIzCvOTEkFqtDLKU1OVShJLS5RSMusKCktStVT8BguRgAAUEsBAhQAFAAACAgAAAAhAPp7Tl9IAAAADAEAAAwAAAAAAAAAAAAAAAAAAAAAAGRlZmxhdGVkLnR4dFBLBQYAAAAAAQABADoAAAByAAAAAAA="

    func testDeflatedEntryInflatesAndPassesCRC() throws {
        let archive = try XCTUnwrap(Data(base64Encoded: fixtureBase64))
        let entries = try MiniZip.entries(from: archive)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.name, "deflated.txt")
        let expected = Data(String(repeating:
            "Hello from a DEFLATE-compressed entry inside a .luce test fixture. ",
            count: 4).utf8)
        XCTAssertEqual(entries.first?.data, expected)
    }

    func testCorruptDeflateStreamFailsCleanly() throws {
        let archive = try XCTUnwrap(Data(base64Encoded: fixtureBase64))
        // Flip a byte INSIDE the compressed payload (data starts at 42 = 30-byte
        // local header + 12-byte name): every record length stays valid and the
        // central directory stays reachable, so only the inflate/CRC path can
        // fail — the whole read throws (strict mode). Removing bytes instead
        // would desync the EOCD's central-directory offset and fail on the
        // directory walk before inflate ever ran.
        var corrupt = archive
        corrupt[60] ^= 0xFF
        XCTAssertThrowsError(try MiniZip.entries(from: corrupt))
    }
}

/// Entry-name safety for the .luce writer/reader: duplicate names are refused on
/// both paths, and image `src` values are normalized to flat `images/<file>` names
/// on write while spec-legal sources outside `images/` still load on read.
final class ZipEntryNameSafetyTests: XCTestCase {

    private let imagePayload = Data([0x89, 0x50, 0x4e, 0x47])

    private func modelWithImage(src: String) -> LucerneDocumentModel {
        var model = DefaultDocuments.empty()
        model.objects = [PlacedObject(id: "img", type: "image", src: src, page: 0,
                                      frame: RectModel(x: 10, y: 10, width: 50, height: 50))]
        return model
    }

    func testWriterRejectsDuplicateEntryNames() {
        let entries = [MiniZip.Entry(name: "a.txt", data: Data("one".utf8)),
                       MiniZip.Entry(name: "a.txt", data: Data("two".utf8))]
        XCTAssertThrowsError(try MiniZip.archive(entries, maxEntrySize: MiniZip.maxEntrySize)) { error in
            guard case MiniZip.ZipError.duplicateEntry("a.txt") = error else {
                return XCTFail("expected duplicateEntry, got \(error)")
            }
        }
    }

    func testReaderRejectsDuplicateEntryNames() throws {
        // The writer now refuses duplicates, so craft one by renaming the second
        // of two same-length entries ("b.txt" -> "a.txt") in both headers.
        var data = MiniZip.archive([
            MiniZip.Entry(name: "a.txt", data: Data("one".utf8)),
            MiniZip.Entry(name: "b.txt", data: Data("two".utf8))
        ])
        let old = Data("b.txt".utf8), new = Data("a.txt".utf8)
        var cursor = 0
        while let range = data.range(of: old, in: cursor..<data.count) {
            data.replaceSubrange(range, with: new)
            cursor = range.lowerBound + new.count
        }
        XCTAssertThrowsError(try MiniZip.entries(from: data)) { error in
            guard case MiniZip.ZipError.duplicateEntry("a.txt") = error else {
                return XCTFail("expected duplicateEntry, got \(error)")
            }
        }
    }

    func testWriteNormalizesNonImagesSourceToFlatName() throws {
        let model = modelWithImage(src: "pictures/lake.png")
        let data = try LuceArchive.write(model: model,
                                         images: ["pictures/lake.png": imagePayload])
        let contents = try LuceArchive.read(data)
        XCTAssertEqual(contents.model.objects.first?.src, "images/lake.png")
        XCTAssertEqual(contents.images["images/lake.png"], imagePayload)
    }

    func testWriteRefusesUnusableImageSource() {
        let model = modelWithImage(src: "/")
        XCTAssertThrowsError(try LuceArchive.write(model: model,
                                                   images: ["/": imagePayload])) { error in
            guard case LuceArchive.ArchiveError.invalidImageSource = error else {
                return XCTFail("expected invalidImageSource, got \(error)")
            }
        }
    }

    func testWriteRefusesDotDotImageSource() {
        let model = modelWithImage(src: "..")
        XCTAssertThrowsError(try LuceArchive.write(model: model, images: ["..": imagePayload])) { error in
            guard case LuceArchive.ArchiveError.invalidImageSource = error else {
                return XCTFail("expected invalidImageSource, got \(error)")
            }
        }
    }

    func testReadCollectsReferencedSourceOutsideImagesPrefix() throws {
        // Spec: `src` MUST name an archive entry; "images/" is only conventional.
        let model = modelWithImage(src: "pictures/a.png")
        let archive = MiniZip.archive([
            MiniZip.Entry(name: LuceArchive.documentEntryName,
                          data: try DocumentCoding.encode(model)),
            MiniZip.Entry(name: "pictures/a.png", data: imagePayload)
        ])
        let contents = try LuceArchive.read(archive)
        XCTAssertEqual(contents.images["pictures/a.png"], imagePayload,
                       "a referenced payload outside images/ must be collected so the file stays savable")
    }

    func testRoundTripPreservesFlatImageSource() throws {
        let model = modelWithImage(src: "images/lake.png")
        let data = try LuceArchive.write(model: model, images: ["images/lake.png": imagePayload])
        let contents = try LuceArchive.read(data)
        XCTAssertEqual(contents.model, model)
        XCTAssertEqual(contents.images["images/lake.png"], imagePayload)
    }
}

extension ZipEntryNameSafetyTests {
    func testWriteRefusesRenameCollisionWithKeptFlatName() {
        // Review feedback on #59: a rename must not collide with an existing
        // flat images/ key either, not just with other renamed sources.
        var model = DefaultDocuments.empty()
        model.objects = [
            PlacedObject(id: "a", type: "image", src: "images/lake.png", page: 0,
                        frame: RectModel(x: 0, y: 0, width: 10, height: 10)),
            PlacedObject(id: "b", type: "image", src: "pictures/lake.png", page: 0,
                        frame: RectModel(x: 20, y: 0, width: 10, height: 10))
        ]
        XCTAssertThrowsError(try LuceArchive.write(
            model: model,
            images: ["images/lake.png": imagePayload, "pictures/lake.png": imagePayload])) { error in
            guard case LuceArchive.ArchiveError.invalidImageSource = error else {
                return XCTFail("expected invalidImageSource, got \(error)")
            }
        }
    }
}
