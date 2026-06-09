import XCTest
@testable import LucerneKit

/// Forward-compatibility and archive-content safety for the .luce format: a file
/// from a *newer* Lucerne must be refused loudly (decoding it would silently drop
/// fields and the next save would destroy them), and hostile entry names inside
/// the archive must not be accepted as image sources.
final class FormatSafetyTests: XCTestCase {

    private func makeModel() -> LucerneDocumentModel {
        DefaultDocuments.empty()
    }

    // MARK: - formatVersion guard

    func testCurrentFormatVersionRoundTrips() throws {
        let model = makeModel()
        let decoded = try DocumentCoding.decode(try DocumentCoding.encode(model))
        XCTAssertEqual(decoded, model)
    }

    func testFutureFormatVersionIsRefused() throws {
        var model = makeModel()
        model.formatVersion = LucerneDocumentModel.currentFormatVersion + 1
        let data = try DocumentCoding.encode(model)
        XCTAssertThrowsError(try DocumentCoding.decode(data)) { error in
            guard case DocumentCoding.DocumentError.formatTooNew(let found, let supported) = error else {
                return XCTFail("expected formatTooNew, got \(error)")
            }
            XCTAssertEqual(found, LucerneDocumentModel.currentFormatVersion + 1)
            XCTAssertEqual(supported, LucerneDocumentModel.currentFormatVersion)
        }
    }

    func testOlderFormatVersionStillDecodes() throws {
        // Version 0 (or any past version) must keep opening; only the future is refused.
        var model = makeModel()
        model.formatVersion = 0
        XCTAssertNoThrow(try DocumentCoding.decode(try DocumentCoding.encode(model)))
    }

    // MARK: - Archive image-name validation

    func testTraversalImageNamesAreIgnoredOnRead() throws {
        let documentJSON = try DocumentCoding.encode(makeModel())
        let archive = MiniZip.archive([
            MiniZip.Entry(name: LuceArchive.documentEntryName, data: documentJSON),
            MiniZip.Entry(name: "images/lake.png", data: Data([1, 2, 3])),
            MiniZip.Entry(name: "images/../../escape.png", data: Data([4, 5, 6])),
            MiniZip.Entry(name: "images/nested/dir.png", data: Data([7, 8, 9]))
        ])
        let contents = try LuceArchive.read(archive)
        XCTAssertEqual(contents.images.keys.sorted(), ["images/lake.png"],
                       "only flat images/<file> names may be accepted")
    }
}
