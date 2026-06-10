import AppKit

// Hand-drawn "classic" chrome for the format bar, ruler, status bar, and welcome
// screen, in the spirit of the iWork '09 era: gradient bezels, etched group
// separators, and glyphs drawn with paths instead of symbol images. Everything is
// drawn at 1 pt hairline scale and pinned to the light appearance by the windows.
//
// Like the classic Mac chrome it emulates, every surface mutes when its window is
// not active: colors are resolved through functions taking an `active` flag, and
// ClassicChromeActivation redraws a ClassicWindow's view tree when its main/key
// state changes.
enum ClassicChrome {

    static let controlHeight: CGFloat = 20
    static let cornerRadius: CGFloat = 3.5

    static let barTopHighlight = NSColor(calibratedWhite: 1.0, alpha: 0.6)

    /// Whether a view's chrome should draw at full strength: its window is the
    /// main or key window (popovers count as key while in use).
    static func active(for view: NSView?) -> Bool {
        guard let window = view?.window else { return true }
        return window.isMainWindow || window.isKeyWindow
    }

    static func barBottomBorder(_ active: Bool) -> NSColor {
        NSColor(calibratedWhite: active ? 0.45 : 0.60, alpha: 1)
    }
    static func bezelBorder(_ active: Bool) -> NSColor {
        NSColor(calibratedWhite: active ? 0.47 : 0.65, alpha: 1)
    }
    static func glyphColor(_ active: Bool) -> NSColor {
        NSColor(calibratedWhite: active ? 0.18 : 0.45, alpha: 1)
    }
    static func titleColor(_ active: Bool) -> NSColor {
        NSColor(calibratedWhite: active ? 0.13 : 0.45, alpha: 1)
    }
    static func arrowColor(_ active: Bool) -> NSColor {
        NSColor(calibratedWhite: active ? 0.25 : 0.50, alpha: 1)
    }
    static func segmentSeparator(_ active: Bool) -> NSColor {
        NSColor(calibratedWhite: active ? 0.55 : 0.70, alpha: 1)
    }

    enum BezelState { case normal, on, pressed }

