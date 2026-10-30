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
        case invalidImageSource(String)
    }

    /// True for a safe, flat archive entry name under `images/` ("images/lake.png").
    public static func isFlatImageName(_ name: String) -> Bool {
        let filename = (name as NSString).lastPathComponent
        return !filename.isEmpty && filename != "." && filename != ".."
            && name == imagesPrefix + filename
    }

    // MARK: - Write

    public static func write(model: LucerneDocumentModel, images: [String: Data],
                              history: [HistorySnapshot] = []) throws -> Data {
        var entries: [MiniZip.Entry] = []

        // Entry names go into the ZIP verbatim, so a model `src` that isn't a flat
        // "images/<file>" name (traversal, absolute path, "document.json") must not
        // be written as-is. Normalize such sources to "images/<basename>" — the
        // payload is preserved, the archive stays safe — and refuse when that
        // isn't possible (empty basename or a collision).
        var model = model
        var images = images
        var renamed: [String: String] = [:]
        for object in model.objects {
            guard object.type == "image", let src = object.src, !isFlatImageName(src) else { continue }
            let filename = (src as NSString).lastPathComponent
            let newName = imagesPrefix + filename
            guard isFlatImageName(newName) else {
                throw ArchiveError.invalidImageSource(src)
            }
            guard renamed[src] == nil || renamed[src] == newName else {
                throw ArchiveError.invalidImageSource(src)
            }
            if let existing = renamed.first(where: { $0.value == newName && $0.key != src }) {
                throw ArchiveError.invalidImageSource(
                    "\(src) and \(existing.key) would both map to \(newName)")
            }
            renamed[src] = newName
        }
        if !renamed.isEmpty {
            for index in model.objects.indices {
                if let src = model.objects[index].src, let newName = renamed[src] {
                    model.objects[index].src = newName
                }
            }
            var moved: [String: Data] = [:]
            for (key, value) in images {
                moved[renamed[key] ?? key] = value
            }
            images = moved
        }

        let documentJSON = try DocumentCoding.encode(model)
        entries.append(MiniZip.Entry(name: documentEntryName, data: documentJSON))

        // Only include images actually referenced by the model, in a stable order.
        let referenced = referencedImageSources(in: model)
        for src in referenced.sorted() {
            // A referenced image with no bytes would write a document.json that points
            // at a picture the archive doesn't contain — a silent, unopenable-picture
            // save. Refuse with a clear error instead of dropping it (2.6).
            guard let data = images[src] else {
                throw NSError(domain: NSCocoaErrorDomain, code: NSFileWriteUnknownError, userInfo: [
                    NSLocalizedDescriptionKey:
                        "Can't save the document because a referenced image is missing (\(src))."
                ])
            }
            entries.append(MiniZip.Entry(name: src, data: data))
        }

        let markdown = MarkdownExporter.export(model)
        entries.append(MiniZip.Entry(name: markdownEntryName, data: Data(markdown.utf8)))

        // Dated Markdown backups (oldest→newest), tiny plain-text recovery trail.
        for snapshot in history.sorted(by: { $0.timestamp < $1.timestamp }) {
            entries.append(MiniZip.Entry(name: HistoryPruner.entryName(for: snapshot.timestamp),
                                         data: Data(snapshot.markdown.utf8)))
        }

        return try MiniZip.archive(entries, maxEntrySize: MiniZip.maxEntrySize)
    }

    // MARK: - Read

    public static func read(_ data: Data) throws -> Contents {
        // Strict integrity for the authoritative content (document.json, images/);
        // a bit-rotted recovery entry (content.md, history/*) is dropped rather
        // than blocking the whole document — those exist for best-effort recovery.
        let entries = try MiniZip.entries(from: data, droppingCorruptEntriesWhere: { name in
            name != documentEntryName && !name.hasPrefix(imagesPrefix)
        })

        guard let documentEntry = entries.first(where: { $0.name == documentEntryName }) else {
            throw ArchiveError.missingDocument
        }
        let model = try DocumentCoding.decode(documentEntry.data)

        var images: [String: Data] = [:]
        for entry in entries where !entry.name.hasSuffix("/") {
            // Accept only flat, well-formed names ("images/<file>"). Today these
            // names are just dictionary keys, but a hostile archive could carry
            // "images/../../x" — reject the zip-slip shape now so a future
            // "extract images" feature can't be caught out by it.
            let filename = (entry.name as NSString).lastPathComponent
            guard !filename.isEmpty, entry.name == imagesPrefix + filename else { continue }
            images[entry.name] = entry.data
        }
        // The spec only requires `src` to name an archive entry — "images/" is a
        // convention — so also collect payloads for referenced sources outside
        // images/ (exact name match; the names are dictionary keys, never paths
        // we extract to). This keeps third-party files with e.g. src
        // "pictures/a.png" loadable instead of unsavable.
        let referenced = referencedImageSources(in: model)
        for entry in entries where !entry.name.hasSuffix("/") {
            if referenced.contains(entry.name) {
                images[entry.name] = entry.data
            }
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

extension LuceArchive.ArchiveError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .missingDocument:
            return "The archive does not contain a document.json."
        case .invalidImageSource(let src):
            return "A placed image names an unusable archive entry (\"\(src)\"). "
                + "Images must be stored as flat files under images/."
        }
    }
}
