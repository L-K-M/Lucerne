import AppKit
import XCTest
@testable import LucerneKit

/// The AppKit half of the exclusion contract (the portable rect math is locked in
/// LucerneCoreTests/ExclusionRectsTests): `exclusionPaths` must stay derivable
/// one-NSBezierPath-per-rect from `exclusionRects`, because pagination's
/// dirty-check (review 3.1) diffs the rect lists before reassigning paths.
final class ExclusionPathsTests: XCTestCase {

    private let metrics = PageMetrics(page: .a4)

    private func object(id: String, page: Int?, z: Int = 0) -> PlacedObject {
        PlacedObject(id: id, page: page,
                     frame: RectModel(x: 200, y: 200, width: 100, height: 80),
                     wrap: "rectangular", standoff: 12, z: z)
    }

    func testPathsAreOnePerRect() {
        let objects = [object(id: "a", page: 0, z: 2), object(id: "b", page: 0, z: 1)]
        let rects = ExclusionPathController.exclusionRects(forPage: 0, objects: objects, metrics: metrics)
        let paths = ExclusionPathController.exclusionPaths(forPage: 0, objects: objects, metrics: metrics)
        XCTAssertEqual(rects.count, 2)
        XCTAssertEqual(paths.count, rects.count)
        for (rect, path) in zip(rects, paths) {
            XCTAssertEqual(path.bounds, rect)
        }
    }
}
