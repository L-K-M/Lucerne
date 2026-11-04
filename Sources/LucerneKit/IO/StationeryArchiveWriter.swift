import Foundation

/// Persists a stationery archive without exposing a partially written template.
/// Foundation writes a sibling temporary file and renames it over the destination.
enum StationeryArchiveWriter {
    static func write(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: .atomic)
    }
}
