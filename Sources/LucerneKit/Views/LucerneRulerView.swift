import AppKit

// A horizontal ruler with draggable indent markers and tab stops. It spans the
// full window width (so its background and bottom border are continuous), and
// draws the measured scale aligned to the page below it: the page's on-screen
// origin and width are supplied via setPageGeometry(), so the scale tracks
// horizontal scroll and zoom. Document points map to x as:
//     x = pageOriginX + documentX * (pageOnScreenWidth / pageWidth)
//
// Tab stops are document-global (see EditorController.setTabStops); indents apply
// to the selected paragraphs. Hovering reports contextual help via onHoverHelp.
public final class LucerneRulerView: NSView {

    public weak var editor: EditorController?
    public var rulerHeight: CGFloat = 30
    public var onHoverHelp: ((String?) -> Void)?

    // Document geometry (points).
    private var marginLeft: CGFloat = 72
    private var marginRight: CGFloat = 72
    private var pageWidth: CGFloat = 595.28

    // The page's on-screen placement within this view (tracks scroll/zoom).
    private var pageOriginX: CGFloat = 0
    private var pageOnScreenWidth: CGFloat = 595.28

    // Active paragraph values, in document points from the left margin.
    private var leftIndent: CGFloat = 0
    private var firstLineExtra: CGFloat = 0
    private var rightIndent: CGFloat = 0
    private var tabs: [(loc: CGFloat, kind: TabStopModel.Kind)] = []

    // When the caret is in a table, the ruler switches to "column mode": it shows
    // draggable dividers for the table's column widths (normalised fractions summing
    // to 1) instead of the tab/indent markers. nil means not in a table.
    private var columnFractions: [CGFloat]?

    private enum Marker: Equatable { case none, left, firstLine, right, tab(Int), column(Int) }
    private var dragging: Marker = .none
    private var dragRemovedTab = false

    private let markerHalf: CGFloat = 6
    private let hitTolerance: CGFloat = 7

