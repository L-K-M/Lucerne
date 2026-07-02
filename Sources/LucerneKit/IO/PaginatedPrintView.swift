import AppKit
import PDFKit

// A view used only for printing: it stacks the per-page PDFs the editor produced
// and implements knowsPageRange/rectForPage so the print system emits one document
// page per sheet at the correct size.
public final class PaginatedPrintView: NSView {

    // One slot per source page, preserving position: a page whose PDF failed to
    // parse is kept as `nil` rather than compacted away, so later pages don't shift
    // into the wrong slot (which would desync the baked "{page} of {pages}" footers).
    private let pdfPages: [PDFPage?]
    private let pageSize: CGSize

    public override var isFlipped: Bool { true }

    public init(pagePDFs: [Data], pageSize: CGSize) {
        let rendered = pagePDFs.map { PDFDocument(data: $0)?.page(at: 0) }
        // If *every* page failed there's nothing to preserve; fall back to a single
        // blank sheet (as before) but leave a trace of why the print looks empty.
        if !rendered.isEmpty && rendered.allSatisfy({ $0 == nil }) {
            NSLog("PaginatedPrintView: all \(rendered.count) page(s) failed to render; printing one blank sheet.")
            self.pdfPages = []
        } else {
            self.pdfPages = rendered
        }
        self.pageSize = pageSize
        let pageCount = self.pdfPages.count
        let height = max(pageSize.height, CGFloat(pageCount) * pageSize.height)
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
            guard let page else {
                // A page that failed to render still occupies its sheet; label it so
                // the failure is visible rather than a silently dropped page (2.9).
                drawFailedPagePlaceholder(in: pageRect)
                continue
            }
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

    private func drawFailedPagePlaceholder(in rect: NSRect) {
        let text = "This page could not be rendered." as NSString
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12),
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: style,
        ]
        let size = text.size(withAttributes: attrs)
        let origin = NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2)
        text.draw(at: origin, withAttributes: attrs)
    }
}
