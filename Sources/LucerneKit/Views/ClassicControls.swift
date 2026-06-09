import AppKit

// Hand-drawn "classic" chrome for the format bar, in the spirit of the iWork '09
// era: gradient bezels, etched group separators, and glyphs drawn with paths
// instead of symbol images. Everything is drawn at 1 pt hairline scale; the
// document window pins itself to the light (aqua) appearance, so these colors
// are fixed rather than semantic.
enum ClassicChrome {

    static let controlHeight: CGFloat = 20
    static let cornerRadius: CGFloat = 3.5

    static let barTopHighlight = NSColor(calibratedWhite: 1.0, alpha: 0.6)
    static let barBottomBorder = NSColor(calibratedWhite: 0.45, alpha: 1)

    static let bezelBorder = NSColor(calibratedWhite: 0.47, alpha: 1)
    static let glyphColor = NSColor(calibratedWhite: 0.18, alpha: 1)
    static let titleColor = NSColor(calibratedWhite: 0.13, alpha: 1)
    static let arrowColor = NSColor(calibratedWhite: 0.25, alpha: 1)
    static let segmentSeparator = NSColor(calibratedWhite: 0.55, alpha: 1)

    enum BezelState { case normal, on, pressed }

    static func bezelGradient(_ state: BezelState) -> NSGradient {
        switch state {
        case .normal: return gradient(top: 1.00, bottom: 0.86)
        case .on: return gradient(top: 0.68, bottom: 0.82)
        case .pressed: return gradient(top: 0.60, bottom: 0.74)
        }
    }

    static func gradient(top: CGFloat, bottom: CGFloat) -> NSGradient {
        NSGradient(starting: NSColor(calibratedWhite: bottom, alpha: 1),
                   ending: NSColor(calibratedWhite: top, alpha: 1))!
    }

    /// Rounded outline inset for a crisp 1 pt border stroke.
    static func bezelOutline(in bounds: NSRect, radius: CGFloat = ClassicChrome.cornerRadius) -> NSBezierPath {
        NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: radius, yRadius: radius)
    }

    /// The 1 pt hint line just inside the top border: a light gloss on raised
    /// bezels, a dark seam on sunken (on/pressed) ones.
    static func drawInnerHint(_ state: BezelState, in rect: NSRect) {
        switch state {
        case .normal: NSColor(calibratedWhite: 1.0, alpha: 0.55).setFill()
        case .on, .pressed: NSColor(calibratedWhite: 0.25, alpha: 0.22).setFill()
        }
        NSRect(x: rect.minX, y: rect.maxY - 2, width: rect.width, height: 1).fill()
    }
}

// MARK: - Glyphs

/// What gets drawn centered inside a bezel segment: a styled letter (B/I/U) or a
/// little stack of alignment bars, both drawn in code so they read crisply at
/// 11–12 pt like the originals.
enum ClassicGlyph {
    case text(NSAttributedString)
    case alignment(NSTextAlignment)

    static func letter(_ string: String, font: NSFont, underlined: Bool = false) -> ClassicGlyph {
        var attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: ClassicChrome.glyphColor
        ]
        if underlined { attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue }
        return .text(NSAttributedString(string: string, attributes: attrs))
    }

    func draw(centeredIn rect: NSRect) {
        switch self {
        case .text(let string):
            let size = string.size()
            string.draw(at: NSPoint(x: (rect.midX - size.width / 2).rounded(),
                                    y: (rect.midY - size.height / 2).rounded()))
        case .alignment(let alignment):
            drawAlignmentBars(alignment, in: rect)
        }
    }

    /// Four 1 pt text-line bars; odd rows are short and hug the glyph's edge per
    /// the alignment (all full for justified).
    private func drawAlignmentBars(_ alignment: NSTextAlignment, in rect: NSRect) {
        let full: CGFloat = 11
        let short: CGFloat = 7
        let left = (rect.midX - full / 2).rounded()
        var y = (rect.midY + 4).rounded()           // top row, working down in 3 pt steps
        ClassicChrome.glyphColor.setFill()
        for row in 0..<4 {
            let width = (alignment == .justified || row % 2 == 0) ? full : short
            let x: CGFloat
            switch alignment {
            case .center: x = left + ((full - width) / 2).rounded()
            case .right: x = left + (full - width)
            default: x = left
            }
            NSRect(x: x, y: y, width: width, height: 1).fill()
            y -= 3
        }
    }
}

// MARK: - Segmented control

/// A grouped row of gradient-bezel toggle buttons sharing one rounded outline,
/// split by hairlines — the classic B/I/U and alignment clusters. `selectOne`
/// keeps exactly one segment on; `selectAny` toggles each independently.
final class ClassicSegmentedControl: NSControl {