    static func bezelGradient(_ state: BezelState, active: Bool) -> NSGradient {
        guard active else {
            switch state {
            case .normal: return gradient(top: 0.99, bottom: 0.94)
            case .on: return gradient(top: 0.84, bottom: 0.90)
            case .pressed: return gradient(top: 0.60, bottom: 0.74)
            }
        }
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
    static func drawInnerHint(_ state: BezelState, in rect: NSRect, active: Bool) {
        switch state {
        case .normal: NSColor(calibratedWhite: 1.0, alpha: active ? 0.55 : 0.35).setFill()
        case .on, .pressed: NSColor(calibratedWhite: 0.25, alpha: active ? 0.22 : 0.12).setFill()
        }
        NSRect(x: rect.minX, y: rect.maxY - 2, width: rect.width, height: 1).fill()
    }

    // MARK: Window silhouette

    /// The classic pre–Big Sur window shape: standard rounded top corners over
    /// gently rounded bottom corners. Shared by ClassicWindow's corner mask and
    /// the floating palettes' hand-drawn chrome, so every Lucerne window —
    /// document or palette — has the same silhouette.
    static let windowTopCornerRadius: CGFloat = 10   // ≈ the system's own top radius
    static let windowBottomCornerRadius: CGFloat = 5

    static func windowSilhouette(in rect: NSRect,
                                 top: CGFloat = windowTopCornerRadius,
                                 bottom: CGFloat = windowBottomCornerRadius) -> NSBezierPath {
        let path = NSBezierPath()
        path.move(to: NSPoint(x: rect.minX + bottom, y: rect.minY))
        path.line(to: NSPoint(x: rect.maxX - bottom, y: rect.minY))
        path.appendArc(withCenter: NSPoint(x: rect.maxX - bottom, y: rect.minY + bottom),
                       radius: bottom, startAngle: 270, endAngle: 360)
        path.line(to: NSPoint(x: rect.maxX, y: rect.maxY - top))
        path.appendArc(withCenter: NSPoint(x: rect.maxX - top, y: rect.maxY - top),
                       radius: top, startAngle: 0, endAngle: 90)
        path.line(to: NSPoint(x: rect.minX + top, y: rect.maxY))
        path.appendArc(withCenter: NSPoint(x: rect.minX + top, y: rect.maxY - top),
                       radius: top, startAngle: 90, endAngle: 180)
        path.line(to: NSPoint(x: rect.minX, y: rect.minY + bottom))
        path.appendArc(withCenter: NSPoint(x: rect.minX + bottom, y: rect.minY + bottom),
                       radius: bottom, startAngle: 180, endAngle: 270)
        path.close()
        return path
    }

    /// Stacked up/down chevrons (the pop-up arrow well glyph), centered at `cx/cy`.
    static func drawStackedChevrons(cx: CGFloat, cy: CGFloat, active: Bool) {
        arrowColor(active).setFill()
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

// MARK: - Activation redraw

/// Repaints a ClassicWindow's whole view tree when its main/key state changes,
/// so chrome drawn through `ClassicChrome.active(for:)` mutes and un-mutes like
/// the classic title bar does. Installed once, from ClassicWindow's initializer.
enum ClassicChromeActivation {

    private static var installed = false

    static func install() {
        guard !installed else { return }
        installed = true
        let names: [Notification.Name] = [
            NSWindow.didBecomeMainNotification, NSWindow.didResignMainNotification,
            NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification
        ]
        for name in names {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { note in
                guard let window = note.object as? NSWindow, window is ClassicWindow else { return }
                invalidate(window.contentView)
            }
        }
    }

    private static func invalidate(_ view: NSView?) {
        guard let view else { return }
        view.needsDisplay = true
        view.subviews.forEach { invalidate($0) }
    }
}

// MARK: - Glyphs

/// What gets drawn centered inside a bezel segment: a styled letter (B/I/U) or a
/// little stack of alignment bars, both drawn in code so they read crisply at
/// 11–12 pt like the originals. Color is resolved at draw time so glyphs mute
/// with their window.
enum ClassicGlyph {
    case text(String, NSFont, underlined: Bool)
    case alignment(NSTextAlignment)

    static func letter(_ string: String, font: NSFont, underlined: Bool = false) -> ClassicGlyph {
        .text(string, font, underlined: underlined)
    }

    func draw(centeredIn rect: NSRect, active: Bool) {
        switch self {
        case .text(let string, let font, let underlined):
            var attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: ClassicChrome.glyphColor(active)
            ]
            if underlined { attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue }
            let styled = NSAttributedString(string: string, attributes: attrs)
            let size = styled.size()
            styled.draw(at: NSPoint(x: (rect.midX - size.width / 2).rounded(),
                                    y: (rect.midY - size.height / 2).rounded()))
        case .alignment(let alignment):
            drawAlignmentBars(alignment, in: rect, active: active)
        }
    }

    /// Four 1 pt text-line bars; odd rows are short and hug the glyph's edge per
    /// the alignment (all full for justified).
    private func drawAlignmentBars(_ alignment: NSTextAlignment, in rect: NSRect, active: Bool) {
        let full: CGFloat = 11
        let short: CGFloat = 7
        let left = (rect.midX - full / 2).rounded()
        var y = (rect.midY + 4).rounded()           // top row, working down in 3 pt steps
        ClassicChrome.glyphColor(active).setFill()
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

/// A grouped row of gradient-bezel buttons sharing one rounded outline, split by
/// hairlines — the classic B/I/U and alignment clusters. `selectOne` keeps
/// exactly one segment on; `selectAny` toggles each independently; `momentary`
/// only flashes pressed and reports the click (the status bar's zoom cluster).
final class ClassicSegmentedControl: NSControl {

    enum Mode { case selectOne, selectAny, momentary }

    private var glyphs: [ClassicGlyph]
    private let mode: Mode
    private let widths: [CGFloat]
    private let controlHeight: CGFloat
    private var isOn: [Bool]
    private var trackedSegment: Int?
    private var pressedSegment: Int?
    private(set) var selectedSegment: Int = -1   // the segment the user last clicked

    init(glyphs: [ClassicGlyph], mode: Mode, segmentWidth: CGFloat = 25,
         segmentWidths: [CGFloat]? = nil, height: CGFloat = ClassicChrome.controlHeight) {
        self.glyphs = glyphs
        self.mode = mode
        self.widths = segmentWidths ?? Array(repeating: segmentWidth, count: glyphs.count)
        self.controlHeight = height
        self.isOn = Array(repeating: false, count: glyphs.count)
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var intrinsicContentSize: NSSize {
        NSSize(width: widths.reduce(0, +), height: controlHeight)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    func setGlyph(_ glyph: ClassicGlyph, forSegment index: Int) {
        guard glyphs.indices.contains(index) else { return }
        glyphs[index] = glyph
        needsDisplay = true
    }

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
        case .momentary:
            break
        }
        sendAction(action, to: target)
    }

    private func segment(at point: NSPoint) -> Int? {
        guard bounds.contains(point) else { return nil }
        var x: CGFloat = 0
        for (index, width) in widths.enumerated() {
            if point.x < x + width { return index }
            x += width
        }
        return nil
    }

    private func segmentRect(_ index: Int) -> NSRect {
        let x = widths.prefix(index).reduce(0, +)
        return NSRect(x: x, y: 0, width: widths[index], height: bounds.height)
    }

    private func state(for index: Int) -> ClassicChrome.BezelState {
        if pressedSegment == index { return .pressed }
        return isOn[index] ? .on : .normal
    }

    override func draw(_ dirtyRect: NSRect) {
        let active = ClassicChrome.active(for: self)
        let outline = ClassicChrome.bezelOutline(in: bounds)
        NSGraphicsContext.saveGraphicsState()
        outline.addClip()
        for index in glyphs.indices {
            let rect = segmentRect(index)
            ClassicChrome.bezelGradient(state(for: index), active: active).draw(in: rect, angle: 90)
            ClassicChrome.drawInnerHint(state(for: index), in: rect, active: active)
        }
        ClassicChrome.segmentSeparator(active).setFill()
        var boundary: CGFloat = 0
        for width in widths.dropLast() {
            boundary += width
            NSRect(x: boundary - 0.5, y: 0, width: 1, height: bounds.height).fill()
        }
        NSGraphicsContext.restoreGraphicsState()
        ClassicChrome.bezelBorder(active).setStroke()
        outline.lineWidth = 1
        outline.stroke()
        for index in glyphs.indices {
            glyphs[index].draw(centeredIn: segmentRect(index), active: active)
        }
    }
}

// MARK: - Pop-up

/// A pop-up with the classic look: gradient bezel, hairline-separated arrow well
/// with stacked up/down chevrons, 11 pt title. The API mirrors the slice of
/// NSPopUpButton the toolbar uses, so callers read the same. Subclasses can
/// override `presentChoices()` to show something other than the item menu.
class ClassicPopUp: NSControl {

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

    /// What the closed control shows; the menu-backed default is the selection.
    var displayTitle: String? { titleOfSelectedItem }

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

    /// Subclass hook: the bezel state the control draws in when idle (a chooser
    /// deferring to an open floating palette draws sunken).
    var idleBezelState: ClassicChrome.BezelState { .normal }

    /// Subclass hook: the glyph in the hairline arrow well — stacked chevrons by
    /// default.
    func drawArrowWellGlyph(cx: CGFloat, cy: CGFloat, active: Bool) {
        ClassicChrome.drawStackedChevrons(cx: cx, cy: cy, active: active)
    }

    /// Presents the control's chooser; the default pops the item menu over the
    /// control like NSPopUpButton.
    func presentChoices() {
        popMenu.minimumWidth = bounds.width
        let positioning = popMenu.items.indices.contains(indexOfSelectedItem)
            ? popMenu.items[indexOfSelectedItem] : nil
        popMenu.popUp(positioning: positioning, at: NSPoint(x: 0, y: bounds.height + 1), in: self)
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        isPressed = true
        needsDisplay = true
        displayIfNeeded()
        presentChoices()
        isPressed = false
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let active = ClassicChrome.active(for: self)
        let outline = ClassicChrome.bezelOutline(in: bounds)
        let state: ClassicChrome.BezelState = isPressed ? .pressed : idleBezelState
        NSGraphicsContext.saveGraphicsState()
        outline.addClip()
        ClassicChrome.bezelGradient(state, active: active).draw(in: bounds, angle: 90)
        ClassicChrome.drawInnerHint(state, in: bounds, active: active)
        ClassicChrome.segmentSeparator(active).withAlphaComponent(0.7).setFill()
        NSRect(x: bounds.width - arrowZoneWidth - 0.5, y: 2, width: 1, height: bounds.height - 4).fill()
        NSGraphicsContext.restoreGraphicsState()
        ClassicChrome.bezelBorder(active).setStroke()
        outline.lineWidth = 1
        outline.stroke()
        drawTitle(active: active)
        drawArrowWellGlyph(cx: bounds.width - arrowZoneWidth / 2 - 0.5,
                           cy: bounds.height / 2, active: active)
    }

    private func drawTitle(active: Bool) {
        guard let title = displayTitle else { return }
        let ps = NSMutableParagraphStyle()
        ps.lineBreakMode = .byTruncatingTail
        let string = NSAttributedString(string: title, attributes: [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: ClassicChrome.titleColor(active),
            .paragraphStyle: ps
        ])
        let height = ceil(string.size().height)
        let rect = NSRect(x: 8, y: ((bounds.height - height) / 2).rounded(),
                          width: bounds.width - arrowZoneWidth - 12, height: height)
        string.draw(in: rect)
    }
}

/// A ClassicPopUp shell whose click presents a custom chooser (the typeface or
/// style try-on picker) instead of an item menu; the closed control shows
/// `title`.
final class ClassicChooserControl: ClassicPopUp {

    var onPresent: (() -> Void)?

    var title: String = "" {
        didSet { needsDisplay = true }
    }

    /// When the control's chooser lives in the app-global floating palette, the
    /// control draws "engaged elsewhere": sunken bezel, and a tiny floating-
    /// window glyph in place of the chevrons. Clicking then summons the palette
    /// (the onPresent handler decides) instead of opening a second picker.
    var representsOpenPalette = false {
        didSet { needsDisplay = true }
    }

    override var displayTitle: String? { title.isEmpty ? nil : title }

    override var idleBezelState: ClassicChrome.BezelState {
        representsOpenPalette ? .on : .normal
    }

    override func drawArrowWellGlyph(cx: CGFloat, cy: CGFloat, active: Bool) {
        guard representsOpenPalette else {
            return super.drawArrowWellGlyph(cx: cx, cy: cy, active: active)
        }
        // A miniature floating window: an outlined pane under a filled title bar.
        // 8 pt square so it centers crisply in the well with the same side
        // margins as the chevrons (a wider box crowds the control's right edge).
        let color = ClassicChrome.arrowColor(active)
        let frame = NSRect(x: (cx - 4.5).rounded() + 0.5, y: (cy - 4.5).rounded() + 0.5,
                           width: 8, height: 8)
        color.setStroke()
        let outline = NSBezierPath(rect: frame)
        outline.lineWidth = 1
        outline.stroke()
        color.setFill()
        NSRect(x: frame.minX + 0.5, y: frame.maxY - 2.5, width: frame.width - 1, height: 2).fill()
    }

    override func presentChoices() { onPresent?() }
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
        let active = ClassicChrome.active(for: self)
        let outline = ClassicChrome.bezelOutline(in: bounds, radius: 3)
        NSGraphicsContext.saveGraphicsState()
        outline.addClip()
        NSColor.white.setFill()
        bounds.fill()
        let arrowZone = NSRect(x: bounds.width - arrowZoneWidth, y: 0,
                               width: arrowZoneWidth, height: bounds.height)
        ClassicChrome.bezelGradient(.normal, active: active).draw(in: arrowZone, angle: 90)
        NSColor(calibratedWhite: 0, alpha: 0.07).setFill()     // inset shadow on the text area
        NSRect(x: 0, y: bounds.height - 2, width: bounds.width - arrowZoneWidth, height: 1).fill()
        ClassicChrome.segmentSeparator(active).withAlphaComponent(0.7).setFill()
        NSRect(x: bounds.width - arrowZoneWidth - 0.5, y: 0, width: 1, height: bounds.height).fill()
        NSGraphicsContext.restoreGraphicsState()
        ClassicChrome.bezelBorder(active).setStroke()
        outline.lineWidth = 1
        outline.stroke()

        let cx = bounds.width - arrowZoneWidth / 2 - 0.5
        let cy = bounds.height / 2
        ClassicChrome.arrowColor(active).setFill()
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
        let windowActive = ClassicChrome.active(for: self)
        let outline = ClassicChrome.bezelOutline(in: bounds, radius: 3)
        let state: ClassicChrome.BezelState = isActive ? .on : .normal
        NSGraphicsContext.saveGraphicsState()
        outline.addClip()
        ClassicChrome.bezelGradient(state, active: windowActive).draw(in: bounds, angle: 90)
        ClassicChrome.drawInnerHint(state, in: bounds, active: windowActive)
        NSGraphicsContext.restoreGraphicsState()
        ClassicChrome.bezelBorder(windowActive).setStroke()
        outline.lineWidth = 1
        outline.stroke()

        let swatch = bounds.insetBy(dx: 5, dy: 5)
        color.setFill()
        swatch.insetBy(dx: 1, dy: 1).fill()
        NSColor(calibratedWhite: windowActive ? 0.35 : 0.55, alpha: 1).setStroke()
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
        let active = ClassicChrome.active(for: self)
        NSColor(calibratedWhite: active ? 0.58 : 0.72, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: 1, height: bounds.height).fill()
        NSColor(calibratedWhite: 1.0, alpha: 0.8).setFill()
        NSRect(x: 1, y: 0, width: 1, height: bounds.height).fill()
    }
}

// MARK: - Push button

/// A standalone classic push button: one gradient bezel with a centered 11 pt
/// title, flashing pressed while clicked. Public for the welcome screen.
public final class ClassicButton: NSControl {

    public var title: String {
        didSet {
            invalidateIntrinsicContentSize()
            needsDisplay = true
        }
    }

    private let fixedWidth: CGFloat?
    private var isTracking = false
    private var isPressed = false

    public init(title: String, width: CGFloat? = nil) {
        self.title = title
        self.fixedWidth = width
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    public override var intrinsicContentSize: NSSize {
        let titleWidth = ceil(NSAttributedString(string: title, attributes: [
            .font: NSFont.systemFont(ofSize: 11)
        ]).size().width)
        return NSSize(width: fixedWidth ?? titleWidth + 28, height: ClassicChrome.controlHeight)
    }

    public override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    public override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        isTracking = true
        isPressed = true
        needsDisplay = true
    }

    public override func mouseDragged(with event: NSEvent) {
        guard isTracking else { return }
        let inside = bounds.contains(convert(event.locationInWindow, from: nil))
        if inside != isPressed {
            isPressed = inside
            needsDisplay = true
        }
    }

    public override func mouseUp(with event: NSEvent) {
        let inside = bounds.contains(convert(event.locationInWindow, from: nil))
        let shouldFire = isTracking && inside
        isTracking = false
        isPressed = false
        needsDisplay = true
        if shouldFire { sendAction(action, to: target) }
    }

    public override func draw(_ dirtyRect: NSRect) {
        let active = ClassicChrome.active(for: self)
        let outline = ClassicChrome.bezelOutline(in: bounds)
        let state: ClassicChrome.BezelState = isPressed ? .pressed : .normal
        NSGraphicsContext.saveGraphicsState()
        outline.addClip()
        ClassicChrome.bezelGradient(state, active: active).draw(in: bounds, angle: 90)
        ClassicChrome.drawInnerHint(state, in: bounds, active: active)
        NSGraphicsContext.restoreGraphicsState()
        ClassicChrome.bezelBorder(active).setStroke()
        outline.lineWidth = 1
        outline.stroke()
        ClassicGlyph.letter(title, font: .systemFont(ofSize: 11))
            .draw(centeredIn: bounds, active: active)
    }
}

// MARK: - Engraved lettering

/// Classic bar lettering: dark gray over a hard 1 pt white drop below, so text
/// reads as engraved into the chrome. Public for the welcome screen.
public enum ClassicText {

    public static func engraved(_ string: String, size: CGFloat,
                                weight: NSFont.Weight = .regular, italic: Bool = false,
                                gray: CGFloat = 0.22, active: Bool = true) -> NSAttributedString {
        let shadow = NSShadow()
        shadow.shadowColor = NSColor(calibratedWhite: 1.0, alpha: active ? 0.65 : 0.4)
        shadow.shadowOffset = NSSize(width: 0, height: -1)
        shadow.shadowBlurRadius = 0
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        var font = NSFont.systemFont(ofSize: size, weight: weight)
        if italic { font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask) }
        return NSAttributedString(string: string, attributes: [
            .font: font,
            .foregroundColor: NSColor(calibratedWhite: active ? gray : min(gray + 0.26, 0.62), alpha: 1),
            .shadow: shadow,
            .paragraphStyle: paragraph
        ])
    }

    public static func engravedLabel(_ string: String, size: CGFloat,
                                     weight: NSFont.Weight = .regular, italic: Bool = false,
                                     gray: CGFloat = 0.22) -> NSTextField {
        let field = NSTextField(labelWithString: "")
        field.attributedStringValue = engraved(string, size: size, weight: weight,
                                                italic: italic, gray: gray)
        field.alignment = .center
        return field
    }
}

/// A short horizontal etched rule (dark hairline over a light one) — the classic
/// ornamental divider. Non-flipped coordinates: dark on top, light just below.
public final class ClassicRuleView: NSView {

    public override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: 2) }

