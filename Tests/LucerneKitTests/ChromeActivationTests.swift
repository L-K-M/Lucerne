import AppKit
import RigiUI
import XCTest
import LucerneKit

@MainActor
final class ChromeActivationTests: XCTestCase {
    func testTheAppOwnedRulerOptsIntoRigisActivationRedraw() {
        let ruler: NSView = LucerneRulerView(frame: .zero)
        XCTAssertTrue(ruler is any ClassicChromeDrawing)
    }
}
