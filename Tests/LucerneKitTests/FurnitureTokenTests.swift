import XCTest
@testable import LucerneKit

// Header/footer token substitution (EditorController.resolveFurnitureTemplate).
// The zone-blanking rule for unnumbered pages is easy to regress, so it's pinned.
final class FurnitureTokenTests: XCTestCase {

    func testAllFourTokensSubstitute() {
        let out = EditorController.resolveFurnitureTemplate(
            "{title} — page {page} of {pages} · {date}",
            page: 2, pages: 5, date: "March 3, 2026", title: "Offer Letter")
        XCTAssertEqual(out, "Offer Letter — page 2 of 5 · March 3, 2026")
    }

    func testPageTokenOnUnnumberedPageBlanksZone() {
        // page == nil is a page before the numbering start: a zone that references
        // a page number renders empty rather than "Page  of 5".
        XCTAssertEqual(
            EditorController.resolveFurnitureTemplate(
                "Page {page} of {pages}", page: nil, pages: 5, date: "d", title: "t"),
            "")

        // …but date/title-only zones on that same page still render.
        XCTAssertEqual(
            EditorController.resolveFurnitureTemplate(
                "{title}", page: nil, pages: 5, date: "March 3, 2026", title: "Offer Letter"),
            "Offer Letter")
        XCTAssertEqual(
            EditorController.resolveFurnitureTemplate(
                "{date}", page: nil, pages: 5, date: "March 3, 2026", title: "Offer Letter"),
            "March 3, 2026")
    }

    func testPagesShowsNumberedCount() {
        XCTAssertEqual(
            EditorController.resolveFurnitureTemplate(
                "{pages}", page: 1, pages: 3, date: "d", title: "t"),
            "3")
    }

    func testEmptyTemplateStaysEmpty() {
        XCTAssertEqual(
            EditorController.resolveFurnitureTemplate("", page: 1, pages: 2, date: "d", title: "t"),
            "")
    }
}