    public override func draw(_ dirtyRect: NSRect) {
        NSColor(calibratedWhite: 0.68, alpha: 1).setFill()
        NSRect(x: 0, y: 1, width: bounds.width, height: 1).fill()
        NSColor(calibratedWhite: 1.0, alpha: 0.85).setFill()
        NSRect(x: 0, y: 0, width: bounds.width, height: 1).fill()
    }
}

// MARK: - Panels

/// A classic panel backdrop: the polished gradient as a full content background
/// (the welcome screen sits on this).
public final class ClassicPanelView: NSView {

    public override func draw(_ dirtyRect: NSRect) {
        let active = ClassicChrome.active(for: self)
        ClassicChrome.gradient(top: active ? 0.97 : 0.975,
                               bottom: active ? 0.86 : 0.92).draw(in: bounds, angle: 90)
        ClassicChrome.barTopHighlight.setFill()
        NSRect(x: 0, y: bounds.height - 1, width: bounds.width, height: 1).fill()
    }
}

/// A white inset surface with a hairline border and a faint top inner shadow —
/// the classic "well" that lists sit in (the welcome screen's recents).
public final class ClassicInsetBox: NSView {

    public func embed(_ view: NSView) {
        view.translatesAutoresizingMaskIntoConstraints = false
        addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 1),
            view.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -1),
            view.topAnchor.constraint(equalTo: topAnchor, constant: 1),
            view.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -1)
        ])
    }

    public override func draw(_ dirtyRect: NSRect) {
        let active = ClassicChrome.active(for: self)
        NSColor.white.setFill()
        bounds.fill()
        NSColor(calibratedWhite: 0, alpha: 0.06).setFill()
        NSRect(x: 1, y: bounds.height - 2, width: bounds.width - 2, height: 1).fill()
        NSColor(calibratedWhite: active ? 0.55 : 0.68, alpha: 1).setStroke()
        let border = NSBezierPath(rect: bounds.insetBy(dx: 0.5, dy: 0.5))
        border.lineWidth = 1
        border.stroke()
    }
}

