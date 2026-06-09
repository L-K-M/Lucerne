import AppKit

// The control strip across the top of the window (the plan's "simple toolbar at
// the top of the page"). It talks straight to the EditorController and is kept in
// sync with the selection via syncFromSelection(). `preferredContentWidth` lets the
// window size its minimum width so the controls always fit. Bold/Italic/Underline
// and alignment are segmented controls, so the selected ones take the accent color.
public final class ToolbarView: NSView {

    public weak var editor: EditorController?
    /// Reports a one-line description of the control under the cursor (or nil when
    /// the cursor leaves the toolbar) so the window can show it in the status bar.
    public var onHoverHelp: ((String?) -> Void)?
    private var helpItems: [(view: NSView, help: String)] = []

    private let styleRoles = DefaultDocuments.styleRoleOrder
    private let styleNames: [String]

    private let stylePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let fontPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let sizeCombo = NSComboBox()
    private let formatControl = NSSegmentedControl()   // Bold / Italic / Underline
    private let colorWell = NSColorWell()
    private let alignControl = NSSegmentedControl()
    private let lineSpacingPopup = NSPopUpButton(frame: .zero, pullsDown: false)

    private var stack = NSStackView()

    private let lineSpacings: [(String, CGFloat)] = [("1.0", 1.0), ("1.15", 1.15), ("1.5", 1.5), ("2.0", 2.0)]
    private let sizes = ["9", "10", "11", "12", "14", "18", "24", "36", "48", "72"]