    public override var isFlipped: Bool { false }
    public override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: rulerHeight) }

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        toolTip = "Click in the white band to add a tab stop · double-click a tab to change its "
            + "type (left/center/right/decimal) · drag a tab to move it, or off the ruler to delete · "
            + "drag the triangles to set the paragraph indents."
        // Redraw when the ruler unit (Settings…) changes.
        NotificationCenter.default.addObserver(self, selector: #selector(preferencesChanged),
                                               name: Preferences.didChange, object: nil)
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    @objc private func preferencesChanged() { needsDisplay = true }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private var scale: CGFloat {
        (pageWidth > 0 && pageOnScreenWidth > 0) ? pageOnScreenWidth / pageWidth : 1
    }
    private func sx(_ documentX: CGFloat) -> CGFloat { pageOriginX + documentX * scale }
    private func documentX(_ x: CGFloat) -> CGFloat { (x - pageOriginX) / scale }

    private var contentWidth: CGFloat { max(0, pageWidth - marginLeft - marginRight) }
    private var contentRightX: CGFloat { pageWidth - marginRight }

    // MARK: - External updates

    public func updateGeometry(marginLeft: CGFloat, marginRight: CGFloat, pageWidth: CGFloat) {
        self.marginLeft = marginLeft
        self.marginRight = marginRight
        self.pageWidth = pageWidth
        needsDisplay = true
    }

    /// The page's left edge x and on-screen width within this (full-width) view.
    public func setPageGeometry(originX: CGFloat, onScreenWidth: CGFloat) {
        pageOriginX = originX
        pageOnScreenWidth = onScreenWidth
        needsDisplay = true
    }

    public func refresh() {
        // Column mode when the caret is in a table with at least two columns.
        if let widths = editor?.currentTableColumnWidths(), widths.count >= 2 {
            let total = widths.reduce(0, +)
            columnFractions = total > 0 ? widths.map { CGFloat($0 / total) } : nil
        } else {
            columnFractions = nil
        }
        guard let ps = editor?.selectedParagraphStyle() else { needsDisplay = true; return }
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
        let active = ClassicChrome.active(for: self)
        // Chrome strip outside the writable band, continuing the format bar's
        // classic look; the etched highlight under the bar's border seams them.
        ClassicChrome.gradient(top: active ? 0.93 : 0.955,
                               bottom: active ? 0.84 : 0.90).draw(in: bounds, angle: 90)
        NSColor(calibratedWhite: 1.0, alpha: 0.5).setFill()
        NSRect(x: 0, y: h - 1, width: bounds.width, height: 1).fill()

        let band = NSRect(x: sx(marginLeft), y: 0, width: contentWidth * scale, height: h)
        NSColor.white.setFill()
        band.fill()
        NSColor(calibratedWhite: active ? 0.72 : 0.80, alpha: 1).setFill()    // hairline band edges
        NSRect(x: band.minX - 1, y: 0, width: 1, height: h).fill()
        NSRect(x: band.maxX, y: 0, width: 1, height: h).fill()

        NSColor(calibratedWhite: active ? 0.55 : 0.68, alpha: 1).setStroke()
        let labelAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 8),
            .foregroundColor: NSColor(calibratedWhite: active ? 0.4 : 0.58, alpha: 1)
        ]
        // Unit-aware ticks: a labelled major tick every unit (cm or inch), a medium
        // tick at the half mark, and minor ticks at the unit's subdivisions.
        let unit = Preferences.rulerUnit
        let perUnit = unit.pointsPerUnit
        let subdivisions = max(1, unit.subdivisions)
        let minorStep = perUnit / CGFloat(subdivisions)
        let tickBottom: CGFloat = 3            // ticks rise from the bottom; numbers sit on top
        var tick = 0
        var p: CGFloat = 0
        while p <= contentWidth + 0.5 {
            let x = sx(marginLeft + p)
            let isMajor = tick % subdivisions == 0
            let isMedium = subdivisions % 2 == 0 && tick % (subdivisions / 2) == 0
            let tickHeight: CGFloat = isMajor ? 9 : (isMedium ? 6 : 4)
            let path = NSBezierPath()
            path.move(to: CGPoint(x: x, y: tickBottom))
            path.line(to: CGPoint(x: x, y: tickBottom + tickHeight))
            path.lineWidth = 1
            path.stroke()
            if isMajor && p > 0 {
                // Centered above the ticks: cm marks are close together and labels can
                // be two digits, so drawing beside a tick made the number overlap it.
                let label = "\(Int((p / perUnit).rounded()))" as NSString
                let size = label.size(withAttributes: labelAttrs)
                label.draw(at: CGPoint(x: x - size.width / 2, y: h - size.height - 1), withAttributes: labelAttrs)
            }
            tick += 1
            p += minorStep
        }

        NSColor(calibratedWhite: active ? 0.55 : 0.68, alpha: 1).setStroke()
        let border = NSBezierPath()
        border.move(to: CGPoint(x: 0, y: 0.5))
        border.line(to: CGPoint(x: bounds.width, y: 0.5))
        border.stroke()

        if columnFractions != nil {
            drawColumnDividers(height: h, active: active)   // table mode: column dividers only
        } else {
            drawIndentMarkers(height: h, active: active)
            drawTabMarkers(active: active)
        }
    }

    /// Marker tint: the accent color on the active window, classic gray when muted.
    private func markerColor(active: Bool) -> NSColor {
        active ? .controlAccentColor : NSColor(calibratedWhite: 0.62, alpha: 1)
    }

    private func drawColumnDividers(height h: CGFloat, active: Bool) {
        guard let fractions = columnFractions, fractions.count >= 2 else { return }
        markerColor(active: active).setStroke()
        markerColor(active: active).setFill()
        var cumulative: CGFloat = 0
        for k in 0 ..< (fractions.count - 1) {
            cumulative += fractions[k]
            let x = sx(marginLeft + cumulative * contentWidth)
            let line = NSBezierPath()
            line.move(to: CGPoint(x: x, y: 2))
            line.line(to: CGPoint(x: x, y: h - 2))
            line.lineWidth = 1
            line.stroke()
            let s: CGFloat = 4                  // a small diamond handle at mid-height
            let handle = NSBezierPath()
            handle.move(to: CGPoint(x: x, y: h / 2 - s))
            handle.line(to: CGPoint(x: x + s, y: h / 2))
            handle.line(to: CGPoint(x: x, y: h / 2 + s))
            handle.line(to: CGPoint(x: x - s, y: h / 2))
            handle.close()
            handle.fill()
        }
    }

    private func drawIndentMarkers(height h: CGFloat, active: Bool) {
        markerColor(active: active).setFill()
        fillTriangle(centerX: sx(marginLeft + leftIndent + firstLineExtra), baseY: h, pointingDown: true)
        fillTriangle(centerX: sx(marginLeft + leftIndent), baseY: 0, pointingDown: false)
        fillTriangle(centerX: sx(contentRightX - rightIndent), baseY: 0, pointingDown: false)
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

    /// Tab stops drawn as solid 2 pt pennants (pixel-aligned stem + foot, with a
    /// dot for decimal) — the filled, hand-set weight of the rest of the chrome,
    /// replacing the earlier thin stroked glyphs.
    private func drawTabMarkers(active: Bool) {
        NSColor(calibratedWhite: active ? 0.28 : 0.52, alpha: 1).setFill()
        for tab in tabs {
            let x = sx(marginLeft + tab.loc).rounded()
            let y: CGFloat = 3
            NSRect(x: x - 1, y: y, width: 2, height: 9).fill()              // stem
            switch tab.kind {
            case .left:
                NSRect(x: x - 1, y: y, width: 7, height: 2).fill()          // foot → right
            case .right:
                NSRect(x: x - 6, y: y, width: 7, height: 2).fill()          // foot → left
            case .center:
                NSRect(x: x - 5, y: y, width: 10, height: 2).fill()         // centered foot
            case .decimal:
                NSRect(x: x - 5, y: y, width: 10, height: 2).fill()
                NSBezierPath(ovalIn: NSRect(x: x + 3, y: y + 4, width: 3, height: 3)).fill()
            }
        }
    }

    // MARK: - Mouse

    public override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        dragRemovedTab = false

        if columnFractions != nil {
            dragging = columnMarker(at: p)   // table mode: drag column dividers only
            return
        }

        if event.clickCount == 2, let i = tabIndex(near: p.x) {
            cycleTabKind(at: i)
            commitTabs()
            return
        }

        dragging = marker(at: p)
        if dragging == .none, p.x >= sx(marginLeft), p.x <= sx(contentRightX) {
            let loc = clampTabLocation(documentX(p.x) - marginLeft)
            tabs.append((loc: loc, kind: .left))
            tabs.sort { $0.loc < $1.loc }
            // Recover the new tab by its exact location, not by hit-testing:
            // tabIndex(near:) returns the *first* tab within tolerance, so a click
            // near an existing tab would grab that one and strand the new tab.
            let inserted = tabs.firstIndex { $0.loc == loc && $0.kind == .left }
            dragging = .tab(inserted ?? tabs.count - 1)
            needsDisplay = true
        }
    }

    public override func mouseDragged(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        let docPoint = documentX(p.x) - marginLeft

        switch dragging {
        case .none:
            return
        case .left:
            leftIndent = clamp(docPoint, 0, contentWidth)
        case .firstLine:
            firstLineExtra = clamp(docPoint, 0, contentWidth) - leftIndent
        case .right:
            rightIndent = clamp(contentWidth - docPoint, 0, contentWidth - leftIndent)
        case .tab(let i):
            guard tabs.indices.contains(i) else { return }
            dragRemovedTab = p.y < -hitTolerance || p.y > bounds.height + hitTolerance
            tabs[i].loc = clampTabLocation(docPoint)
        case .column(let k):
            guard var fractions = columnFractions, k + 1 < fractions.count, contentWidth > 0 else { return }
            let boundary = clamp((documentX(p.x) - marginLeft) / contentWidth, 0, 1)
            let leftEdge = fractions[0 ..< k].reduce(0, +)
            let combined = fractions[k] + fractions[k + 1]
            let minFraction: CGFloat = 0.05
            let newK = clamp(boundary - leftEdge, minFraction, combined - minFraction)
            fractions[k] = newK
            fractions[k + 1] = combined - newK
            columnFractions = fractions
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
        case .column:
            if let fractions = columnFractions {
                editor?.setCurrentTableColumnWidths(fractions.map { Double($0 * 100) })
            }
        }
        dragging = .none
    }

    // MARK: - Hover help

    public override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self, userInfo: nil))
    }

    public override func mouseMoved(with event: NSEvent) {
        onHoverHelp?(help(at: convert(event.locationInWindow, from: nil)))
    }

    public override func mouseExited(with event: NSEvent) {
        onHoverHelp?(nil)
    }

    private func help(at p: CGPoint) -> String? {
        switch marker(at: p) {
        case .column:
            return "Column divider — drag to resize the table's columns"
        case .tab:
            return "Tab stop — double-click to change type (left/center/right/decimal), "
                + "drag to move, or drag off the ruler to delete"
        case .left, .firstLine, .right:
            return "Indent marker — drag to set the paragraph's indent"
        case .none:
            if columnFractions != nil { return nil }   // table mode: no tab-adding
            if p.x >= sx(marginLeft), p.x <= sx(contentRightX) {
                return "Click to add a tab stop"
            }
            return nil
        }
    }

    // MARK: - Hit testing (screen space)

    private func columnMarker(at p: CGPoint) -> Marker {
        guard let fractions = columnFractions, fractions.count >= 2 else { return .none }
        var cumulative: CGFloat = 0
        for k in 0 ..< (fractions.count - 1) {
            cumulative += fractions[k]
            if abs(p.x - sx(marginLeft + cumulative * contentWidth)) <= hitTolerance { return .column(k) }
        }
        return .none
    }

    private func marker(at p: CGPoint) -> Marker {
        if columnFractions != nil { return columnMarker(at: p) }
        if p.y > bounds.height / 2 {
            if abs(p.x - sx(marginLeft + leftIndent + firstLineExtra)) <= hitTolerance { return .firstLine }
        } else {
            if abs(p.x - sx(marginLeft + leftIndent)) <= hitTolerance { return .left }
            if abs(p.x - sx(contentRightX - rightIndent)) <= hitTolerance { return .right }
            if let i = tabIndex(near: p.x) { return .tab(i) }
        }
        return .none
    }

    private func tabIndex(near x: CGFloat) -> Int? {
        for (i, tab) in tabs.enumerated() where abs(sx(marginLeft + tab.loc) - x) <= hitTolerance {
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
