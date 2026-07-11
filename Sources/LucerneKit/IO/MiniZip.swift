import Foundation
import Compression

// A tiny, self-contained ZIP reader/writer so the project builds with no external
// dependencies (the .luce package is a real ZIP — D4). It writes *stored*
// (uncompressed) entries, which is ideal here: images are already-compressed
// PNG/JPEG and the text payloads are tiny, so compression would buy almost
// nothing. On read it supports stored and DEFLATE (method 8) entries — the latter
// via Apple's Compression framework (COMPRESSION_ZLIB decodes raw DEFLATE) — so
// it can also open archives produced by other tools.
//
// This is not a general-purpose ZIP library (no ZIP64, no encryption, no spanning).
public enum MiniZip {

    public struct Entry: Equatable {
        public var name: String
        public var data: Data
        public init(name: String, data: Data) {
            self.name = name
            self.data = data
        }
    }

    public enum ZipError: Error {
        case notAZip
        case corrupt(String)
        case unsupported(String)
    }

    /// Upper bound on a single entry's uncompressed size. The size field in a
    /// (possibly hostile) archive is attacker-controlled and is used to size the
    /// inflate buffer, so it must not be trusted blindly — a 1 KB file could
    /// otherwise demand a 4 GiB allocation. Generous for a letters document.
    /// Not `private` so the writer (and tests) can enforce the same cap on save.
    static let maxEntrySize = 512 * 1024 * 1024

    // Signatures
    private static let localHeaderSig: UInt32 = 0x0403_4b50
    private static let centralHeaderSig: UInt32 = 0x0201_4b50
    private static let endOfCentralSig: UInt32 = 0x0605_4b50
    private static let dosDate1980: UInt16 = 0x0021   // 1980-01-01 (deterministic)
    private static let dosTimeZero: UInt16 = 0x0000
    /// General-purpose flag bit 11 (EFS): entry names/comments are UTF-8, not CP437,
    /// so strict extractors read non-ASCII names (e.g. "images/Zürich.png") correctly.
    private static let utf8NameFlag: UInt16 = 0x0800

    // MARK: - Writing (stored)

    /// Non-throwing entry point retained for callers that build small, trusted
    /// archives entirely in memory (unit tests). Real saves go through the checked
    /// overload below — that is the one that enforces the size/offset limits.
    public static func archive(_ entries: [Entry]) -> Data {
        // These callers never approach the size or 32-bit-offset limits, so the
        // checked build can't actually throw here; fall back to empty on the
        // impossible path rather than trapping.
        (try? archive(entries, maxEntrySize: maxEntrySize)) ?? Data()
    }

    /// Builds a stored-only ZIP, enforcing the SAME per-entry size cap the reader
    /// applies and rejecting a running offset that would overflow ZIP's 32-bit
    /// fields — so a save can never quietly produce a `.luce` this code then refuses
    /// to reopen (1.13). Throws `ZipError` instead of trapping on the conversions.
    public static func archive(_ entries: [Entry], maxEntrySize: Int) throws -> Data {
        var output = Data()
        var central = Data()
        var offsets: [(entry: Entry, crc: UInt32, offset: UInt32)] = []

        for entry in entries {
            if entry.data.count > maxEntrySize {
                throw ZipError.unsupported(
                    "An entry (\(entry.name)) is too large to store: \(entry.data.count) bytes "
                    + "exceeds the \(maxEntrySize)-byte limit.")
            }
            // Sizes and the running offset go into ZIP's fixed 32-bit fields; a value
            // that no longer fits means a >4 GiB archive this reader could never
            // reopen, so stop with a clean error instead of trapping on the UInt32.
            guard let dataLen = UInt32(exactly: entry.data.count) else {
                throw ZipError.unsupported("An entry (\(entry.name)) exceeds ZIP's 4 GiB size limit.")
            }
            guard let offset = UInt32(exactly: output.count) else {
                throw ZipError.unsupported("The archive exceeds ZIP's 4 GiB size limit.")
            }
            let nameBytes = Array(entry.name.utf8)
            guard let nameLen = UInt16(exactly: nameBytes.count) else {
                throw ZipError.unsupported("An entry name is too long to store.")
            }
            let crc = CRC32.checksum(entry.data)

            // Local file header
            output.appendLE(localHeaderSig)
            output.appendLE(UInt16(20))                  // version needed
            output.appendLE(utf8NameFlag)                // gp flag: bit 11 = UTF-8 names
            output.appendLE(UInt16(0))                   // method: stored
            output.appendLE(dosTimeZero)
            output.appendLE(dosDate1980)
            output.appendLE(crc)
            output.appendLE(dataLen)                     // compressed size
            output.appendLE(dataLen)                     // uncompressed size
            output.appendLE(nameLen)
            output.appendLE(UInt16(0))                   // extra length
            output.append(contentsOf: nameBytes)
            output.append(entry.data)

            offsets.append((entry, crc, offset))
        }

        guard let entryCount = UInt16(exactly: offsets.count) else {
            throw ZipError.unsupported("The archive has too many entries for a non-ZIP64 ZIP.")
        }
        guard let centralStart = UInt32(exactly: output.count) else {
            throw ZipError.unsupported("The archive exceeds ZIP's 4 GiB size limit.")
        }
        for record in offsets {
            // Name length and data size were bounds-checked in the loop above, so
            // these conversions can't trap.
            let nameBytes = Array(record.entry.name.utf8)
            central.appendLE(centralHeaderSig)
            central.appendLE(UInt16(20))                 // version made by
            central.appendLE(UInt16(20))                 // version needed
            central.appendLE(utf8NameFlag)               // gp flag: bit 11 = UTF-8 names
            central.appendLE(UInt16(0))                  // method: stored
            central.appendLE(dosTimeZero)
            central.appendLE(dosDate1980)
            central.appendLE(record.crc)
            central.appendLE(UInt32(record.entry.data.count))
            central.appendLE(UInt32(record.entry.data.count))
            central.appendLE(UInt16(nameBytes.count))
            central.appendLE(UInt16(0))                  // extra length
            central.appendLE(UInt16(0))                  // comment length
            central.appendLE(UInt16(0))                  // disk number start
            central.appendLE(UInt16(0))                  // internal attrs
            central.appendLE(UInt32(0))                  // external attrs
            central.appendLE(record.offset)              // local header offset
            central.append(contentsOf: nameBytes)
        }
        output.append(central)
        guard let centralSize = UInt32(exactly: central.count) else {
            throw ZipError.unsupported("The archive's central directory exceeds ZIP's 4 GiB limit.")
        }

        // End of central directory
        output.appendLE(endOfCentralSig)
        output.appendLE(UInt16(0))                       // disk number
        output.appendLE(UInt16(0))                       // disk with CD start
        output.appendLE(entryCount)                      // CD records on this disk
        output.appendLE(entryCount)                      // total CD records
        output.appendLE(centralSize)                     // size of CD
        output.appendLE(centralStart)                    // offset of CD start
        output.appendLE(UInt16(0))                       // comment length
        return output
    }

