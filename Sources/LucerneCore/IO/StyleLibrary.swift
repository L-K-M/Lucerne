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

    /// Posted when a save was refused or the write failed, with the underlying
    /// error (or refusal reason) under `error` in the userInfo. Saving must never
    /// report success when nothing was persisted.
    public static let didFailToSave = Notification.Name("ch.lkmc.lucerne.styleLibraryDidFailToSave")

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

    /// Why the last `load()` couldn't return the file's real contents. A missing
    /// file is *not* a failure — that's a legitimately empty library. But a file
    /// that exists and won't load (corrupt, or a newer `formatVersion` this build
    /// rejects on purpose, or transiently unreadable) must never be silently
    /// overwritten: every mutator is read-modify-write, so saving on top of a
    /// swallowed failure would clobber the real file (1.11). While this is
    /// non-`.none`, destructive writes refuse.
    public enum LoadFailure: Equatable {
        case none
        /// The file exists but couldn't be read (permissions, transient I/O).
        case unreadable
        /// The file exists but couldn't be decoded — corrupt JSON, wrong format,
        /// or a `formatVersion` newer than this build understands.
        case undecodable
    }

    /// All mutable state below is guarded by `stateLock`: the styles palette
    /// calls `load()` per caret move while the Style Library window mutates, and
    /// the read-modify-write mutators must be atomic so two windows can't lose
    /// an update.
    private let stateLock = NSLock()
    private var _loadFailure: LoadFailure = .none

    public private(set) var loadFailure: LoadFailure {
        get { stateLock.lock(); defer { stateLock.unlock() }; return _loadFailure }
        set { stateLock.lock(); defer { stateLock.unlock() }; _loadFailure = newValue }
    }

    /// In-memory cache keyed by the file's modification date (3.4): with the
    /// styles palette open, `load()` is called on the selection-change path (per
    /// caret move). Serving an unchanged file from memory kills that disk I/O
    /// while still honoring an external edit — a changed mtime re-reads.
    private var cache: [String: ParagraphStyleDef]?
    private var cacheModDate: Date?

    private func fileModificationDate() -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: fileURL.path))?[.modificationDate] as? Date
    }

    /// The library's styles. Read on demand; a missing file is an empty library
    /// (the built-in defaults rule alone). A file that exists but won't load is
    /// also reported as empty so the UI degrades gracefully, but it flips
    /// `loadFailure` so writes refuse rather than clobber it (1.11).
    public func load() -> [String: ParagraphStyleDef] {
        stateLock.lock()
        defer { stateLock.unlock() }
        return loadLocked()
    }

    private func loadLocked() -> [String: ParagraphStyleDef] {
        guard let modDate = fileModificationDate() else {
            // No file yet: a legitimately empty library, not a failure.
            _loadFailure = .none
            cache = [:]
            cacheModDate = nil
            return [:]
        }
        if let cache, cacheModDate == modDate { return cache }
        guard let data = try? Data(contentsOf: fileURL) else {
            return recordLoadFailure(.unreadable,
                "could not read style library at \(fileURL.path)", modDate: modDate)
        }
        do {
            let styles = try StyleLibrary.decode(data)
            cache = styles
            cacheModDate = modDate
            _loadFailure = .none
            return styles
        } catch {
            return recordLoadFailure(.undecodable,
                "could not decode style library at \(fileURL.path): \(error)", modDate: modDate)
        }
    }

    /// Enters a load-failure state: caches the empty result against this mtime so
    /// a corrupt file isn't re-read every caret move, and logs the reason once
    /// (only on the transition into a failure, not on every subsequent load).
    private func recordLoadFailure(_ failure: LoadFailure, _ reason: String,
                                    modDate: Date) -> [String: ParagraphStyleDef] {
        if _loadFailure != failure {
            NSLog("Lucerne: \(reason); refusing to overwrite it until it loads cleanly")
        }
        _loadFailure = failure
        cache = [:]
        cacheModDate = modDate
        return [:]
    }

    /// Rewrites the library file (atomically) and posts `didChange`. Returns
    /// false — and posts `didFailToSave` — when the write was refused (load
    /// failure on an existing file, so a corrupt or future-versioned library is
    /// never overwritten wholesale, 1.11) or failed, so callers never mistake a
    /// skipped save for a successful one.
    @discardableResult
    public func save(_ styles: [String: ParagraphStyleDef]) -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return saveLocked(styles)
    }

    private func saveLocked(_ styles: [String: ParagraphStyleDef]) -> Bool {
        guard _loadFailure == .none else {
            let reason = "refusing to overwrite the style library while it is "
                + "in a load-failure state (\(_loadFailure)); leaving it untouched"
            NSLog("Lucerne: \(reason)")
            NotificationCenter.default.post(name: StyleLibrary.didFailToSave, object: self,
                                            userInfo: ["error": reason])
            return false
        }
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try StyleLibrary.encode(styles).write(to: fileURL, options: .atomic)
            // Keep the cache in step with what we just wrote so the palette's
            // next selection-change sync serves memory, not disk (3.4).
            cache = styles
            cacheModDate = fileModificationDate()
            NotificationCenter.default.post(name: StyleLibrary.didChange, object: self)
            return true
        } catch {
            // A preferences-grade file: failing to persist must never take the
            // app down, but it must not pass silently either. The next save retries.
            NSLog("Lucerne: could not write style library: \(error)")
            NotificationCenter.default.post(name: StyleLibrary.didFailToSave, object: self,
                                            userInfo: ["error": error])
            return false
        }
    }

    /// Adds or updates one style. The library's existing `order` for the key is
    /// kept (pushing a definition shouldn't reshuffle the library); a brand-new
    /// entry goes to the end. Returns false when the change was not persisted.
    @discardableResult
    public func saveStyle(_ def: ParagraphStyleDef, forKey key: String) -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        var library = loadLocked()
        var merged = def
        if let existingOrder = library[key]?.order {
            merged.order = existingOrder
        } else if merged.order == nil {
            merged.order = (library.values.compactMap(\.order).max()
                ?? Double(library.count - 1)) + 1
        }
        library[key] = merged
        return saveLocked(library)
    }

    @discardableResult
    public func removeStyle(forKey key: String) -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        var library = loadLocked()
        guard library.removeValue(forKey: key) != nil else { return true }
        return saveLocked(library)
    }

    // MARK: - First run (S6): a starter collection instead of an empty shelf

    /// Seeds a brand-new library — **no file on disk yet** — with the curated
    /// starter collection, so the Style Library window's first impression is a
    /// stocked shelf, not an empty box. A library the user emptied by hand
    /// stays empty (its file exists), and — true to the escape hatch — deleting
    /// `styles.json` brings the starter set back. Call once at app launch,
    /// before any document is created.
    public func seedStarterLibraryIfNeeded() {
        guard !FileManager.default.fileExists(atPath: fileURL.path) else { return }
        // First-run seeding; if it fails (read-only disk), the next launch retries.
        _ = save(DefaultDocuments.starterLibraryStyles())
    }

    // MARK: - Seeding new documents (S6)

    /// The stylesheet a new document starts with — **exactly the library**:
    /// what the Style Library window shows (and the order it shows it in) is
    /// what a new letter gets, nothing mixed in behind the scenes. Two guard
    /// rails: an emptied or missing library falls back to the built-in
    /// defaults, and a library without `body` has it materialized from them
    /// (`body` is the format's fallback anchor). Existing documents are never
    /// touched.
    public func seededStyles(base: [String: ParagraphStyleDef]
                                = DefaultDocuments.defaultStyles()) -> [String: ParagraphStyleDef] {
        var library = load()
        guard !library.isEmpty else { return base }
        if library[LucerneDocumentModel.defaultStyleRole] == nil {
            var body = base[LucerneDocumentModel.defaultStyleRole] ?? .fallbackBody
            body.order = (library.values.compactMap(\.order).min() ?? 0) - 1
            library[LucerneDocumentModel.defaultStyleRole] = body
        }
        return library
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
