import Foundation

// Reads and writes the .luce package (D3/D4): a ZIP containing document.json (the
// canonical model), the loose image files under images/, and a derived content.md
// escape hatch. content.md is regenerated on every write and never read back.
public enum LuceArchive {

    public static let documentEntryName = "document.json"
    public static let markdownEntryName = "content.md"
    public static let imagesPrefix = "images/"

    public struct Contents {
        public var model: LucerneDocumentModel
        public var images: [String: Data]      // keyed by src path, e.g. "images/lake.png"
        public init(model: LucerneDocumentModel, images: [String: Data]) {
            self.model = model
            self.images = images
        }
    }

    public enum ArchiveError: Error {
        case missingDocument
    }

    // MARK: - Write

    public static func write(model: LucerneDocumentModel, images: [String: Data]) throws -> Data {
        var entries: [MiniZip.Entry] = []

        let documentJSON = try DocumentCoding.encode(model)
        entries.append(MiniZip.Entry(name: documentEntryName, data: documentJSON))

        // Only include images actually referenced by the model, in a stable order.
        let referenced = referencedImageSources(in: model)
        for src in referenced.sorted() {
            guard let data = images[src] else { continue }
            entries.append(MiniZip.Entry(name: src, data: data))
        }

        let markdown = MarkdownExporter.export(model)
        entries.append(MiniZip.Entry(name: markdownEntryName, data: Data(markdown.utf8)))

        return MiniZip.archive(entries)
    }

    // MARK: - Read

    public static func read(_ data: Data) throws -> Contents {
        let entries = try MiniZip.entries(from: data)

        guard let documentEntry = entries.first(where: { $0.name == documentEntryName }) else {
            throw ArchiveError.missingDocument
        }
        let model = try DocumentCoding.decode(documentEntry.data)

        var images: [String: Data] = [:]
        for entry in entries where entry.name.hasPrefix(imagesPrefix) && !entry.name.hasSuffix("/") {
            images[entry.name] = entry.data
        }
        return Contents(model: model, images: images)
    }

    // MARK: -

    private static func referencedImageSources(in model: LucerneDocumentModel) -> Set<String> {
        Set(model.objects.compactMap { $0.type == "image" ? $0.src : nil })
    }
}