    // MARK: - Reading

    /// Reads every entry, verifying structure and each entry's CRC-32. Strict by
    /// default: any corruption fails the whole read. `droppingCorruptEntriesWhere`
    /// names the entries whose own corruption (bad payload or CRC mismatch) merely
    /// drops them from the result instead — for best-effort content (e.g. the
    /// .luce recovery snapshots) that shouldn't block opening an intact document.
    public static func entries(from data: Data,
                               droppingCorruptEntriesWhere isDroppable: (String) -> Bool = { _ in false })
        throws -> [Entry] {
        let bytes = [UInt8](data)
        guard let eocd = findEndOfCentralDirectory(in: bytes) else { throw ZipError.notAZip }

        let total = Int(readLE16(bytes, eocd + 10))
        let cdOffset = readLE32(bytes, eocd + 16)        // offset of central directory
        // ZIP64 parks sentinel values in these EOCD fields and stores the real ones
        // in a separate record we don't parse. Detect the sentinels and fail with an
        // honest "unsupported" error rather than chasing 0xFFFFFFFF as a real offset
        // and reporting generic corruption (2.5).
        if total == 0xFFFF || cdOffset == 0xFFFF_FFFF {
            throw ZipError.unsupported("This archive uses ZIP64 extensions, which Lucerne can't open.")
        }
        var cursor = Int(cdOffset)

        var result: [Entry] = []
        for _ in 0 ..< total {
            guard cursor + 46 <= bytes.count, readLE32(bytes, cursor) == centralHeaderSig else {
                throw ZipError.corrupt("bad central directory header")
            }
            let method = readLE16(bytes, cursor + 10)
            let crc = readLE32(bytes, cursor + 16)
            let compressedSize = Int(readLE32(bytes, cursor + 20))
            let uncompressedSize = Int(readLE32(bytes, cursor + 24))
            let nameLen = Int(readLE16(bytes, cursor + 28))
            let extraLen = Int(readLE16(bytes, cursor + 30))
            let commentLen = Int(readLE16(bytes, cursor + 32))
            let localOffset = Int(readLE32(bytes, cursor + 42))
            // The variable-length tail (name + extra + comment) must also fit; the
            // declared lengths come from the file and can't be trusted.
            let recordEnd = cursor + 46 + nameLen + extraLen + commentLen
            guard recordEnd <= bytes.count else {
                throw ZipError.corrupt("central directory entry overruns the file")
            }
            let name = String(decoding: bytes[cursor + 46 ..< cursor + 46 + nameLen], as: UTF8.self)
            cursor = recordEnd

            do {
                let payload = try readLocalEntry(bytes, localOffset: localOffset,
                                                 method: method,
                                                 compressedSize: compressedSize,
                                                 uncompressedSize: uncompressedSize)
                // The central directory always carries the entry's CRC-32; checking
                // it catches truncation and bit rot the structure checks can't.
                if CRC32.checksum(payload) != crc {
                    throw ZipError.corrupt("CRC mismatch for \(name)")
                }
                result.append(Entry(name: name, data: payload))
            } catch {
                // Damage confined to a droppable entry's own payload skips just
                // that entry; the central-directory walk above stays strict.
                if isDroppable(name) { continue }
                throw error
            }
        }
        return result
    }

