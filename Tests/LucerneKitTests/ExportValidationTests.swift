import XCTest
@testable import LucerneKit

final class ExportValidationTests: XCTestCase {
    func testRequireDataRejectsMissingAndEmptyOutput() {
        let invalidOutputs: [Data?] = [nil, Data()]
        for output in invalidOutputs {
            XCTAssertThrowsError(try ExportValidation.requireData(output, format: "RTF")) { error in
                XCTAssertEqual(error as? ExportError, .emptyOutput(format: "RTF"))
            }
        }
    }

    func testRequireDataReturnsNonemptyOutput() throws {
        let output = Data([1, 2, 3])
        XCTAssertEqual(try ExportValidation.requireData(output, format: "PDF"), output)
    }

    func testCompletePDFRequiresAtLeastOneSourcePage() {
        XCTAssertThrowsError(
            try ExportValidation.requireCompletePDF(sourcePageCount: 0, assembledPageCount: 0)
        ) { error in
            XCTAssertEqual(error as? ExportError, .noPDFPages)
        }
    }

    func testCompletePDFRejectsDroppedPages() {
        XCTAssertThrowsError(
            try ExportValidation.requireCompletePDF(sourcePageCount: 3, assembledPageCount: 2)
        ) { error in
            XCTAssertEqual(error as? ExportError, .incompletePDF(expected: 3, actual: 2))
        }
    }

    func testCompletePDFAcceptsMatchingPageCounts() {
        XCTAssertNoThrow(
            try ExportValidation.requireCompletePDF(sourcePageCount: 3, assembledPageCount: 3)
        )
    }
}
