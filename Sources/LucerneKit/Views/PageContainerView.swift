import AppKit

// One page: a white sheet with a soft shadow, flipped so its coordinate system
// matches the model (origin top-left, y down). Hosts the page's text view and any
// floating image views as subviews, and draws the running header/footer (already
// token-resolved by the editor) in the top/bottom margins.
public final class PageContainerView: NSView {

    public let pageIndex: Int
    private var shadowPathBounds = CGRect.null

    // Margins (points) — the bands where header/footer text is drawn.
    public var marginTop: CGFloat = 72
    public var marginLeft: CGFloat = 72
    public var marginBottom: CGFloat = 72
    public var marginRight: CGFloat = 72

    // Resolved header/footer zone text (tokens already substituted for this page).
    // Guarded so a relayout that re-resolves to the same strings doesn't repaint
    // every sheet (3.9).
    public var headerLeft = "" { didSet { if headerLeft != oldValue { needsDisplay = true } } }
    public var headerCenter = "" { didSet { if headerCenter != oldValue { needsDisplay = true } } }
    public var headerRight = "" { didSet { if headerRight != oldValue { needsDisplay = true } } }
    public var footerLeft = "" { didSet { if footerLeft != oldValue { needsDisplay = true } } }
    public var footerCenter = "" { didSet { if footerCenter != oldValue { needsDisplay = true } } }
    public var footerRight = "" { didSet { if footerRight != oldValue { needsDisplay = true } } }

    // Furniture typography. The editor sets these to the document's Body face at a
    // reduced size; nil falls back to a neutral 10 pt system gray (4.6).
    public var furnitureFont: NSFont? { didSet { if furnitureFont != oldValue { needsDisplay = true } } }
    public var furnitureColor: NSColor? { didSet { if furnitureColor != oldValue { needsDisplay = true } } }

    // DIN 5008 tri-fold guide ticks in the outer left margin (windowed envelopes).
    public var showFoldMarks = false { didSet { if oldValue != showFoldMarks { needsDisplay = true } } }

    public override var isFlipped: Bool { true }

    public init(pageIndex: Int, frame: CGRect) {
        self.pageIndex = pageIndex
        super.init(frame: frame)
        wantsLayer = true
        if let layer {
            layer.shadowColor = NSColor.black.cgColor
            layer.shadowOpacity = 0.38
            layer.shadowRadius = 12
            layer.shadowOffset = CGSize(width: 0, height: -2)
        }
        updateShadowPath()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    public override func layout() {
        super.layout()
        updateShadowPath()
    }

    private func updateShadowPath() {
        guard bounds != shadowPathBounds, let layer else { return }
        layer.shadowPath = CGPath(rect: bounds, transform: nil)
        shadowPathBounds = bounds
    }

    public override func draw(_ dirtyRect: NSRect) {
        NSColor.white.setFill()
        bounds.fill()
        // The gray page-edge outline only separates the sheet from the on-screen
        // gray canvas; it must not appear in PDF/print captures (1.12).
        if NSGraphicsContext.currentContextDrawingToScreen() {
            NSColor(calibratedWhite: 0.70, alpha: 1).setStroke()
            let border = NSBezierPath(rect: bounds.insetBy(dx: 0.5, dy: 0.5))
            border.lineWidth = 1
            border.stroke()
        }

        let headerBand = NSRect(x: 0, y: 0, width: bounds.width, height: marginTop)
        drawZones(headerLeft, headerCenter, headerRight, in: headerBand)
        let footerBand = NSRect(x: 0, y: bounds.height - marginBottom, width: bounds.width, height: marginBottom)
        drawZones(footerLeft, footerCenter, footerRight, in: footerBand)

        if showFoldMarks { drawFoldMarks() }
    }

    /// Two light 0.5-pt horizontal ticks in the outer left margin band at the DIN
    /// 5008 offsets from the top. Drawn here so print/PDF capture them automatically.
    private func drawFoldMarks() {
        NSColor(calibratedWhite: 0.75, alpha: 1).setStroke()
        for y in PageMetrics.din5008FoldMarkOffsetsFromTop {
            let mark = NSBezierPath()
            mark.move(to: CGPoint(x: 6, y: y))
            mark.line(to: CGPoint(x: 18, y: y))
            mark.lineWidth = 0.5
            mark.stroke()
        }
    }

    private func drawZones(_ left: String, _ center: String, _ right: String, in band: NSRect) {
        let font = furnitureFont ?? NSFont.systemFont(ofSize: 10)
        let color = furnitureColor ?? NSColor(calibratedWhite: 0.35, alpha: 1)
        let width = bounds.width - marginLeft - marginRight
        guard width > 0 else { return }
        for (text, alignment) in [(left, NSTextAlignment.left), (center, .center), (right, .right)] {
            guard !text.isEmpty else { continue }
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = alignment
            paragraph.lineBreakMode = .byTruncatingTail
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font, .foregroundColor: color, .paragraphStyle: paragraph
            ]
            let size = (text as NSString).size(withAttributes: attrs)
            let rect = NSRect(x: marginLeft, y: band.midY - size.height / 2, width: width, height: size.height)
            (text as NSString).draw(in: rect, withAttributes: attrs)
        }
    }
}
