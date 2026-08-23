import XCTest
@testable import LucerneCore

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

    func testRectsAreZSorted() {
        // The one-NSBezierPath-per-rect derivation is locked by
        // ExclusionPathsTests in LucerneKitTests (it needs AppKit); the portable
        // half of that old test — rect count and z-ascending order — lives here.
        // Distinct frames with z running AGAINST y, so only a genuine
        // z-ascending sort (not geometry or insertion order) passes.
        let low = RectModel(x: 100, y: 100, width: 10, height: 10)
        let high = RectModel(x: 300, y: 300, width: 10, height: 10)
        let objects = [object(id: "a", page: 0, z: 2, frame: low),
                       object(id: "b", page: 0, z: 1, frame: high)]
        let rects = ExclusionPathController.exclusionRects(forPage: 0, objects: objects, metrics: metrics)
        XCTAssertEqual(rects.count, 2)
        XCTAssertEqual(rects.first, metrics.exclusionRect(forObjectFrame: high, standoff: 12),
                       "z=1 must come first despite its larger y")
        XCTAssertEqual(rects.last, metrics.exclusionRect(forObjectFrame: low, standoff: 12))
    }
}
