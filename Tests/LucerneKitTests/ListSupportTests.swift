import XCTest
@testable import LucerneKit

/// The list numbering engine, marker labels, Markdown-shortcut recognition, and the
/// attribute codec — all pure, so they exercise the heart of the feature without a GUI.
final class ListSupportTests: XCTestCase {

    private func item(_ list: String, _ ordered: Bool, _ marker: String,
                      level: Int = 0, start: Int? = nil) -> ListItemModel {
        ListItemModel(list: list, ordered: ordered, marker: marker, level: level, start: start)
    }

    private func markers(_ items: [ListItemModel?]) -> [String?] {
        ListMarkers.resolve(items).map { $0?.text }
    }

    // MARK: - Numbering

    func testBulletsAllShowTheSameGlyph() {
        let list = Array(repeating: Optional(item("a", false, "disc")), count: 3)
        XCTAssertEqual(markers(list), ["\u{2022}", "\u{2022}", "\u{2022}"])
    }

    func testOrderedCountsFromOne() {
        let list = Array(repeating: Optional(item("a", true, "decimal")), count: 3)
        XCTAssertEqual(markers(list), ["1.", "2.", "3."])
    }

    func testOrderedRespectsStartNumber() {
        let list = [item("a", true, "decimal", start: 5), item("a", true, "decimal")]
        XCTAssertEqual(markers(list), ["5.", "6."])
    }

    func testDifferentListIdsRestartNumbering() {
        let list = [item("a", true, "decimal"), item("a", true, "decimal"),
                    item("b", true, "decimal"), item("b", true, "decimal")]
        XCTAssertEqual(markers(list), ["1.", "2.", "1.", "2."])
    }

    func testNonListParagraphBreaksTheList() {
        let list: [ListItemModel?] = [item("a", true, "decimal"), nil, item("a", true, "decimal")]
        XCTAssertEqual(markers(list), ["1.", nil, "1."])
    }

    func testBulletBeforeOrderedDoesNotBumpTheFirstNumber() {
        // A bullet doesn't count, so the first numbered item after it is still 1.
        let list: [ListItemModel?] = [item("a", false, "disc"),
                                      item("a", true, "decimal"),
                                      item("a", true, "decimal")]
        XCTAssertEqual(markers(list), ["\u{2022}", "1.", "2."])
    }

    func testOrderedContinuesAcrossAnInterveningBullet() {
        let list: [ListItemModel?] = [item("a", true, "decimal"),
                                      item("a", false, "disc"),
                                      item("a", true, "decimal")]
        XCTAssertEqual(markers(list), ["1.", "\u{2022}", "2."])
    }

    func testBulletBeforeOrderedStillHonoursStart() {
        let list: [ListItemModel?] = [item("a", false, "disc"),
                                      item("a", true, "decimal", start: 5)]
        XCTAssertEqual(markers(list), ["\u{2022}", "5."])
    }

    func testNestingRestartsAndResumesCounters() {
        // 1.  a
        //   1.  b   (nested restarts)
        //   2.  c
        // 2.  d     (outdent resumes the parent counter)
        let list = [item("a", true, "decimal", level: 0),
                    item("a", true, "decimal", level: 1),
                    item("a", true, "decimal", level: 1),
                    item("a", true, "decimal", level: 0)]
        XCTAssertEqual(markers(list), ["1.", "1.", "2.", "2."])
    }

    func testDeeplyNestedThenOutdentTwoLevels() {
        let list = [item("a", true, "decimal", level: 0),   // 1.
                    item("a", true, "decimal", level: 1),   // 1.
                    item("a", true, "decimal", level: 2),   // 1.
                    item("a", true, "decimal", level: 0)]   // 2.
        XCTAssertEqual(markers(list), ["1.", "1.", "1.", "2."])
    }

    func testResolveExposesRawNumbersForOrdered() {
        let list = [item("a", true, "decimal", start: 3), item("a", true, "decimal")]
        XCTAssertEqual(ListMarkers.resolve(list).map { $0?.number }, [3, 4])
    }

    // MARK: - Labels

