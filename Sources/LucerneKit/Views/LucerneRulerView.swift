import AppKit

// A horizontal ruler with draggable indent markers and tab stops, drawn to line up
// with the page below it. It reads the active paragraph's indents/tabs from the
// EditorController and writes changes back through it (one undo step per gesture).
//
// Conventions: not flipped (origin bottom-left). The ruler's own x-axis spans
// [0, pageWidth]; document point p (from the left margin) maps to x = marginLeft+p.
public final class LucerneRulerView: NSView {

    public weak var editor: EditorController?

    public var rulerHeight: CGFloat = 26

    private var marginLeft: CGFloat = 72
    private var marginRight: CGFloat = 72
    private var pageWidth: CGFloat = 595.28

    // Current paragraph values, in document points from the left margin.
    private var leftIndent: CGFloat = 0
    private var firstLineExtra: CGFloat = 0
    private var rightIndent: CGFloat = 0
    private var tabs: [(loc: CGFloat, kind: TabStopModel.Kind)] = []

    private enum Marker: Equatable { case none, left, firstLine, right, tab(Int) }
    private var dragging: Marker = .none
    private var dragRemovedTab = false

    private let markerHalf: CGFloat = 6
    private let hitTolerance: CGFloat = 7

    public override var isFlipped: Bool { false }
    public override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: rulerHeight) }

    private var contentWidth: CGFloat { max(0, pageWidth - marginLeft - marginRight) }
    private var contentRightX: CGFloat { pageWidth - marginRight }

    // MARK: - External updates

    public func updateGeometry(marginLeft: CGFloat, marginRight: CGFloat, pageWidth: CGFloat) {
        self.marginLeft = marginLeft
        self.marginRight = marginRight
        self.pageWidth = pageWidth
        needsDisplay = true
    }

    public func refresh() {
        guard let ps = editor?.selectedParagraphStyle() else { return }
        leftIndent = ps.headIndent
        firstLineExtra = ps.firstLineHeadIndent - ps.headIndent
        rightIndent = ps.tailIndent < 0 ? -ps.tailIndent : 0
        tabs = ps.tabStops.map { tab in
            let kind: TabStopModel.Kind
            if tab.options[.columnTerminators] != nil { kind = .decimal }
            else {
                switch tab.alignment {
                case .center: kind = .center
                case .right: kind = .right
                default: kind = .left
                }
            }
            return (loc: tab.location, kind: kind)
        }
        needsDisplay = true
    }

    // MARK: - Drawing

    public override func draw(_ dirtyRect: NSRect) {
        let h = bounds.height
        NSColor(calibratedWhite: 0.96, alpha: 1).setFill()
        bounds.fill()

        // Content band (between margins)
        let band = NSRect(x: marginLeft, y: 0, width: contentWidth, height: h)
        NSColor.white.setFill()
        band.fill()

        // Ticks every 1/8 inch (9pt), labels every inch (72pt)
        NSColor(calibratedWhite: 0.55, alpha: 1).setStroke()
        let labelAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 8),
            .foregroundColor: NSColor(calibratedWhite: 0.4, alpha: 1)
        ]
        var p: CGFloat = 0
        while p <= contentWidth + 0.5 {
            let x = marginLeft + p
            let isInch = Int(p.rounded()) % 72 == 0
            let tickHeight: CGFloat = isInch ? 8 : (Int(p.rounded()) % 36 == 0 ? 6 : 4)
            let path = NSBezierPath()
            path.move(to: CGPoint(x: x, y: h / 2 - tickHeight / 2))
            path.line(to: CGPoint(x: x, y: h / 2 + tickHeight / 2))
            path.lineWidth = 1
            path.stroke()
            if isInch && p > 0 {
                let label = "\(Int(p / 72))" as NSString
                label.draw(at: CGPoint(x: x + 2, y: h / 2 - 4), withAttributes: labelAttrs)
            }
            p += 9
        }

        // Bottom border
        NSColor(calibratedWhite: 0.7, alpha: 1).setStroke()
        let border = NSBezierPath()
        border.move(to: CGPoint(x: 0, y: 0.5))
        border.line(to: CGPoint(x: bounds.width, y: 0.5))
        border.stroke()

        drawIndentMarkers(height: h)
        drawTabMarkers(height: h)
    }

    private func drawIndentMarkers(height h: CGFloat) {
        NSColor.controlAccentColor.setFill()
        // First-line indent: downward triangle at the top.
        let firstX = marginLeft + leftIndent + firstLineExtra
        fillTriangle(centerX: firstX, baseY: h, pointingDown: true)
        // Left indent: upward triangle at the bottom.
        let leftX = marginLeft + leftIndent
        fillTriangle(centerX: leftX, baseY: 0, pointingDown: false)
        // Right indent: upward triangle at the bottom, on the right.
        let rightX = contentRightX - rightIndent
        fillTriangle(centerX: rightX, baseY: 0, pointingDown: false)
    }

    private func fillTriangle(centerX: CGFloat, baseY: CGFloat, pointingDown: Bool) {
        let path = NSBezierPath()
        let tip = pointingDown ? baseY - markerHalf * 1.6 : baseY + markerHalf * 1.6
        path.move(to: CGPoint(x: centerX - markerHalf, y: baseY))
        path.line(to: CGPoint(x: centerX + markerHalf, y: baseY))
        path.line(to: CGPoint(x: centerX, y: tip))
        path.close()
        path.fill()
    }

    private func drawTabMarkers(height h: CGFloat) {
        NSColor(calibratedWhite: 0.25, alpha: 1).setStroke()
        NSColor(calibratedWhite: 0.25, alpha: 1).setFill()
        for tab in tabs {
            let x = marginLeft + tab.loc
            let y: CGFloat = 4
            let glyph = NSBezierPath()
            glyph.lineWidth = 1.5
            switch tab.kind {
            case .left:
                glyph.move(to: CGPoint(x: x, y: y)); glyph.line(to: CGPoint(x: x, y: y + 8))
                glyph.move(to: CGPoint(x: x, y: y)); glyph.line(to: CGPoint(x: x + 6, y: y))
            case .right:
                glyph.move(to: CGPoint(x: x, y: y)); glyph.line(to: CGPoint(x: x, y: y + 8))
                glyph.move(to: CGPoint(x: x, y: y)); glyph.line(to: CGPoint(x: x - 6, y: y))
            case .center:
                glyph.move(to: CGPoint(x: x, y: y)); glyph.line(to: CGPoint(x: x, y: y + 8))
                glyph.move(to: CGPoint(x: x - 5, y: y)); glyph.line(to: CGPoint(x: x + 5, y: y))
            case .decimal:
                glyph.move(to: CGPoint(x: x, y: y)); glyph.line(to: CGPoint(x: x, y: y + 8))
                glyph.move(to: CGPoint(x: x - 5, y: y)); glyph.line(to: CGPoint(x: x + 5, y: y))
                NSBezierPath(ovalIn: CGRect(x: x + 2, y: y - 1, width: 2, height: 2)).fill()
            }
            glyph.stroke()
        }
    }

    // MARK: - Mouse

    public override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        dragRemovedTab = false

        if event.clickCount == 2, let i = tabIndex(near: p.x) {
            cycleTabKind(at: i)
            commitTabs()
            return
        }

        dragging = marker(at: p)
        if dragging == .none, p.x >= marginLeft, p.x <= contentRightX {
            // Click in an empty part of the band → add a left tab there.
            let loc = clampTabLocation(p.x - marginLeft)
            tabs.append((loc: loc, kind: .left))
            tabs.sort { $0.loc < $1.loc }
            dragging = .tab(tabIndex(near: marginLeft + loc) ?? tabs.count - 1)
            needsDisplay = true
        }
    }

    public override func mouseDragged(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        let docPoint = p.x - marginLeft

        switch dragging {
        case .none:
            return
        case .left:
            let newLeft = clamp(docPoint, 0, contentWidth)
            // Move the first-line marker with the left marker (preserve the offset).
            leftIndent = newLeft
        case .firstLine:
            let absFirst = clamp(docPoint, 0, contentWidth)
            firstLineExtra = absFirst - leftIndent
        case .right:
            let fromRight = clamp(contentWidth - docPoint, 0, contentWidth - leftIndent)
            rightIndent = fromRight
        case .tab(let i):
            guard tabs.indices.contains(i) else { return }
            // Dragging far above/below the ruler removes the tab on mouse-up.
            dragRemovedTab = p.y < -hitTolerance || p.y > bounds.height + hitTolerance
            tabs[i].loc = clampTabLocation(docPoint)
        }
        needsDisplay = true
    }

    public override func mouseUp(with event: NSEvent) {
        switch dragging {
        case .none:
            break
        case .left, .firstLine, .right:
            commitIndents()
        case .tab(let i):
            if dragRemovedTab, tabs.indices.contains(i) { tabs.remove(at: i) }
            tabs.sort { $0.loc < $1.loc }
            commitTabs()
        }
        dragging = .none
    }

    // MARK: - Hit testing

    private func marker(at p: CGPoint) -> Marker {
        let topZone = p.y > bounds.height / 2
        if topZone {
            if abs(p.x - (marginLeft + leftIndent + firstLineExtra)) <= hitTolerance { return .firstLine }
        } else {
            if abs(p.x - (marginLeft + leftIndent)) <= hitTolerance { return .left }
            if abs(p.x - (contentRightX - rightIndent)) <= hitTolerance { return .right }
            if let i = tabIndex(near: p.x) { return .tab(i) }
        }
        return .none
    }

    private func tabIndex(near x: CGFloat) -> Int? {
        for (i, tab) in tabs.enumerated() where abs(marginLeft + tab.loc - x) <= hitTolerance {
            return i
        }
        return nil
    }

    private func cycleTabKind(at i: Int) {
        guard tabs.indices.contains(i) else { return }
        let order: [TabStopModel.Kind] = [.left, .center, .right, .decimal]
        let next = order[(order.firstIndex(of: tabs[i].kind).map { $0 + 1 } ?? 0) % order.count]
        tabs[i].kind = next
    }

    // MARK: - Commit

    private func commitIndents() {
        editor?.setIndents(left: leftIndent, firstLine: firstLineExtra, right: rightIndent)
    }

    private func commitTabs() {
        let textTabs = tabs.map { tab -> NSTextTab in
            switch tab.kind {
            case .left:   return NSTextTab(textAlignment: .left, location: tab.loc)
            case .center: return NSTextTab(textAlignment: .center, location: tab.loc)
            case .right:  return NSTextTab(textAlignment: .right, location: tab.loc)
            case .decimal:
                let sep = Locale.current.decimalSeparator ?? "."
                return NSTextTab(textAlignment: .right, location: tab.loc,
                                 options: [.columnTerminators: CharacterSet(charactersIn: sep)])
            }
        }
        editor?.setTabStops(textTabs)
        needsDisplay = true
    }

    private func clampTabLocation(_ loc: CGFloat) -> CGFloat { clamp(loc, 0, contentWidth) }
    private func clamp(_ v: CGFloat, _ lo: CGFloat, _ hi: CGFloat) -> CGFloat { min(max(v, lo), hi) }
}
