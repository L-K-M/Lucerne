import XCTest
@testable import LucerneKit

/// Locks the exclusion-rect helper that pagination's dirty-check (review 3.1) relies
/// on: `exclusionPaths` must be derivable one-per-rect from `exclusionRects`, and the
/// filtering (page, wrap mode, missing frame) must match what the paths did before.
final class ExclusionRectsTests: XCTestCase {

    private let metrics = PageMetrics(page: .a4)
    private let sampleFrame = RectModel(x: 200, y: 200, width: 100, height: 80)

    private func object(id: String, page: Int?, wrap: String = "rectangular",
                        z: Int = 0, frame: RectModel? = RectModel(x: 200, y: 200, width: 100, height: 80)) -> PlacedObject {
        PlacedObject(id: id, page: page, frame: frame, wrap: wrap, standoff: 12, z: z)
    }

    func testRectsCoverOnlyWrappingObjectsOnThePage() {
        let objects = [
            object(id: "a", page: 0),                     // on page, wrapping → included
            object(id: "b", page: 1),                     // other page → excluded
            object(id: "c", page: 0, wrap: "none"),       // overlay → excluded
            object(id: "d", page: 0, frame: nil),         // no frame → excluded
        ]
        let rects = ExclusionPathController.exclusionRects(forPage: 0, objects: objects, metrics: metrics)
        XCTAssertEqual(rects.count, 1)
        XCTAssertEqual(rects.first, metrics.exclusionRect(forObjectFrame: sampleFrame, standoff: 12))
    }

    func testPathsAreOnePerRect() {
        let objects = [object(id: "a", page: 0, z: 2), object(id: "b", page: 0, z: 1)]
        let rects = ExclusionPathController.exclusionRects(forPage: 0, objects: objects, metrics: metrics)
        let paths = ExclusionPathController.exclusionPaths(forPage: 0, objects: objects, metrics: metrics)
        XCTAssertEqual(rects.count, 2)
        XCTAssertEqual(paths.count, rects.count)
    }
}
