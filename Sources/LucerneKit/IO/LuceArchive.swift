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
        public var history: [HistorySnapshot]  // dated Markdown backups under history/
        public init(model: LucerneDocumentModel, images: [String: Data],
                    history: [HistorySnapshot] = []) {
            self.model = model
            self.images = images
            self.history = history
        }
    }

    public enum ArchiveError: Error {
        case missingDocument
    }

    // MARK: - Write

    public static func write(model: LucerneDocumentModel, images: [String: Data],
                             history: [HistorySnapshot] = []) throws -> Data {
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

        // Dated Markdown backups (oldest→newest), tiny plain-text recovery trail.
        for snapshot in history.sorted(by: { $0.timestamp < $1.timestamp }) {
            entries.append(MiniZip.Entry(name: HistoryPruner.entryName(for: snapshot.timestamp),
                                         data: Data(snapshot.markdown.utf8)))
        }

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
            // Accept only flat, well-formed names ("images/<file>"). Today these
            // names are just dictionary keys, but a hostile archive could carry
            // "images/../../x" — reject the zip-slip shape now so a future
            // "extract images" feature can't be caught out by it.
            let filename = (entry.name as NSString).lastPathComponent
            guard !filename.isEmpty, entry.name == imagesPrefix + filename else { continue }
            images[entry.name] = entry.data
        }

        var history: [HistorySnapshot] = []
        for entry in entries {
            guard let timestamp = HistoryPruner.timestamp(fromEntryName: entry.name) else { continue }
            history.append(HistorySnapshot(timestamp: timestamp,
                                           markdown: String(decoding: entry.data, as: UTF8.self)))
        }
        return Contents(model: model, images: images, history: history)
    }

    // MARK: -

    private static func referencedImageSources(in model: LucerneDocumentModel) -> Set<String> {
        Set(model.objects.compactMap { $0.type == "image" ? $0.src : nil })
    }
}
