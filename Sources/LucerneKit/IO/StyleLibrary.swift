import Foundation

// The app-global style library (STYLES.md S6): a plain JSON file under
// Application Support, in the same dialect as a document's `styles` block. It
// participates at exactly three moments — seeding a new document, an explicit
// import into a document, an explicit save out of one — and is never *referenced*
// by a document (copy-on-use, S2), so every .luce file stays self-contained.
//
// The same file shape doubles as the Import/Export Stylesheet interchange format.
// Missing or corrupt files degrade silently to "no library" (built-in defaults
// alone). Foundation-only so it is unit-testable headlessly.
public final class StyleLibrary {

    /// Posted after the library file is rewritten, so open windows (the Style
    /// Library window, the styles palette) can refresh.
    public static let didChange = Notification.Name("ch.lkmc.lucerne.styleLibraryDidChange")

    public static let canonicalFormat = "lucerne-styles"
    public static let currentFormatVersion = 1

    public static let shared = StyleLibrary()

    /// The interchange shape: `{ "format": "lucerne-styles", "formatVersion": 1,
    /// "styles": { key: definition } }`.
    public struct File: Codable, Equatable {
        public var format: String
        public var formatVersion: Int
        public var styles: [String: ParagraphStyleDef]

        public init(styles: [String: ParagraphStyleDef]) {
            self.format = StyleLibrary.canonicalFormat
            self.formatVersion = StyleLibrary.currentFormatVersion
            self.styles = styles
        }
    }

    /// Where this library lives. Injectable for tests; defaults to
    /// `~/Library/Application Support/Lucerne/styles.json`.
    public let fileURL: URL

    public init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? StyleLibrary.defaultFileURL()
    }

    private static func defaultFileURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("Lucerne", isDirectory: true)
            .appendingPathComponent("styles.json", isDirectory: false)
    }

    // MARK: - Load / save

    /// The library's styles. Read on demand; a missing or undecodable file is an
    /// empty library (the built-in defaults rule alone).
    public func load() -> [String: ParagraphStyleDef] {
        guard let data = try? Data(contentsOf: fileURL) else { return [:] }
        return (try? StyleLibrary.decode(data)) ?? [:]
    }

    /// Rewrites the library file (atomically) and posts `didChange`.
    public func save(_ styles: [String: ParagraphStyleDef]) {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try StyleLibrary.encode(styles).write(to: fileURL, options: .atomic)
            NotificationCenter.default.post(name: StyleLibrary.didChange, object: self)
        } catch {
            // A preferences-grade file: failing to persist must never take the
            // app down. The next save retries.
            NSLog("Lucerne: could not write style library: \(error)")
        }
    }

    /// Adds or updates one style. The library's existing `order` for the key is
    /// kept (pushing a definition shouldn't reshuffle the library); a brand-new
    /// entry goes to the end.
    public func saveStyle(_ def: ParagraphStyleDef, forKey key: String) {
        var library = load()
        var merged = def
        if let existingOrder = library[key]?.order {
            merged.order = existingOrder
        } else if merged.order == nil {
            merged.order = (library.values.compactMap(\.order).max()
                ?? Double(library.count - 1)) + 1
        }
        library[key] = merged
        save(library)
    }

    public func removeStyle(forKey key: String) {
        var library = load()
        guard library.removeValue(forKey: key) != nil else { return }
        save(library)
    }

    // MARK: - Seeding new documents (S6)

    /// The stylesheet a new document starts with: the built-in defaults overlaid
    /// by the library — the library wins on key collisions, so redefining `body`
    /// there restyles all future letters. Existing documents are never touched.
    public func seededStyles(base: [String: ParagraphStyleDef]
                                = DefaultDocuments.defaultStyles()) -> [String: ParagraphStyleDef] {
        StyleLibrary.overlay(base: base, library: load())
    }

    public static func overlay(base: [String: ParagraphStyleDef],
                               library: [String: ParagraphStyleDef]) -> [String: ParagraphStyleDef] {
        var merged = base
        for (key, def) in library { merged[key] = def }
        return merged
    }

    // MARK: - Interchange (Import / Export Stylesheet…)

    public static func encode(_ styles: [String: ParagraphStyleDef]) throws -> Data {
        try DocumentCoding.makeEncoder().encode(File(styles: styles))
    }

    public static func decode(_ data: Data) throws -> [String: ParagraphStyleDef] {
        let file = try JSONDecoder().decode(File.self, from: data)
        guard file.format == canonicalFormat else { throw CocoaError(.fileReadCorruptFile) }
        guard file.formatVersion <= currentFormatVersion else {
            throw CocoaError(.fileReadUnsupportedScheme)
        }
        return file.styles
    }

    // MARK: - Document ↔ library relationship (the editor's strip, STYLES.md §6.4)

    public enum SyncState: Equatable {
        case notInLibrary   // the key has no library entry
        case matches        // visually identical definitions
        case differs        // same key, different look
    }

    /// Compared *visually* (`order` ignored): reordering a list must not read as
    /// "differs from your Library".
    public static func syncState(documentDef: ParagraphStyleDef,
                                 libraryDef: ParagraphStyleDef?) -> SyncState {
        guard let libraryDef else { return .notInLibrary }
        return documentDef.visuallyEquals(libraryDef) ? .matches : .differs
    }
}
