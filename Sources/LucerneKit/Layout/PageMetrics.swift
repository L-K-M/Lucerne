import CoreGraphics

// All page geometry in one place. This is the "coordinate bookkeeping" the plan
// (§3, Avenue A risks) warns is the main bug source — so it is isolated here as
// pure functions and unit-tested. Everything is in points, origin top-left, y down
// (the page-view and text-container convention; both are flipped).
public struct PageMetrics: Equatable {
    public let pageSize: CGSize
    public let marginTop: CGFloat
    public let marginLeft: CGFloat
    public let marginBottom: CGFloat
    public let marginRight: CGFloat

    public init(page: PageConfig) {
        pageSize = CGSize(width: page.width, height: page.height)
        marginTop = CGFloat(page.margins.top)
        marginLeft = CGFloat(page.margins.left)
        marginBottom = CGFloat(page.margins.bottom)
        marginRight = CGFloat(page.margins.right)
    }

    /// Size of the text area (the text container size, identical on every page, D1).
    public var contentSize: CGSize {
        CGSize(width: max(0, pageSize.width - marginLeft - marginRight),
               height: max(0, pageSize.height - marginTop - marginBottom))
    }

    /// Frame of the text view within its (flipped) page view.
    public var textFrameInPage: CGRect {
        CGRect(x: marginLeft, y: marginTop, width: contentSize.width, height: contentSize.height)
    }

    /// A page-anchored object's frame maps **directly** into its page view — both
    /// use top-left / y-down coordinates.
    public func viewFrame(forObjectFrame frame: RectModel) -> CGRect {
        CGRect(x: frame.x, y: frame.y, width: frame.width, height: frame.height)
    }

    /// The exclusion rectangle for a page-anchored object, in **text-container**
    /// coordinates: shift by the margins (the container starts at the margin) and
    /// inflate outward by the standoff gutter.
    ///
    /// If the gap left between the obstacle and a side margin is narrower than
    /// `minColumn`, the exclusion is extended to that margin so text doesn't flow
    /// into an unusable sliver and clip mid-word — it wraps on the wider side and
    /// below instead. This matches how ClarisWorks/DTP handle a box near a margin.
    public func exclusionRect(forObjectFrame frame: RectModel, standoff: Double,
                              minColumn: CGFloat = 72) -> CGRect {
        let s = CGFloat(standoff)
        var left = CGFloat(frame.minX) - marginLeft - s
        var right = CGFloat(frame.maxX) - marginLeft + s
        let top = CGFloat(frame.minY) - marginTop - s
        let height = CGFloat(frame.height) + 2 * s
        let width = contentSize.width

        if left > 0, left < minColumn { left = 0 }
        if right < width, width - right < minColumn { right = width }

        return CGRect(x: left, y: top, width: right - left, height: height)
    }

    /// Clamp a proposed object frame so the image stays within the page bounds
    /// (v1 behaviour: clip rather than overhang — see AGENTS.md limitations).
    public func clampObjectFrame(_ frame: CGRect) -> CGRect {
        var f = frame
        f.size.width = min(f.size.width, pageSize.width)
        f.size.height = min(f.size.height, pageSize.height)
        f.origin.x = min(max(0, f.origin.x), pageSize.width - f.size.width)
        f.origin.y = min(max(0, f.origin.y), pageSize.height - f.size.height)
        return f
    }
}
