import AppKit
import PDFKit

// A view used only for printing: it stacks the per-page PDFs the editor produced
// and implements knowsPageRange/rectForPage so the print system emits one document
// page per sheet at the correct size.
public final class PaginatedPrintView: NSView {

    private let pdfPages: [PDFPage]
    private let pageSize: CGSize

    public override var isFlipped: Bool { true }

    public init(pagePDFs: [Data], pageSize: CGSize) {
        self.pdfPages = pagePDFs.compactMap { PDFDocument(data: $0)?.page(at: 0) }
        self.pageSize = pageSize
        let height = max(pageSize.height, CGFloat(pdfPages.count) * pageSize.height)
        super.init(frame: CGRect(x: 0, y: 0, width: pageSize.width, height: height))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    public override func knowsPageRange(_ range: NSRangePointer) -> Bool {
        range.pointee = NSRange(location: 1, length: max(1, pdfPages.count))
        return true
    }

    public override func rectForPage(_ page: Int) -> NSRect {
        let index = page - 1            // AppKit page numbers are 1-based
        return NSRect(x: 0, y: CGFloat(index) * pageSize.height,
                      width: pageSize.width, height: pageSize.height)
    }

    public override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        NSColor.white.setFill()
        dirtyRect.fill()

        for (index, page) in pdfPages.enumerated() {
            let pageRect = NSRect(x: 0, y: CGFloat(index) * pageSize.height,
                                  width: pageSize.width, height: pageSize.height)
            guard pageRect.intersects(dirtyRect) else { continue }
            context.saveGState()
            // PDFPage.draw expects an unflipped (y-up) CTM; flip within this page box.
            context.translateBy(x: 0, y: pageRect.maxY)
            context.scaleBy(x: 1, y: -1)
            let media = page.bounds(for: .mediaBox)
            if media.height > 0 {
                context.scaleBy(x: pageSize.width / media.width, y: pageSize.height / media.height)
            }
            page.draw(with: .mediaBox, to: context)
            context.restoreGState()
        }
    }
}
