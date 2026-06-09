import AppKit

public protocol FloatingImageViewDelegate: AnyObject {
    func floatingImageViewDidSelect(_ view: FloatingImageView)
    /// Live during a drag/resize — update the model and reflow text, no undo step.
    func floatingImageView(_ view: FloatingImageView, didChangeFrameLive frame: CGRect)
    /// Gesture finished — register a single undo step for the whole move/resize.
    func floatingImageView(_ view: FloatingImageView, didCommitFrom oldFrame: CGRect, to newFrame: CGRect)
    func floatingImageViewRequestsDelete(_ view: FloatingImageView)
}

// A free-placed image: a draggable, resizable view sitting above the page text.
// Its frame in the (flipped) page view *is* the object's page-relative model frame.
public final class FloatingImageView: NSView {

    public let objectID: String
    public weak var delegate: FloatingImageViewDelegate?

    public var image: NSImage? { didSet { needsDisplay = true } }
    public var placeholderLabel: String = "Image"
    public var standoff: CGFloat = 12
    public var isSelected = false { didSet { needsDisplay = true } }

    private enum DragMode { case none, move, resizeTL, resizeTR, resizeBL, resizeBR }
    private var dragMode: DragMode = .none
    private var dragOrigin: CGPoint = .zero          // in superview coords
    private var frameAtDragStart: CGRect = .zero
    private let handleSize: CGFloat = 9
    private let minSize: CGFloat = 24

    public override var isFlipped: Bool { true }
    public override var acceptsFirstResponder: Bool { true }
    public override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    public init(objectID: String, frame: CGRect) {
        self.objectID = objectID
        super.init(frame: frame)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    // MARK: - Drawing

    public override func draw(_ dirtyRect: NSRect) {
        let b = bounds
        if let image {
            image.draw(in: b, from: .zero, operation: .sourceOver, fraction: 1,
                       respectFlipped: true, hints: nil)
        } else {
            NSColor(calibratedWhite: 0.93, alpha: 1).setFill()
            b.fill()
            let outline = NSBezierPath(rect: b.insetBy(dx: 1, dy: 1))
            outline.lineWidth = 1
            outline.setLineDash([5, 3], count: 2, phase: 0)
            NSColor(calibratedWhite: 0.6, alpha: 1).setStroke()
            outline.stroke()
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 11),
                .foregroundColor: NSColor(calibratedWhite: 0.45, alpha: 1)
            ]
            let label = placeholderLabel as NSString
            let size = label.size(withAttributes: attrs)
            label.draw(at: CGPoint(x: b.midX - size.width / 2, y: b.midY - size.height / 2),
                       withAttributes: attrs)
        }

        if isSelected {
            let border = NSBezierPath(rect: b.insetBy(dx: 1, dy: 1))
            border.lineWidth = 2
            NSColor.selectedContentBackgroundColor.setStroke()
            border.stroke()
            for handle in handleRects() {
                NSColor.white.setFill()
                handle.fill()
                let hp = NSBezierPath(rect: handle.insetBy(dx: 0.5, dy: 0.5))
                hp.lineWidth = 1
                NSColor.selectedContentBackgroundColor.setStroke()
                hp.stroke()
            }
        }
    }

    private func handleRects() -> [CGRect] {
        let b = bounds, h = handleSize
        return [
            CGRect(x: b.minX, y: b.minY, width: h, height: h),          // TL
            CGRect(x: b.maxX - h, y: b.minY, width: h, height: h),      // TR
            CGRect(x: b.minX, y: b.maxY - h, width: h, height: h),      // BL
            CGRect(x: b.maxX - h, y: b.maxY - h, width: h, height: h)   // BR
        ]
    }

    // MARK: - Mouse

    public override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        delegate?.floatingImageViewDidSelect(self)
        isSelected = true
        frameAtDragStart = frame
        dragOrigin = superview?.convert(event.locationInWindow, from: nil) ?? .zero
        dragMode = mode(forLocalPoint: convert(event.locationInWindow, from: nil))
    }

    private func mode(forLocalPoint p: CGPoint) -> DragMode {
        let rects = handleRects()
        if rects[0].contains(p) { return .resizeTL }
        if rects[1].contains(p) { return .resizeTR }
        if rects[2].contains(p) { return .resizeBL }
        if rects[3].contains(p) { return .resizeBR }
        return .move
    }

    public override func mouseDragged(with event: NSEvent) {
        guard let superview else { return }
        let cur = superview.convert(event.locationInWindow, from: nil)
        let dx = cur.x - dragOrigin.x
        let dy = cur.y - dragOrigin.y       // flipped: +dy is downward
        var f = frameAtDragStart

        switch dragMode {
        case .none, .move:
            f.origin.x += dx
            f.origin.y += dy
        case .resizeBR:
            f.size.width += dx
            f.size.height += dy
        case .resizeTR:
            f.size.width += dx
            f.origin.y += dy
            f.size.height -= dy
        case .resizeBL:
            f.origin.x += dx
            f.size.width -= dx
            f.size.height += dy
        case .resizeTL:
            f.origin.x += dx
            f.size.width -= dx
            f.origin.y += dy
            f.size.height -= dy
        }

        if f.size.width < minSize {
            if dragMode == .resizeTL || dragMode == .resizeBL { f.origin.x = f.maxX - minSize }
            f.size.width = minSize
        }
        if f.size.height < minSize {
            if dragMode == .resizeTL || dragMode == .resizeTR { f.origin.y = f.maxY - minSize }
            f.size.height = minSize
        }

        frame = f
        delegate?.floatingImageView(self, didChangeFrameLive: f)
    }

    public override func mouseUp(with event: NSEvent) {
        dragMode = .none
        if frame != frameAtDragStart {
            delegate?.floatingImageView(self, didCommitFrom: frameAtDragStart, to: frame)
        }
    }

    // MARK: - Keyboard

    public override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 51, 117:                    // delete, forward-delete
            delegate?.floatingImageViewRequestsDelete(self)
        default:
            super.keyDown(with: event)
        }
    }

    public override func resetCursorRects() {
        addCursorRect(bounds, cursor: .openHand)
        if isSelected {
            for handle in handleRects() {
                addCursorRect(handle, cursor: .crosshair)
            }
        }
    }
}