    private static func readLocalEntry(_ bytes: [UInt8], localOffset: Int, method: UInt16,
                                       compressedSize: Int, uncompressedSize: Int) throws -> Data {
        guard localOffset >= 0, localOffset + 30 <= bytes.count,
              readLE32(bytes, localOffset) == localHeaderSig else {
            throw ZipError.corrupt("bad local header")
        }
        guard compressedSize >= 0, uncompressedSize >= 0,
              compressedSize <= maxEntrySize, uncompressedSize <= maxEntrySize else {
            throw ZipError.corrupt("entry size out of bounds")
        }
        let nameLen = Int(readLE16(bytes, localOffset + 26))
        let extraLen = Int(readLE16(bytes, localOffset + 28))
        let dataStart = localOffset + 30 + nameLen + extraLen
        guard dataStart + compressedSize <= bytes.count else {
            throw ZipError.corrupt("entry data out of bounds")
        }
        let compressed = Data(bytes[dataStart ..< dataStart + compressedSize])

        switch method {
        case 0:
            return compressed
        case 8:
            guard let inflated = inflateRawDeflate(compressed, expectedSize: uncompressedSize) else {
                throw ZipError.corrupt("deflate decode failed")
            }
            return inflated
        default:
            throw ZipError.unsupported("compression method \(method)")
        }
    }

    private static func findEndOfCentralDirectory(in bytes: [UInt8]) -> Int? {
        guard bytes.count >= 22 else { return nil }
        // EOCD is at the end, with an optional comment (≤ 65535). Search backwards.
        let minStart = max(0, bytes.count - 22 - 0xffff)
        var i = bytes.count - 22
        while i >= minStart {
            if readLE32(bytes, i) == endOfCentralSig {
                let commentLength = Int(readLE16(bytes, i + 20))
                if i + 22 + commentLength == bytes.count { return i }
            }
            i -= 1
        }
        return nil
    }

    private static func inflateRawDeflate(_ input: Data, expectedSize: Int) -> Data? {
        if expectedSize == 0 { return Data() }
        guard !input.isEmpty else { return nil }
        var output = Data(count: expectedSize)
        let written = output.withUnsafeMutableBytes { (dst: UnsafeMutableRawBufferPointer) -> Int in
            input.withUnsafeBytes { (src: UnsafeRawBufferPointer) -> Int in
                guard let dstBase = dst.bindMemory(to: UInt8.self).baseAddress,
                      let srcBase = src.bindMemory(to: UInt8.self).baseAddress else { return 0 }
                return compression_decode_buffer(dstBase, expectedSize,
                                                 srcBase, input.count,
                                                 nil, COMPRESSION_ZLIB)
            }
        }
        return written == expectedSize ? output : nil
    }

    // MARK: - Little-endian readers

    private static func readLE16(_ bytes: [UInt8], _ offset: Int) -> UInt16 {
        UInt16(bytes[offset]) | (UInt16(bytes[offset + 1]) << 8)
    }
    private static func readLE32(_ bytes: [UInt8], _ offset: Int) -> UInt32 {
        UInt32(bytes[offset]) | (UInt32(bytes[offset + 1]) << 8)
            | (UInt32(bytes[offset + 2]) << 16) | (UInt32(bytes[offset + 3]) << 24)
    }
}

// Surface the associated message so `NSAlert(error:)` shows real text instead of a
// generic "operation couldn't be completed" (2.5).
extension MiniZip.ZipError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .notAZip:                 return "The file is not a valid .luce archive."
        case .corrupt(let message):    return message
        case .unsupported(let message): return message
        }
    }
}

// MARK: - Little-endian writers

private extension Data {
    mutating func appendLE(_ value: UInt16) {
        append(UInt8(value & 0xff))
        append(UInt8((value >> 8) & 0xff))
    }
    mutating func appendLE(_ value: UInt32) {
        append(UInt8(value & 0xff))
        append(UInt8((value >> 8) & 0xff))
        append(UInt8((value >> 16) & 0xff))
        append(UInt8((value >> 24) & 0xff))
    }
}

// MARK: - CRC-32 (IEEE 802.3, polynomial 0xEDB88320)

enum CRC32 {
    private static let table: [UInt32] = {
        (0 ..< 256).map { i -> UInt32 in
            var c = UInt32(i)
            for _ in 0 ..< 8 {
                c = (c & 1) != 0 ? (0xEDB8_8320 ^ (c >> 1)) : (c >> 1)
            }
            return c
        }
    }()

    static func checksum(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xffff_ffff
        for byte in data {
            crc = table[Int((crc ^ UInt32(byte)) & 0xff)] ^ (crc >> 8)
        }
        return crc ^ 0xffff_ffff
    }
}
