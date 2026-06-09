import AppKit

// A thin classic footer: engraved contextual info on the left (current style,
// page count, or hover help) and a momentary − / percent / + zoom cluster on the
// right, drawn with the same gradient-bezel chrome as the format bar. The window
// controller supplies the message text and handles the zoom callbacks.
public final class StatusBarView: NSView {

    private let label = NSTextField(labelWithString: "")
    private let zoomControl = ClassicSegmentedControl(
        glyphs: [
            .letter("−", font: .systemFont(ofSize: 12)),
            .letter("100%", font: .systemFont(ofSize: 10)),
            .letter("+", font: .systemFont(ofSize: 12))
        ],
        mode: .momentary,
        segmentWidths: [20, 44, 20],
        height: 17)

    public var message: String = "" {
        didSet { label.attributedStringValue = StatusBarView.engraved(message) }
    }

    public var onZoomIn: (() -> Void)?
    public var onZoomOut: (() -> Void)?
    public var onZoomReset: (() -> Void)?

    public func setZoom(percent: Int) {
        zoomControl.setGlyph(.letter("\(percent)%", font: .systemFont(ofSize: 10)), forSegment: 1)
    }

    /// Classic bar lettering: dark gray with a hard 1 pt white drop below, so the
    /// text reads as engraved into the gradient strip.
    private static func engraved(_ string: String) -> NSAttributedString {
        let shadow = NSShadow()
        shadow.shadowColor = NSColor(calibratedWhite: 1.0, alpha: 0.65)
        shadow.shadowOffset = NSSize(width: 0, height: -1)
        shadow.shadowBlurRadius = 0
        return NSAttributedString(string: string, attributes: [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor(calibratedWhite: 0.22, alpha: 1),
            .shadow: shadow
        ])
    }

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        zoomControl.target = self
        zoomControl.action = #selector(zoomClicked)
        zoomControl.toolTip = "Zoom out · click the percentage to reset to 100% · zoom in"
        zoomControl.translatesAutoresizingMaskIntoConstraints = false
        addSubview(zoomControl)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.trailingAnchor.constraint(lessThanOrEqualTo: zoomControl.leadingAnchor, constant: -12),
            zoomControl.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            zoomControl.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    @objc private func zoomClicked() {
        switch zoomControl.selectedSegment {
        case 0: onZoomOut?()
        case 1: onZoomReset?()
        case 2: onZoomIn?()
        default: break
        }
    }

    public override func draw(_ dirtyRect: NSRect) {
        ClassicChrome.gradient(top: 0.94, bottom: 0.78).draw(in: bounds, angle: 90)
        ClassicChrome.barBottomBorder.setFill()      // top border, mirroring the format bar's bottom
        NSRect(x: 0, y: bounds.height - 1, width: bounds.width, height: 1).fill()
        ClassicChrome.barTopHighlight.setFill()      // etched highlight just under it
        NSRect(x: 0, y: bounds.height - 2, width: bounds.width, height: 1).fill()
    }
}
