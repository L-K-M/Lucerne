import Foundation

enum ExportError: Error, Equatable {
    case emptyOutput(format: String)
    case invalidPDFPage(page: Int)
    case noPDFPages
    case incompletePDF(expected: Int, actual: Int)
}

extension ExportError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .emptyOutput(let format):
            return "Lucerne couldn't create the \(format) export."
        case .invalidPDFPage(let page):
            return "Lucerne couldn't render page \(page) for PDF export."
        case .noPDFPages:
            return "Lucerne couldn't create the PDF export because the document has no pages."
        case .incompletePDF(let expected, let actual):
            return "Lucerne couldn't assemble all PDF pages (expected \(expected), produced \(actual))."
        }
    }
}

enum ExportValidation {
    static func requireData(_ data: Data?, format: String) throws -> Data {
        guard let data, !data.isEmpty else { throw ExportError.emptyOutput(format: format) }
        return data
    }

    static func requireCompletePDF(sourcePageCount: Int, assembledPageCount: Int) throws {
        guard sourcePageCount > 0 else { throw ExportError.noPDFPages }
        guard assembledPageCount == sourcePageCount else {
            throw ExportError.incompletePDF(expected: sourcePageCount, actual: assembledPageCount)
        }
    }
}
