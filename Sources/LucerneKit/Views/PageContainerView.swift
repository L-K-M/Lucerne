import AppKit

// One page: a white sheet with a soft shadow, flipped so its coordinate system
// matches the model (origin top-left, y down). Hosts the page's text view and any
// floating image views as subviews.
//
// The white fill + border are drawn in draw(_:) (not via the layer's
// backgroundColor) so that dataWithPDF(inside:) — used for PDF export and
// printing — captures a real white page. The layer carries only the drop shadow.
public final class PageContainerView: NSView {

    public let pageIndex: Int

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
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    public override func draw(_ dirtyRect: NSRect) {
        NSColor.white.setFill()
        bounds.fill()
        NSColor(calibratedWhite: 0.70, alpha: 1).setStroke()
        let border = NSBezierPath(rect: bounds.insetBy(dx: 0.5, dy: 0.5))
        border.lineWidth = 1
        border.stroke()
    }
}
