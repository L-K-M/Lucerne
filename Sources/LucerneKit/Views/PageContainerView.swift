import AppKit

// One page: a white sheet with a soft shadow, flipped so its coordinate system
// matches the model (origin top-left, y down). Hosts the page's text view and any
// floating image views as subviews.
public final class PageContainerView: NSView {

    public let pageIndex: Int

    public override var isFlipped: Bool { true }

    public init(pageIndex: Int, frame: CGRect) {
        self.pageIndex = pageIndex
        super.init(frame: frame)
        wantsLayer = true
        guard let layer else { return }
        layer.backgroundColor = NSColor.white.cgColor
        layer.borderColor = NSColor(calibratedWhite: 0.78, alpha: 1).cgColor
        layer.borderWidth = 1
        layer.shadowColor = NSColor.black.cgColor
        layer.shadowOpacity = 0.22
        layer.shadowRadius = 6
        layer.shadowOffset = .zero
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
}
