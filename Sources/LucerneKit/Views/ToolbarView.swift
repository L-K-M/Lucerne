import AppKit

// The format bar across the top of the window, drawn in the classic pre-flat Mac
// style (think iWork '09): a polished-metal gradient strip holding hand-drawn
// gradient-bezel controls in etched groups — see ClassicControls.swift. It talks
// straight to the EditorController and is kept in sync with the selection via
// syncFromSelection(). `preferredContentWidth` lets the window size its minimum
// width so the controls always fit.
public final class ToolbarView: NSView {

    public weak var editor: EditorController?
    /// Reports a one-line description of the control under the cursor (or nil when
    /// the cursor leaves the toolbar) so the window can show it in the status bar.
    public var onHoverHelp: ((String?) -> Void)?
    private var helpItems: [(view: NSView, help: String)] = []

    /// The bar's designed height; the window controller lays it out at this.
    public static let barHeight: CGFloat = 34

    private let styleRoles = DefaultDocuments.styleRoleOrder
    private let styleNames: [String]

    private let stylePopup = ClassicPopUp(width: 112)
    private let fontPopup = ClassicPopUp(width: 146)
    private let sizeField = ClassicSizeField(
        presets: ["9", "10", "11", "12", "14", "18", "24", "36", "48", "72"], width: 46)
    private let formatControl = ClassicSegmentedControl(
        glyphs: [
            .letter("B", font: .boldSystemFont(ofSize: 12)),
            .letter("I", font: NSFontManager.shared.convert(.systemFont(ofSize: 12),
                                                            toHaveTrait: .italicFontMask)),
            .letter("U", font: .systemFont(ofSize: 12), underlined: true)
        ],
        mode: .selectAny)
    private let colorWell = ClassicColorWell()
    private let alignControl = ClassicSegmentedControl(
        glyphs: [.alignment(.left), .alignment(.center), .alignment(.right), .alignment(.justified)],
        mode: .selectOne)
    private let lineSpacingPopup = ClassicPopUp(width: 58)

    private var stack = NSStackView()

    private let lineSpacings: [(String, CGFloat)] = [("1.0", 1.0), ("1.15", 1.15), ("1.5", 1.5), ("2.0", 2.0)]

    public override init(frame frameRect: NSRect) {
        let styles = DefaultDocuments.defaultStyles()
        styleNames = DefaultDocuments.styleRoleOrder.map { styles[$0]?.name ?? $0 }
        super.init(frame: frameRect)
        build()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    public override func draw(_ dirtyRect: NSRect) {
        ClassicChrome.gradient(top: 0.965, bottom: 0.795).draw(in: bounds, angle: 90)
        ClassicChrome.barTopHighlight.setFill()
        NSRect(x: 0, y: bounds.height - 1, width: bounds.width, height: 1).fill()
        NSColor(calibratedWhite: 0.66, alpha: 1).setFill()    // soft seam above the border
        NSRect(x: 0, y: 1, width: bounds.width, height: 1).fill()
        ClassicChrome.barBottomBorder.setFill()
        NSRect(x: 0, y: 0, width: bounds.width, height: 1).fill()
    }

    /// Natural width of all the controls; the window uses it to size itself.
    public var preferredContentWidth: CGFloat { stack.fittingSize.width }

    private func build() {
        stylePopup.addItems(withTitles: styleNames)
        stylePopup.target = self; stylePopup.action = #selector(styleChanged)

        fontPopup.addItems(withTitles: NSFontManager.shared.availableFontFamilies)
        fontPopup.target = self; fontPopup.action = #selector(fontChanged)

        sizeField.onCommit = { [weak self] raw in self?.applyFontSize(raw) }

        formatControl.target = self; formatControl.action = #selector(formatChanged)
        colorWell.target = self; colorWell.action = #selector(colorChanged)
        alignControl.target = self; alignControl.action = #selector(alignChanged)

        lineSpacingPopup.addItems(withTitles: lineSpacings.map(\.0))
        lineSpacingPopup.target = self; lineSpacingPopup.action = #selector(lineSpacingChanged)

        stack = NSStackView(views: [
            stylePopup, separator(),
            fontPopup, sizeField, separator(),
            formatControl, separator(),
            colorWell, separator(),
            alignControl, separator(),
            lineSpacingPopup
        ])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 9
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 10, bottom: 0, right: 10)
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

    private func separator() -> NSView { EtchedSeparatorView(frame: .zero) }

    private func registerHelp() {
        let entries: [(NSView, String)] = [
            (stylePopup, "Paragraph style — apply a named style (Body, Heading 1, …) to the selected paragraphs"),
            (fontPopup, "Font family for the selected text"),
            (sizeField, "Font size in points for the selected text"),
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
    private func applyFontSize(_ raw: String) {
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
        syncFromSelection()   // reflect the true state back on the control
        returnFocusToPage()
    }
    @objc private func colorChanged() { editor?.setTextColor(colorWell.color) }
    @objc private func alignChanged() {
        let map: [NSTextAlignment] = [.left, .center, .right, .justified]
        editor?.setAlignment(map[min(max(alignControl.selectedSegment, 0), 3)])
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
            sizeField.stringValue = String(Int(font.pointSize.rounded()))
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
            alignControl.setSelected(true, forSegment: seg)
            if ps.lineHeightMultiple > 0,
               let index = lineSpacings.firstIndex(where: { abs($0.1 - ps.lineHeightMultiple) < 0.01 }) {
                lineSpacingPopup.selectItem(at: index)
            }
        }
    }
}
