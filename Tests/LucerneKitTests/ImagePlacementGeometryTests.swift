import XCTest
@testable import LucerneKit

final class ImagePlacementGeometryTests: XCTestCase {

    func testExtremePortraitFitsHeightWithoutChangingAspectRatio() {
        let fitted = aspectFitSize(CGSize(width: 100, height: 2_000),
                                   within: CGSize(width: 250, height: 800))
        XCTAssertEqual(fitted.width, 40, accuracy: 0.001)
        XCTAssertEqual(fitted.height, 800, accuracy: 0.001)
    }

    func testExtremeLandscapeFitsWidthWithoutChangingAspectRatio() {
        let fitted = aspectFitSize(CGSize(width: 2_000, height: 100),
                                   within: CGSize(width: 250, height: 800))
        XCTAssertEqual(fitted.width, 250, accuracy: 0.001)
        XCTAssertEqual(fitted.height, 12.5, accuracy: 0.001)
    }

    func testImageSmallerThanAvailableSizeKeepsNativeSize() {
        let fitted = aspectFitSize(CGSize(width: 120, height: 80),
                                   within: CGSize(width: 250, height: 800))
        XCTAssertEqual(fitted, CGSize(width: 120, height: 80))
    }
}