    public override init(frame frameRect: NSRect) {
        let styles = DefaultDocuments.defaultStyles()
        styleNames = DefaultDocuments.styleRoleOrder.map { styles[$0]?.name ?? $0 }
        super.init(frame: frameRect)
        build()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    public override func draw(_ dirtyRect: NSRect) {
        NSColor(calibratedWhite: 0.93, alpha: 1).setFill()
        bounds.fill()
        NSColor(calibratedWhite: 0.62, alpha: 1).setStroke()
        let border = NSBezierPath()       // bottom edge (origin bottom-left, y up)
        border.move(to: CGPoint(x: 0, y: 0.5))
        border.line(to: CGPoint(x: bounds.width, y: 0.5))
        border.stroke()
    }

    /// Natural width of all the controls; the window uses it to size itself.
    public var preferredContentWidth: CGFloat { stack.fittingSize.width }

    private func build() {
        stylePopup.addItems(withTitles: styleNames)
        stylePopup.target = self; stylePopup.action = #selector(styleChanged)
        fixedWidth(stylePopup, 120)

        fontPopup.addItems(withTitles: NSFontManager.shared.availableFontFamilies)
        fontPopup.target = self; fontPopup.action = #selector(fontChanged)
        fixedWidth(fontPopup, 150)

        sizeCombo.addItems(withObjectValues: sizes)
        sizeCombo.target = self; sizeCombo.action = #selector(sizeChanged)
        (sizeCombo.cell as? NSTextFieldCell)?.sendsActionOnEndEditing = true
        fixedWidth(sizeCombo, 56)

        formatControl.segmentCount = 3
        let formatSymbols = ["bold", "italic", "underline"]
        for (i, symbol) in formatSymbols.enumerated() {
            formatControl.setImage(NSImage(systemSymbolName: symbol, accessibilityDescription: nil), forSegment: i)
            formatControl.setWidth(30, forSegment: i)
        }
        formatControl.trackingMode = .selectAny    // each toggles independently; selected → accent
        formatControl.target = self; formatControl.action = #selector(formatChanged)

        colorWell.target = self; colorWell.action = #selector(colorChanged)
        fixedWidth(colorWell, 40)

        alignControl.segmentCount = 4
        let symbols = ["text.alignleft", "text.aligncenter", "text.alignright", "text.justify"]
        for (i, symbol) in symbols.enumerated() {
            alignControl.setImage(NSImage(systemSymbolName: symbol, accessibilityDescription: nil), forSegment: i)
            alignControl.setWidth(28, forSegment: i)
        }
        alignControl.trackingMode = .selectOne
        alignControl.target = self; alignControl.action = #selector(alignChanged)

        lineSpacingPopup.addItems(withTitles: lineSpacings.map(\.0))
        lineSpacingPopup.target = self; lineSpacingPopup.action = #selector(lineSpacingChanged)
        fixedWidth(lineSpacingPopup, 64)

        stack = NSStackView(views: [
            stylePopup, fontPopup, sizeCombo,
            formatControl, colorWell,
            alignControl, lineSpacingPopup
        ])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 6
        // Group with extra spacing instead of separator lines.
        stack.setCustomSpacing(18, after: stylePopup)
        stack.setCustomSpacing(18, after: sizeCombo)
        stack.setCustomSpacing(18, after: colorWell)
        stack.edgeInsets = NSEdgeInsets(top: 4, left: 10, bottom: 4, right: 10)
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.setContentHuggingPriority(.required, for: .horizontal)
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        registerHelp()
    }

    private func fixedWidth(_ view: NSView, _ width: CGFloat) {
        view.widthAnchor.constraint(equalToConstant: width).isActive = true
    }

    private func registerHelp() {
        let entries: [(NSView, String)] = [
            (stylePopup, "Paragraph style — apply a named style (Body, Heading 1, …) to the selected paragraphs"),
            (fontPopup, "Font family for the selected text"),
            (sizeCombo, "Font size in points for the selected text"),
            (formatControl, "Bold (⌘B), Italic (⌘I), Underline (⌘U)"),
            (colorWell, "Text color for the selection"),
            (alignControl, "Paragraph alignment: left, center, right, or justified"),
            (lineSpacingPopup, "Line spacing for the selected paragraphs")
        ]
        helpItems = entries
        for (view, help) in entries { view.toolTip = help }
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

    private func help(at point: CGPoint) -> String? {
        for item in helpItems where item.view.convert(item.view.bounds, to: self).contains(point) {
            return item.help
        }
        return nil
    }

    // MARK: - Actions

    @objc private func styleChanged() {
        let index = stylePopup.indexOfSelectedItem
        guard styleRoles.indices.contains(index) else { return }
        editor?.applyStyleRole(styleRoles[index])
        returnFocusToPage()
    }
    @objc private func fontChanged() {
        if let family = fontPopup.titleOfSelectedItem { editor?.setFontFamily(family) }
        returnFocusToPage()
    }
    @objc private func sizeChanged() {
        // Read the selected item's value when picking from the list (stringValue
        // can be stale at action time); fall back to the typed text.
        let raw: String
        let index = sizeCombo.indexOfSelectedItem
        if index >= 0, let item = sizeCombo.itemObjectValue(at: index) as? String {
            raw = item
        } else {
            raw = sizeCombo.stringValue
        }
        if let value = Double(raw), value > 0 { editor?.setFontSize(CGFloat(value)) }
        returnFocusToPage()
    }
    @objc private func formatChanged() {
        switch formatControl.selectedSegment {
        case 0: editor?.toggleBold()
        case 1: editor?.toggleItalic()
        case 2: editor?.toggleUnderline()
        default: break
        }
        syncFromSelection()   // reflect the true state (and accent) back on the control
        returnFocusToPage()
    }
    @objc private func colorChanged() { editor?.setTextColor(colorWell.color) }
    @objc private func alignChanged() {
        let map: [NSTextAlignment] = [.left, .center, .right, .justified]
        editor?.setAlignment(map[min(alignControl.selectedSegment, 3)])
        returnFocusToPage()
    }
    @objc private func lineSpacingChanged() {
        let index = lineSpacingPopup.indexOfSelectedItem
        guard lineSpacings.indices.contains(index) else { return }
        editor?.setLineHeightMultiple(lineSpacings[index].1)
        returnFocusToPage()
    }

    /// After a toolbar formatting action, hand keyboard focus back to the editing
    /// surface so a change made with no selection (a typing-attribute change) takes
    /// effect on the next typed character. The color well is excluded — it drives the
    /// color panel and must keep focus.
    private func returnFocusToPage() { editor?.focusActiveTextView() }

    // MARK: - Sync

    public func syncFromSelection() {
        guard let editor else { return }
        if let role = editor.currentStyleRole(), let index = styleRoles.firstIndex(of: role) {
            stylePopup.selectItem(at: index)
        }

        let attrs = editor.currentAttributes()
        if let font = attrs[.font] as? NSFont {
            if let family = font.familyName { fontPopup.selectItem(withTitle: family) }
            sizeCombo.stringValue = String(Int(font.pointSize.rounded()))
            formatControl.setSelected(FontResolver.isBold(font), forSegment: 0)
            formatControl.setSelected(FontResolver.isItalic(font), forSegment: 1)
        }
        formatControl.setSelected(((attrs[.underlineStyle] as? Int) ?? 0) != 0, forSegment: 2)
        if let color = attrs[.foregroundColor] as? NSColor { colorWell.color = color }

        if let ps = editor.selectedParagraphStyle() {
            let seg: Int
            switch ps.alignment {
            case .center: seg = 1
            case .right: seg = 2
            case .justified: seg = 3
            default: seg = 0
            }
            alignControl.selectedSegment = seg
            if ps.lineHeightMultiple > 0,
               let index = lineSpacings.firstIndex(where: { abs($0.1 - ps.lineHeightMultiple) < 0.01 }) {
                lineSpacingPopup.selectItem(at: index)
            }
        }
    }
}
