import AppKit
import XCTest
@testable import LucerneKit

final class ListMarkerPasteTests: XCTestCase {
    func testOnlyTheCurrentItemsNumberIsRemoved() {
        let list = NSTextList(markerFormat: NSTextList.MarkerFormat("{decimal}."), options: 0)
        let source = attributed([
            ("\t2.\tLiteral number\n", [list]),
            ("\t2.\tSecond\n", [list]),
            ("Unmarked third\n", [list]),
            ("\t4.\tFourth", [list])
        ])
        XCTAssertEqual(normalize(source).string,
                       "\t2.\tLiteral number\nSecond\nUnmarked third\nFourth")
    }

    func testNestedCountersResumeParentsAndRestartChildren() {
        let outer = NSTextList(markerFormat: NSTextList.MarkerFormat("{decimal}."), options: 0)
        outer.startingItemNumber = 3
        let inner = NSTextList(markerFormat: NSTextList.MarkerFormat("{lower-alpha})"), options: 0)
        inner.startingItemNumber = 2
        let source = attributed([
            ("\t3.\tOuter\n", [outer]),
            ("\t\tb)\tChild 👩🏽‍💻\n", [outer, inner]),
            ("\t\ta)\tLiteral number\n", [outer, inner]),
            ("\t\td)\tThird child\n", [outer, inner]),
            ("\t4.\tNext parent\n", [outer]),
            ("\t\tb)\tRestarted child", [outer, inner])
        ])
        XCTAssertEqual(normalize(source).string,
                       "Outer\nChild 👩🏽‍💻\n\t\ta)\tLiteral number\nThird child\nNext parent\nRestarted child")
    }

    func testNestedBulletsAllowIndentTabsButPreserveOtherTabs() {
        let outer = NSTextList(markerFormat: .disc, options: 0)
        let inner = NSTextList(markerFormat: .circle, options: 0)
        let bullet = inner.marker(forItemNumber: 1)
        let source = attributed([
            ("\t•\tOuter\n", [outer]),
            ("\t\t\(bullet)\tChild\n", [outer, inner]),
            ("\t\t\t\(bullet)\tExtra literal tab\n", [outer, inner]),
            ("\tName\tValue\n", [outer, inner]),
            ("\t•\tPlain text", [])
        ])
        XCTAssertEqual(normalize(source).string,
                       "Outer\nChild\n\t\t\t\(bullet)\tExtra literal tab\n\tName\tValue\n\t•\tPlain text")
    }

    func testPrependingEnclosingMarkersUsesEachLevelsCurrentNumber() {
        let outer = NSTextList(markerFormat: NSTextList.MarkerFormat("{decimal}."), options: 0)
        let inner = NSTextList(markerFormat: NSTextList.MarkerFormat("{lower-alpha})"),
                               options: [.prependEnclosingMarker], startingItemNumber: 1)
        let source = attributed([
            ("\t1.\tOuter\n", [outer]),
            ("\t1.a)\tChild\n", [outer, inner]),
            ("\t1.b)\tSecond child\n", [outer, inner]),
            ("\t2.\tNext parent\n", [outer]),
            ("\t2.a)\tRestarted child", [outer, inner])
        ])
        XCTAssertEqual(normalize(source).string,
                       "Outer\nChild\nSecond child\nNext parent\nRestarted child")
    }

    func testRealRTFImportWithLegacyNestedMarkers() throws {
        guard #available(macOS 15, *) else { throw XCTSkip("Legacy-reader option requires macOS 15") }
        let outer = NSTextList(markerFormat: NSTextList.MarkerFormat("{decimal}."), options: 0)
        let inner = NSTextList(markerFormat: .disc, options: 0)
        let source = attributed([
            ("Outer\n", [outer]), ("Child\n", [outer, inner]),
            ("Second child\n", [outer, inner]), ("Next parent", [outer])
        ])
        let data = try source.data(from: NSRange(location: 0, length: source.length),
                                   documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
        let imported = try NSAttributedString(
            data: data,
            options: [.documentType: NSAttributedString.DocumentType.rtf,
                      .textKit1ListMarkerFormatDocumentOption: true],
            documentAttributes: nil)
        XCTAssertTrue(imported.string.hasPrefix("\t1.\t"))
        XCTAssertEqual(normalize(imported).string, source.string)
    }

    private func attributed(_ paragraphs: [(String, [NSTextList])]) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for (string, lists) in paragraphs {
            let style = NSMutableParagraphStyle()
            style.textLists = lists
            result.append(NSAttributedString(string: string, attributes: [.paragraphStyle: style]))
        }
        return result
    }

    private func normalize(_ source: NSAttributedString) -> NSAttributedString {
        let model = LucerneDocumentModel(page: .a4, styles: DefaultDocuments.defaultStyles(),
                                        body: [], objects: [])
        return PasteNormalizer.normalize(source, destination: [:], model: model)
    }
}
