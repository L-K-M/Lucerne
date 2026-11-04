import XCTest
@testable import LucerneKit

final class StationeryArchiveWriterTests: XCTestCase {

    func testReplacingExistingStationeryUsesAtomicRename() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory,
                                                withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let destination = directory.appendingPathComponent("Letter.luce")
        let originalLink = directory.appendingPathComponent("Original.luce")
        try Data("old stationery".utf8).write(to: destination)
        try FileManager.default.linkItem(at: destination, to: originalLink)

        try StationeryArchiveWriter.write(Data("new stationery".utf8), to: destination)

        XCTAssertEqual(try Data(contentsOf: destination), Data("new stationery".utf8))
        XCTAssertEqual(try Data(contentsOf: originalLink), Data("old stationery".utf8),
                       "an in-place write mutates both hard links; atomic replacement must not")
    }
}
