import Foundation

// Centralised JSON encode/decode for the canonical model so every call site uses
// the same, stable settings:
//   • prettyPrinted + sortedKeys → human-readable, diff-friendly document.json
//   • withoutEscapingSlashes      → "images/lake.png" stays legible, not "images\/lake.png"
public enum DocumentCoding {

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
        try makeDecoder().decode(LucerneDocumentModel.self, from: data)
    }
}