// MARK: - Classic window shape

/// A window with the classic pre–Big Sur silhouette: standard rounded top
/// corners over gently rounded bottom corners. Modern macOS rounds all four
/// corners equally and has no public API to change that, so this answers the
/// private `_cornerMask` hook AppKit consults for the window's shape (and
/// shadow) with a 9-sliced template of `ClassicChrome.windowSilhouette` — the
/// same shape the floating palettes draw. If a future macOS stops consulting
/// the hook, the window simply keeps the stock corners — nothing else depends
/// on it.
public final class ClassicWindow: NSWindow {

    public override init(contentRect: NSRect, styleMask style: NSWindow.StyleMask,
                         backing backingStoreType: NSWindow.BackingStoreType, defer flag: Bool) {
        super.init(contentRect: contentRect, styleMask: style,
                   backing: backingStoreType, defer: flag)
        ClassicChromeActivation.install()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    @objc func _cornerMask() -> NSImage? { Self.shapeTemplate }

    private static let shapeTemplate: NSImage = {
        let top = ClassicChrome.windowTopCornerRadius
        let bottom = ClassicChrome.windowBottomCornerRadius
        let size = NSSize(width: top * 2 + 2, height: top + bottom + 2)
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor.black.setFill()
            ClassicChrome.windowSilhouette(in: rect).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: top, left: top, bottom: bottom, right: top)
        image.resizingMode = .stretch
        return image
    }()
}