    enum Mode { case selectOne, selectAny }

    private let glyphs: [ClassicGlyph]
    private let mode: Mode
    private let segmentWidth: CGFloat
    private var isOn: [Bool]
    private var trackedSegment: Int?
    private var pressedSegment: Int?
    private(set) var selectedSegment: Int = -1   // the segment the user last clicked

    init(glyphs: [ClassicGlyph], mode: Mode, segmentWidth: CGFloat = 25) {
        self.glyphs = glyphs
        self.mode = mode
        self.segmentWidth = segmentWidth
        self.isOn = Array(repeating: false, count: glyphs.count)
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var intrinsicContentSize: NSSize {
        NSSize(width: segmentWidth * CGFloat(glyphs.count), height: ClassicChrome.controlHeight)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    func isSelected(forSegment index: Int) -> Bool {
        isOn.indices.contains(index) ? isOn[index] : false
    }

    func setSelected(_ flag: Bool, forSegment index: Int) {
        guard isOn.indices.contains(index) else { return }
        if mode == .selectOne, flag {
            isOn = Array(repeating: false, count: isOn.count)
            selectedSegment = index
        }
        isOn[index] = flag
        needsDisplay = true
    }

    // MARK: Tracking — highlight while pressed inside, commit on release inside.

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        trackedSegment = segment(at: convert(event.locationInWindow, from: nil))
        pressedSegment = trackedSegment
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let tracked = trackedSegment else { return }
        let current = segment(at: convert(event.locationInWindow, from: nil))
        let visible = (current == tracked) ? tracked : nil
        if visible != pressedSegment {
            pressedSegment = visible
            needsDisplay = true
        }
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            trackedSegment = nil
            pressedSegment = nil
            needsDisplay = true
        }
        guard let tracked = trackedSegment,
              segment(at: convert(event.locationInWindow, from: nil)) == tracked else { return }
        selectedSegment = tracked
        switch mode {
        case .selectOne:
            isOn = Array(repeating: false, count: isOn.count)
            isOn[tracked] = true
        case .selectAny:
            isOn[tracked].toggle()
        }
        sendAction(action, to: target)
    }

    private func segment(at point: NSPoint) -> Int? {
        guard bounds.contains(point), segmentWidth > 0 else { return nil }
        let index = Int(point.x / segmentWidth)
        return glyphs.indices.contains(index) ? index : nil
    }

    private func segmentRect(_ index: Int) -> NSRect {
        NSRect(x: CGFloat(index) * segmentWidth, y: 0, width: segmentWidth, height: bounds.height)
    }

    private func state(for index: Int) -> ClassicChrome.BezelState {
        if pressedSegment == index { return .pressed }
        return isOn[index] ? .on : .normal
    }

    override func draw(_ dirtyRect: NSRect) {
        let outline = ClassicChrome.bezelOutline(in: bounds)
        NSGraphicsContext.saveGraphicsState()
        outline.addClip()
        for index in glyphs.indices {
            let rect = segmentRect(index)
            ClassicChrome.bezelGradient(state(for: index)).draw(in: rect, angle: 90)
            ClassicChrome.drawInnerHint(state(for: index), in: rect)
        }
        ClassicChrome.segmentSeparator.setFill()
        for index in 1..<glyphs.count {
            NSRect(x: CGFloat(index) * segmentWidth - 0.5, y: 0, width: 1, height: bounds.height).fill()
        }
        NSGraphicsContext.restoreGraphicsState()
        ClassicChrome.bezelBorder.setStroke()
        outline.lineWidth = 1
        outline.stroke()
        for index in glyphs.indices {
            glyphs[index].draw(centeredIn: segmentRect(index))
        }
    }
}

// MARK: - Pop-up

/// A pop-up with the classic look: gradient bezel, hairline-separated arrow well
/// with stacked up/down chevrons, 11 pt title. The API mirrors the slice of
/// NSPopUpButton the toolbar uses, so callers read the same.
final class ClassicPopUp: NSControl {

    private let popMenu = NSMenu()
    private let fixedWidth: CGFloat
    private let arrowZoneWidth: CGFloat = 16
    private var isPressed = false
    private(set) var indexOfSelectedItem: Int = -1

