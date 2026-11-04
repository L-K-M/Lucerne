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
        /// A page-anchored object names a page the editor cannot create.
        case invalidObjectPage(objectID: String, found: Int)
        /// A list item names a nesting level outside the editor's supported geometry.
        case invalidListLevel(paragraphID: String, found: Int)
        /// Page size or margins are not finite/positive, so the text container
        /// would get an infinite or negative size.
        case invalidPageGeometry
        /// A placed object's frame is not finite or has a negative extent, so the
        /// exclusion rect would be negative or infinite.
        case invalidObjectFrame(objectID: String)
        /// A table cell's coordinates/spans are negative, zero, or so large that
        /// grid math would overflow or allocate an absurd GFM grid.
        case invalidTableCell(paragraphID: String)

        public var errorDescription: String? {
            switch self {
            case let .formatTooNew(found, supported):
                return "This document was saved by a newer version of Lucerne "
                    + "(format \(found); this app reads up to \(supported)). "
                    + "Please update Lucerne to open it."
            case let .wrongFormat(found):
                return "This is not a Lucerne document (its format is "
                    + "\"\(found)\", expected \"\(LucerneDocumentModel.canonicalFormat)\")."
            case let .invalidObjectPage(objectID, found):
                return "Placed object \"\(objectID)\" has page index \(found); "
                    + "page indexes must be between 0 and "
                    + "\(LucerneDocumentModel.maximumPageCount - 1)."
            case let .invalidListLevel(paragraphID, found):
                return "Paragraph \"\(paragraphID)\" has list level \(found); "
                    + "list levels must be between 0 and \(ListGeometry.maximumLevel)."
            case .invalidPageGeometry:
                return "The page size or margins are not finite, positive values."
            case let .invalidObjectFrame(objectID):
                return "Placed object \"\(objectID)\" has a frame that is not "
                    + "finite or has a negative extent."
            case let .invalidTableCell(paragraphID):
                return "Paragraph \"\(paragraphID)\" is a table cell whose row, "
                    + "column, or spans are out of range (0..<\(TableGeometry.maximumExtent))."
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
        let model = try makeDecoder().decode(LucerneDocumentModel.self, from: data)
        try validateSemantics(of: model)
        return model
    }

    /// Codable verifies representation and types, but not values whose validity
    /// depends on editor constraints. Keep those checks at the canonical decode
    /// boundary so malformed files fail before layout or view indexing begins.
    private static func validateSemantics(of model: LucerneDocumentModel) throws {
        let page = model.page
        guard page.width.isFinite, page.height.isFinite,
              page.width > 0, page.height > 0,
              page.width <= TableGeometry.maximumPageDimension,
              page.height <= TableGeometry.maximumPageDimension,
              page.margins.top.isFinite, page.margins.left.isFinite,
              page.margins.bottom.isFinite, page.margins.right.isFinite,
              page.margins.top >= 0, page.margins.left >= 0,
              page.margins.bottom >= 0, page.margins.right >= 0,
              page.margins.left + page.margins.right < page.width,
              page.margins.top + page.margins.bottom < page.height else {
            throw DocumentError.invalidPageGeometry
        }
        for object in model.objects {
            // Frame/standoff geometry is validated for every anchor mode, not
            // just page-anchored objects — an inline object with a huge frame
            // reaches the same layout code.
            if let frame = object.frame {
                guard frame.x.isFinite, frame.y.isFinite,
                      abs(frame.x) <= TableGeometry.maximumPageDimension,
                      abs(frame.y) <= TableGeometry.maximumPageDimension,
                      frame.width.isFinite, frame.height.isFinite,
                      frame.width >= 0, frame.height >= 0,
                      frame.width <= TableGeometry.maximumPageDimension,
                      frame.height <= TableGeometry.maximumPageDimension else {
                    throw DocumentError.invalidObjectFrame(objectID: object.id)
                }
            }
            guard object.standoff.isFinite, object.standoff >= 0,
                  object.standoff <= TableGeometry.maximumPageDimension else {
                throw DocumentError.invalidObjectFrame(objectID: object.id)
            }
            guard object.anchorMode == .page else { continue }
            guard let page = object.page else { continue }
            guard (0..<LucerneDocumentModel.maximumPageCount).contains(page) else {
                throw DocumentError.invalidObjectPage(objectID: object.id, found: page)
            }
        }
        for paragraph in model.body {
            guard let level = paragraph.list?.level else { continue }
            guard ListGeometry.validLevels.contains(level) else {
                throw DocumentError.invalidListLevel(paragraphID: paragraph.id, found: level)
            }
        }
        for paragraph in model.body {
            guard let cell = paragraph.cell else { continue }
            guard TableGeometry.isValidCell(cell) else {
                throw DocumentError.invalidTableCell(paragraphID: paragraph.id)
            }
        }
    }
}
