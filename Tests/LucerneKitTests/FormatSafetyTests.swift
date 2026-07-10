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

    // MARK: - Post-decode semantic validation

    func testNegativePageAnchoredObjectPageIsRefused() throws {
        var model = makeModel()
        model.objects = [PlacedObject(id: "negative-page", page: -1,
                                      frame: RectModel(x: 0, y: 0, width: 10, height: 10))]

        XCTAssertThrowsError(try DocumentCoding.decode(try DocumentCoding.encode(model))) { error in
            guard case DocumentCoding.DocumentError.invalidObjectPage(let id, let found) = error else {
                return XCTFail("expected invalidObjectPage, got \(error)")
            }
            XCTAssertEqual(id, "negative-page")
            XCTAssertEqual(found, -1)
            XCTAssertTrue(error.localizedDescription.contains("between 0 and 1999"))
        }
    }

    func testExtremePageAnchoredObjectPageIsRefused() throws {
        var model = makeModel()
        model.objects = [PlacedObject(id: "extreme-page", page: Int.max,
                                      frame: RectModel(x: 0, y: 0, width: 10, height: 10))]

        XCTAssertThrowsError(try DocumentCoding.decode(try DocumentCoding.encode(model))) { error in
            guard case DocumentCoding.DocumentError.invalidObjectPage(let id, let found) = error else {
                return XCTFail("expected invalidObjectPage, got \(error)")
            }
            XCTAssertEqual(id, "extreme-page")
            XCTAssertEqual(found, Int.max)
        }
    }

    func testExtremeListLevelIsRefused() throws {
        var model = makeModel()
        model.body[0].list = ListItemModel(list: "list-1", ordered: false,
                                          marker: "disc", level: Int.max)

        XCTAssertThrowsError(try DocumentCoding.decode(try DocumentCoding.encode(model))) { error in
            guard case DocumentCoding.DocumentError.invalidListLevel(let id, let found) = error else {
                return XCTFail("expected invalidListLevel, got \(error)")
            }
            XCTAssertEqual(id, model.body[0].id)
            XCTAssertEqual(found, Int.max)
            XCTAssertTrue(error.localizedDescription.contains("between 0 and 8"))
        }
    }

    func testMaximumPageAndListLevelDecode() throws {
        var model = makeModel()
        model.objects = [PlacedObject(
            id: "last-page", page: LucerneDocumentModel.maximumPageCount - 1,
            frame: RectModel(x: 0, y: 0, width: 10, height: 10))]
        model.body[0].list = ListItemModel(list: "list-1", ordered: false,
                                          marker: "disc", level: ListGeometry.maximumLevel)

        let decoded = try DocumentCoding.decode(try DocumentCoding.encode(model))
        XCTAssertEqual(decoded.objects[0].page, 1999)
        XCTAssertEqual(decoded.body[0].list?.level, 8)
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
