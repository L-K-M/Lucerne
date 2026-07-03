import XCTest
@testable import LucerneKit

// Regression tests for the style-library robustness work (fable-is-awesome.md
// 1.11, 3.4): a corrupt or future-versioned `styles.json` must never be
// silently clobbered by the read-modify-write mutators, a missing file stays a
// clean empty library, and the in-memory cache serves saved values without
// re-reading disk.
final class StyleLibraryRobustnessTests: XCTestCase {

    private func temporaryLibrary() -> StyleLibrary {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("styles.json")
        return StyleLibrary(fileURL: url)
    }

    private func writeFile(_ contents: String, to library: StyleLibrary) throws {
        try FileManager.default.createDirectory(
            at: library.fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(contents.utf8).write(to: library.fileURL)
    }

    func testMissingFileIsNotAFailure() {
        let library = temporaryLibrary()
        XCTAssertTrue(library.load().isEmpty)
        XCTAssertEqual(library.loadFailure, .none)
    }

    func testCorruptFileFlagsFailureAndRefusesToClobber() throws {
        let library = temporaryLibrary()
        let corrupt = "definitely { not json"
        try writeFile(corrupt, to: library)

        XCTAssertTrue(library.load().isEmpty)
        XCTAssertEqual(library.loadFailure, .undecodable)

        // A destructive write on top of the swallowed failure would have
        // overwritten the real file — it must refuse instead.
        library.save(["body": ParagraphStyleDef(name: "Body", order: 0, markdown: "p")])
        XCTAssertEqual(try String(contentsOf: library.fileURL, encoding: .utf8), corrupt)
        library.saveStyle(ParagraphStyleDef(name: "X", markdown: "p"), forKey: "x")
        XCTAssertEqual(try String(contentsOf: library.fileURL, encoding: .utf8), corrupt)
    }

    func testFutureVersionSurvivesAnOlderBuild() throws {
        let library = temporaryLibrary()
        let future = #"{ "format": "lucerne-styles", "formatVersion": 99, "styles": {} }"#
        try writeFile(future, to: library)

        XCTAssertTrue(library.load().isEmpty)
        XCTAssertEqual(library.loadFailure, .undecodable)

        library.save(["body": ParagraphStyleDef(name: "Body", order: 0, markdown: "p")])
        XCTAssertEqual(try String(contentsOf: library.fileURL, encoding: .utf8), future,
                       "a library written by a newer Lucerne must not be rewritten wholesale")
    }

    func testDeletingBrokenFileRestoresACleanEmptyLibrary() throws {
        let library = temporaryLibrary()
        try writeFile("nonsense", to: library)
        _ = library.load()
        XCTAssertEqual(library.loadFailure, .undecodable)

        // Removing styles.json is the documented escape hatch; it must lift the
        // failure state (missing file, nil mtime) so writes are allowed again.
        try FileManager.default.removeItem(at: library.fileURL)
        XCTAssertTrue(library.load().isEmpty)
        XCTAssertEqual(library.loadFailure, .none)

        library.save(["body": ParagraphStyleDef(name: "Body", order: 0, markdown: "p")])
        XCTAssertEqual(library.loadFailure, .none)
        XCTAssertEqual(library.load()["body"]?.name, "Body")
    }

    func testSaveKeepsCacheInStepAndClearsFailure() {
        let library = temporaryLibrary()
        let styles = ["legal": ParagraphStyleDef(name: "Legalese", size: 9, order: 0, markdown: "p")]
        library.save(styles)
        XCTAssertEqual(library.loadFailure, .none)
        // Both reads are served from the in-memory cache (3.4); they must still
        // reflect exactly what save() wrote.
        XCTAssertEqual(library.load(), styles)
        XCTAssertEqual(library.load(), styles)
    }
}