    func testAlphaLabels() {
        XCTAssertEqual(ListMarkers.alpha(1, uppercase: false), "a")
        XCTAssertEqual(ListMarkers.alpha(26, uppercase: false), "z")
        XCTAssertEqual(ListMarkers.alpha(27, uppercase: false), "aa")
        XCTAssertEqual(ListMarkers.alpha(52, uppercase: false), "az")
        XCTAssertEqual(ListMarkers.alpha(53, uppercase: false), "ba")
        XCTAssertEqual(ListMarkers.alpha(2, uppercase: true), "B")
    }

    func testRomanLabels() {
        XCTAssertEqual(ListMarkers.roman(4, uppercase: true), "IV")
        XCTAssertEqual(ListMarkers.roman(9, uppercase: false), "ix")
        XCTAssertEqual(ListMarkers.roman(2024, uppercase: true), "MMXXIV")
        XCTAssertEqual(ListMarkers.roman(0, uppercase: true), "0")   // out of range → decimal
    }

    func testOrderedLabelStyles() {
        XCTAssertEqual(ListMarkers.orderedLabel(3, style: "decimal"), "3")
        XCTAssertEqual(ListMarkers.orderedLabel(3, style: "lower-alpha"), "c")
        XCTAssertEqual(ListMarkers.orderedLabel(3, style: "upper-roman"), "III")
        XCTAssertEqual(ListMarkers.orderedLabel(3, style: "nonsense"), "3")  // unknown → decimal
    }

    func testAlphaAndRomanListsNumberInTheirOwnScript() {
        let alpha = Array(repeating: Optional(item("a", true, "lower-alpha")), count: 3)
        XCTAssertEqual(markers(alpha), ["a.", "b.", "c."])
        let roman = Array(repeating: Optional(item("r", true, "upper-roman")), count: 3)
        XCTAssertEqual(markers(roman), ["I.", "II.", "III."])
    }

    // MARK: - Markdown shortcut recognition

    func testBulletMarkersStartUnorderedLists() {
        for marker in ["-", "*", "+"] {
            let spec = EditorController.markdownListShortcut(forMarker: marker)
            XCTAssertEqual(spec?.ordered, false, "\(marker)")
            XCTAssertEqual(spec?.marker, "disc")
            XCTAssertNil(spec?.start)
        }
    }

    func testNumberMarkersStartOrderedLists() {
        XCTAssertEqual(EditorController.markdownListShortcut(forMarker: "1.")?.ordered, true)
        XCTAssertNil(EditorController.markdownListShortcut(forMarker: "1.")?.start)   // 1 is the default
        XCTAssertEqual(EditorController.markdownListShortcut(forMarker: "3.")?.start, 3)
        XCTAssertEqual(EditorController.markdownListShortcut(forMarker: "10)")?.start, 10)
    }

    func testNonListMarkersAreRejected() {
        for marker in ["#", "##", ">", "1", "a.", ".", ")", "", "1a."] {
            XCTAssertNil(EditorController.markdownListShortcut(forMarker: marker), "\(marker)")
        }
    }

    // MARK: - Attribute codec

    func testListItemCodecRoundTrips() throws {
        let original = item("list-7", true, "lower-roman", level: 2, start: 4)
        let encoded = try XCTUnwrap(ListItemCodec.encode(original))
        XCTAssertEqual(ListItemCodec.decode(encoded), original)
    }

    func testListItemCodecRejectsGarbage() {
        XCTAssertNil(ListItemCodec.decode("not json"))
        XCTAssertNil(ListItemCodec.decode(42))
        XCTAssertNil(ListItemCodec.decode(nil))
    }

    // MARK: - Geometry

    func testContentIndentGrowsPerLevel() {
        XCTAssertEqual(ListGeometry.contentIndent(level: 0), 24)
        XCTAssertEqual(ListGeometry.contentIndent(level: 1), 48)
        XCTAssertEqual(ListGeometry.contentIndent(level: 2), 72)
        XCTAssertEqual(ListGeometry.contentIndent(level: -3), 24)   // clamped
    }
}
