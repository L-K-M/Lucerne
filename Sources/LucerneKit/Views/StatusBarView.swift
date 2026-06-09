import AppKit

// A thin footer: contextual info on the left (current style, page count, or hover
// help) and a zoom control on the right (− / percentage / +). The window
// controller supplies the message text and handles the zoom callbacks.
public final class StatusBarView: NSView {

    private let label = NSTextField(labelWithString: "")
    private let zoomOutButton = NSButton()
    private let zoomField = NSButton()       // shows "100%"; click = reset to 100%
    private let zoomInButton = NSButton()

    public var message: String = "" {
        didSet { label.stringValue = message }
    }

    public var onZoomIn: (() -> Void)?
    public var onZoomOut: (() -> Void)?
    public var onZoomReset: (() -> Void)?

    public func setZoom(percent: Int) {
        zoomField.title = "\(percent)%"
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

        configureZoomButton(zoomOutButton, title: "−", action: #selector(zoomOut))
        configureZoomButton(zoomInButton, title: "+", action: #selector(zoomIn))
        zoomField.title = "100%"
        zoomField.bezelStyle = .inline
        zoomField.isBordered = false
        zoomField.font = NSFont.systemFont(ofSize: 11)
        zoomField.target = self
        zoomField.action = #selector(zoomReset)
        zoomField.toolTip = "Click to reset zoom to 100%"
        zoomField.translatesAutoresizingMaskIntoConstraints = false
        zoomField.widthAnchor.constraint(equalToConstant: 44).isActive = true

        let zoomStack = NSStackView(views: [zoomOutButton, zoomField, zoomInButton])
        zoomStack.orientation = .horizontal
        zoomStack.spacing = 2
        zoomStack.alignment = .centerY
        zoomStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(zoomStack)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.trailingAnchor.constraint(lessThanOrEqualTo: zoomStack.leadingAnchor, constant: -12),
            zoomStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            zoomStack.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private func configureZoomButton(_ button: NSButton, title: String, action: Selector) {
        button.title = title
        button.bezelStyle = .inline
        button.isBordered = false
        button.font = NSFont.systemFont(ofSize: 14)
        button.target = self
        button.action = action
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(equalToConstant: 22).isActive = true
    }

    @objc private func zoomIn() { onZoomIn?() }
    @objc private func zoomOut() { onZoomOut?() }
    @objc private func zoomReset() { onZoomReset?() }

    public override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSColor(calibratedWhite: 0.75, alpha: 1).setStroke()
        let top = NSBezierPath()
        top.move(to: CGPoint(x: 0, y: bounds.maxY - 0.5))
        top.line(to: CGPoint(x: bounds.width, y: bounds.maxY - 0.5))
        top.stroke()
    }
}