    init(width: CGFloat) {
        self.fixedWidth = width
        super.init(frame: .zero)
        popMenu.autoenablesItems = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var intrinsicContentSize: NSSize {
        NSSize(width: fixedWidth, height: ClassicChrome.controlHeight)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    var titleOfSelectedItem: String? {
        popMenu.items.indices.contains(indexOfSelectedItem) ? popMenu.items[indexOfSelectedItem].title : nil
    }

    func addItems(withTitles titles: [String]) {
        for title in titles {
            let item = NSMenuItem(title: title, action: #selector(itemChosen(_:)), keyEquivalent: "")
            item.target = self
            popMenu.addItem(item)
        }
        if indexOfSelectedItem == -1, !popMenu.items.isEmpty { select(0, send: false) }
    }

    func selectItem(at index: Int) { select(index, send: false) }

    func selectItem(withTitle title: String) {
        if let index = popMenu.items.firstIndex(where: { $0.title == title }) {
            select(index, send: false)
        }
    }

    @objc private func itemChosen(_ sender: NSMenuItem) {
        let index = popMenu.index(of: sender)
        guard index >= 0 else { return }
        select(index, send: true)
    }

    private func select(_ index: Int, send: Bool) {
        guard popMenu.items.indices.contains(index) else { return }
        if indexOfSelectedItem != index {
            for (i, item) in popMenu.items.enumerated() { item.state = (i == index) ? .on : .off }
            indexOfSelectedItem = index
            needsDisplay = true
        }
        if send { sendAction(action, to: target) }
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        isPressed = true
        needsDisplay = true
        displayIfNeeded()
        popMenu.minimumWidth = bounds.width
        let positioning = popMenu.items.indices.contains(indexOfSelectedItem)
            ? popMenu.items[indexOfSelectedItem] : nil
        popMenu.popUp(positioning: positioning, at: NSPoint(x: 0, y: bounds.height + 1), in: self)
        isPressed = false
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let outline = ClassicChrome.bezelOutline(in: bounds)
        let state: ClassicChrome.BezelState = isPressed ? .pressed : .normal
        NSGraphicsContext.saveGraphicsState()
        outline.addClip()
        ClassicChrome.bezelGradient(state).draw(in: bounds, angle: 90)
        ClassicChrome.drawInnerHint(state, in: bounds)
        ClassicChrome.segmentSeparator.withAlphaComponent(0.7).setFill()
        NSRect(x: bounds.width - arrowZoneWidth - 0.5, y: 2, width: 1, height: bounds.height - 4).fill()
        NSGraphicsContext.restoreGraphicsState()
        ClassicChrome.bezelBorder.setStroke()
        outline.lineWidth = 1
        outline.stroke()
        drawTitle()
        drawArrows()
    }

    private func drawTitle() {
        guard let title = titleOfSelectedItem else { return }
        let ps = NSMutableParagraphStyle()
        ps.lineBreakMode = .byTruncatingTail
        let string = NSAttributedString(string: title, attributes: [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: ClassicChrome.titleColor,
            .paragraphStyle: ps
        ])
        let height = ceil(string.size().height)
        let rect = NSRect(x: 8, y: ((bounds.height - height) / 2).rounded(),
                          width: bounds.width - arrowZoneWidth - 12, height: height)
        string.draw(in: rect)
    }

    private func drawArrows() {
        let cx = bounds.width - arrowZoneWidth / 2 - 0.5
        let cy = bounds.height / 2
        ClassicChrome.arrowColor.setFill()
        let up = NSBezierPath()
        up.move(to: NSPoint(x: cx - 3.5, y: cy + 1.5))
        up.line(to: NSPoint(x: cx + 3.5, y: cy + 1.5))
        up.line(to: NSPoint(x: cx, y: cy + 5.5))
        up.close()
        up.fill()
        let down = NSBezierPath()
        down.move(to: NSPoint(x: cx - 3.5, y: cy - 1.5))
        down.line(to: NSPoint(x: cx + 3.5, y: cy - 1.5))
        down.line(to: NSPoint(x: cx, y: cy - 5.5))
        down.close()
        down.fill()
    }
}

// MARK: - Size field

/// The font-size control: a white inset text area you can type into, joined to a
/// gradient arrow well that pops a preset menu — the classic combo-field shape.
final class ClassicSizeField: NSView {

    var onCommit: ((String) -> Void)?

    var stringValue: String {
        get { field.stringValue }
        set { field.stringValue = newValue }
    }

    private let field = NSTextField()
    private let presets: [String]
    private let fixedWidth: CGFloat
    private let arrowZoneWidth: CGFloat = 15

    init(presets: [String], width: CGFloat) {
        self.presets = presets
        self.fixedWidth = width
        super.init(frame: .zero)
        field.font = NSFont.systemFont(ofSize: 11)
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.usesSingleLineMode = true
        field.target = self
        field.action = #selector(fieldCommitted)
        (field.cell as? NSTextFieldCell)?.sendsActionOnEndEditing = true
        addSubview(field)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var intrinsicContentSize: NSSize {
        NSSize(width: fixedWidth, height: ClassicChrome.controlHeight)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func layout() {
        super.layout()
        let height = field.intrinsicContentSize.height
        field.frame = NSRect(x: 5, y: ((bounds.height - height) / 2).rounded(),
                             width: bounds.width - arrowZoneWidth - 8, height: height)
    }

    @objc private func fieldCommitted() { onCommit?(field.stringValue) }

    // Clicks land here only outside the text field (its own area starts editing),
    // i.e. on the arrow well or bezel — pop the preset menu below the control.
    override func mouseDown(with event: NSEvent) {
        let menu = NSMenu()
        menu.autoenablesItems = false
        for preset in presets {
            let item = NSMenuItem(title: preset, action: #selector(presetChosen(_:)), keyEquivalent: "")
            item.target = self
            item.state = (preset == field.stringValue) ? .on : .off
            menu.addItem(item)
        }
        menu.minimumWidth = bounds.width
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: 0), in: self)
    }

    @objc private func presetChosen(_ sender: NSMenuItem) {
        field.stringValue = sender.title
        onCommit?(sender.title)
    }

    override func draw(_ dirtyRect: NSRect) {
        let outline = ClassicChrome.bezelOutline(in: bounds, radius: 3)
        NSGraphicsContext.saveGraphicsState()
        outline.addClip()
        NSColor.white.setFill()
        bounds.fill()
        let arrowZone = NSRect(x: bounds.width - arrowZoneWidth, y: 0,
                               width: arrowZoneWidth, height: bounds.height)
        ClassicChrome.bezelGradient(.normal).draw(in: arrowZone, angle: 90)
        NSColor(calibratedWhite: 0, alpha: 0.07).setFill()     // inset shadow on the text area
        NSRect(x: 0, y: bounds.height - 2, width: bounds.width - arrowZoneWidth, height: 1).fill()
        ClassicChrome.segmentSeparator.withAlphaComponent(0.7).setFill()
        NSRect(x: bounds.width - arrowZoneWidth - 0.5, y: 0, width: 1, height: bounds.height).fill()
        NSGraphicsContext.restoreGraphicsState()
        ClassicChrome.bezelBorder.setStroke()
        outline.lineWidth = 1
        outline.stroke()

        let cx = bounds.width - arrowZoneWidth / 2 - 0.5
        let cy = bounds.height / 2
        ClassicChrome.arrowColor.setFill()
        let down = NSBezierPath()
        down.move(to: NSPoint(x: cx - 3.5, y: cy + 2))
        down.line(to: NSPoint(x: cx + 3.5, y: cy + 2))
        down.line(to: NSPoint(x: cx, y: cy - 2.5))
        down.close()
        down.fill()
    }
}

// MARK: - Color well

/// NSColorWell behavior (click to drive the shared color panel) in a classic
/// shell: gradient bezel frame around a hairline-edged swatch; the bezel goes
/// sunken while the well is active.
final class ClassicColorWell: NSColorWell {

    override var color: NSColor {
        didSet { needsDisplay = true }
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 34, height: ClassicChrome.controlHeight)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func activate(_ exclusive: Bool) {
        super.activate(exclusive)
        needsDisplay = true
    }

    override func deactivate() {
        super.deactivate()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let outline = ClassicChrome.bezelOutline(in: bounds, radius: 3)
        let state: ClassicChrome.BezelState = isActive ? .on : .normal
        NSGraphicsContext.saveGraphicsState()
        outline.addClip()
        ClassicChrome.bezelGradient(state).draw(in: bounds, angle: 90)
        ClassicChrome.drawInnerHint(state, in: bounds)
        NSGraphicsContext.restoreGraphicsState()
        ClassicChrome.bezelBorder.setStroke()
        outline.lineWidth = 1
        outline.stroke()

        let swatch = bounds.insetBy(dx: 5, dy: 5)
        color.setFill()
        swatch.insetBy(dx: 1, dy: 1).fill()
        NSColor(calibratedWhite: 0.35, alpha: 1).setStroke()
        let frame = NSBezierPath(rect: swatch.insetBy(dx: 0.5, dy: 0.5))
        frame.lineWidth = 1
        frame.stroke()
    }
}

// MARK: - Etched separator

/// The two-hairline (dark + light) vertical divider between control groups.
final class EtchedSeparatorView: NSView {

    override var intrinsicContentSize: NSSize { NSSize(width: 2, height: 24) }

    override func draw(_ dirtyRect: NSRect) {
        NSColor(calibratedWhite: 0.58, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: 1, height: bounds.height).fill()
        NSColor(calibratedWhite: 1.0, alpha: 0.8).setFill()
        NSRect(x: 1, y: 0, width: 1, height: bounds.height).fill()
    }
}
