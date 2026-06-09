import AppKit

// A thin footer that shows contextual information: what the user is doing (current
// paragraph style + page count) or help for whatever they're hovering (a toolbar
// control, a placed image). The window controller decides what text to show; this
// view just displays it.
public final class StatusBarView: NSView {

    private let label = NSTextField(labelWithString: "")

    public var message: String = "" {
        didSet { label.stringValue = message }
    }

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor(calibratedWhite: 0.93, alpha: 1).cgColor

        label.font = NSFont.systemFont(ofSize: 11)
        label.textColor = NSColor(calibratedWhite: 0.25, alpha: 1)
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -12),
            label.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    public override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSColor(calibratedWhite: 0.75, alpha: 1).setStroke()
        let top = NSBezierPath()
        top.move(to: CGPoint(x: 0, y: bounds.maxY - 0.5))
        top.line(to: CGPoint(x: bounds.width, y: bounds.maxY - 0.5))
        top.stroke()
    }
}
