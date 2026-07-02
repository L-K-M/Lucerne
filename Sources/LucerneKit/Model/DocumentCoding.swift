import Foundation

// Centralised JSON encode/decode for the canonical model so every call site uses
// the same, stable settings:
//   • prettyPrinted + sortedKeys → human-readable, diff-friendly document.json
//   • withoutEscapingSlashes      → "images/lake.png" stays legible, not "images\/lake.png"
public enum DocumentCoding {

    public enum DocumentError: LocalizedError {
        /// The file's `formatVersion` is newer than this app understands. Refusing
        /// is the safe move: decoding would silently drop the fields the newer
        /// format added, and the next save would destroy them.
        case formatTooNew(found: Int, supported: Int)
        /// The file's `format` marker names something other than a Lucerne
        /// document. The spec (§3.1) says a reader MUST reject such a file.
        case wrongFormat(found: String)

        public var errorDescription: String? {
            switch self {
            case let .formatTooNew(found, supported):
                return "This document was saved by a newer version of Lucerne "
                    + "(format \(found); this app reads up to \(supported)). "
                    + "Please update Lucerne to open it."
            case let .wrongFormat(found):
                return "This is not a Lucerne document (its format is "
                    + "\"\(found)\", expected \"\(LucerneDocumentModel.canonicalFormat)\")."
            }
        }
    }

    /// The minimal slice of document.json needed to vet the format and version
    /// before the full (and forgiving) decode runs.
    private struct VersionProbe: Decodable {
        var format: String?
        var formatVersion: Int?
    }

    public static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    public static func makeDecoder() -> JSONDecoder {
        JSONDecoder()
    }

    public static func encode(_ model: LucerneDocumentModel) throws -> Data {
        try makeEncoder().encode(model)
    }

    public static func decode(_ data: Data) throws -> LucerneDocumentModel {
        // The plan (§7) says readers check formatVersion — do so before decoding,
        // so a future-versioned .luce fails loudly instead of silently shedding
        // the fields it carries that this app doesn't know about.
        let probe = try makeDecoder().decode(VersionProbe.self, from: data)
        // Spec §3.1: a reader MUST reject a file whose `format` is not
        // "lucerne-document" — some other tool's JSON is not our document.
        if let format = probe.format, format != LucerneDocumentModel.canonicalFormat {
            throw DocumentError.wrongFormat(found: format)
        }
        if let version = probe.formatVersion, version > LucerneDocumentModel.currentFormatVersion {
            throw DocumentError.formatTooNew(found: version,
                                             supported: LucerneDocumentModel.currentFormatVersion)
        }
        return try makeDecoder().decode(LucerneDocumentModel.self, from: data)
    }
}
