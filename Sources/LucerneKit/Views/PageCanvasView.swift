import AppKit

// The scroll view's document view: a gray backdrop that stacks page views
// vertically and centers them horizontally. Pages are added/removed incrementally
// by EditorController (never torn down wholesale), so the active text view keeps
// first responder while typing causes pages to appear or disappear.
public final class PageCanvasView: NSView {

    public var pageGap: CGFloat = 24
    public var topInset: CGFloat = 28
    public var bottomInset: CGFloat = 28
    public var sideInset: CGFloat = 28

    public private(set) var pageViews: [PageContainerView] = []
    public var pageSize: CGSize = .zero

    public override var isFlipped: Bool { true }

    public override func draw(_ dirtyRect: NSRect) {
        NSColor(calibratedWhite: 0.80, alpha: 1).setFill()
        dirtyRect.fill()
    }

    public func appendPageView(_ view: PageContainerView) {
        pageViews.append(view)
        addSubview(view)
        needsLayout = true
    }

    public func removeLastPageView() {
        guard let last = pageViews.popLast() else { return }
        last.removeFromSuperview()
        needsLayout = true
    }

    public override func layout() {
        super.layout()
        layoutPages()
    }

    public func layoutPages() {
        guard pageSize.width > 0, pageSize.height > 0 else { return }

        let viewportWidth = enclosingScrollView?.contentView.bounds.width ?? bounds.width
        let viewportHeight = enclosingScrollView?.contentView.bounds.height ?? bounds.height

        let width = max(viewportWidth, pageSize.width + 2 * sideInset)
        let contentHeight = topInset
            + CGFloat(pageViews.count) * pageSize.height
            + CGFloat(max(0, pageViews.count - 1)) * pageGap
            + bottomInset
        let height = max(contentHeight, viewportHeight)

        let newSize = CGSize(width: width, height: height)
        if abs(newSize.width - frame.width) > 0.5 || abs(newSize.height - frame.height) > 0.5 {
            setFrameSize(newSize)
        }

        let x = ((width - pageSize.width) / 2).rounded()
        var y = topInset
        for pageView in pageViews {
            pageView.frame = CGRect(x: x, y: y, width: pageSize.width, height: pageSize.height)
            y += pageSize.height + pageGap
        }
    }
}
