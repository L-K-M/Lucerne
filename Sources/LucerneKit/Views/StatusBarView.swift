import AppKit

// A thin classic footer: engraved contextual info on the left (current style,
// page count, or hover help) and a momentary − / percent / + zoom cluster on the
// right, drawn with the same gradient-bezel chrome as the format bar. The window
// controller supplies the message text and handles the zoom callbacks. Like the
// rest of the chrome, it mutes when the window isn't active (the engraved label
// is re-set from the window's main/key notifications, since text color is view
// state rather than something resolved at draw time).
public final class StatusBarView: NSView {

    private let label = NSTextField(labelWithString: "")
    private var activationObservers: [NSObjectProtocol] = []
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
        didSet { refreshLabel() }
    }

    public var onZoomIn: (() -> Void)?
    public var onZoomOut: (() -> Void)?
    public var onZoomReset: (() -> Void)?

    public func setZoom(percent: Int) {
        zoomControl.setGlyph(.letter("\(percent)%", font: .systemFont(ofSize: 10)), forSegment: 1)
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

    deinit {
        activationObservers.forEach(NotificationCenter.default.removeObserver)
    }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        activationObservers.forEach(NotificationCenter.default.removeObserver)
        activationObservers = []
        guard let window else { return }
        let names: [Notification.Name] = [
            NSWindow.didBecomeMainNotification, NSWindow.didResignMainNotification,
            NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification
        ]
        for name in names {
            activationObservers.append(NotificationCenter.default.addObserver(
                forName: name, object: window, queue: .main) { [weak self] _ in
                    self?.refreshLabel()
                })
        }
        refreshLabel()
    }

    private func refreshLabel() {
        label.attributedStringValue = ClassicText.engraved(
            message, size: 11, active: ClassicChrome.active(for: self))
    }

    @objc private func zoomClicked() {
        switch zoomControl.selectedSegment {
        case 0: onZoomOut?()
        case 1: onZoomReset?()
        case 2: onZoomIn?()
        default: break
        }
    }

    public override func draw(_ dirtyRect: NSRect) {
        let active = ClassicChrome.active(for: self)
        ClassicChrome.gradient(top: active ? 0.94 : 0.965,
                               bottom: active ? 0.78 : 0.885).draw(in: bounds, angle: 90)
        ClassicChrome.barBottomBorder(active).setFill()  // top border, mirroring the format bar's bottom
        NSRect(x: 0, y: bounds.height - 1, width: bounds.width, height: 1).fill()
        ClassicChrome.barTopHighlight.setFill()          // etched highlight just under it
        NSRect(x: 0, y: bounds.height - 2, width: bounds.width, height: 1).fill()
    }
}
