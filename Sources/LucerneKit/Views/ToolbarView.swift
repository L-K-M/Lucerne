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

    private static let tryOnHint = "↑↓ try on your letter  ·  Return keep  ·  Esc revert  ·  drag off to float"

    private let styleControl = ClassicChooserControl(width: 112)
    private let stylePicker = TryOnPopover(hint: ToolbarView.tryOnHint)
    private let fontControl = ClassicChooserControl(width: 146)
    private let fontPicker = TryOnPopover(hint: ToolbarView.tryOnHint)
    private var paletteObserver: NSObjectProtocol?
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

    deinit {
        if let paletteObserver { NotificationCenter.default.removeObserver(paletteObserver) }
    }

    public override func draw(_ dirtyRect: NSRect) {
        let active = ClassicChrome.active(for: self)
        ClassicChrome.gradient(top: active ? 0.965 : 0.975,
                               bottom: active ? 0.795 : 0.90).draw(in: bounds, angle: 90)
        ClassicChrome.barTopHighlight.setFill()
        NSRect(x: 0, y: bounds.height - 1, width: bounds.width, height: 1).fill()
        NSColor(calibratedWhite: active ? 0.66 : 0.80, alpha: 1).setFill()    // soft seam above the border
        NSRect(x: 0, y: 1, width: bounds.width, height: 1).fill()
        ClassicChrome.barBottomBorder(active).setFill()
        NSRect(x: 0, y: 0, width: bounds.width, height: 1).fill()
    }

    /// Natural width of all the controls; the window uses it to size itself.
    public var preferredContentWidth: CGFloat { stack.fittingSize.width }

    private func build() {
        styleControl.title = styleNames.first ?? "Body"
        styleControl.onPresent = { [weak self] in self?.presentStylePicker() }

        fontControl.onPresent = { [weak self] in self?.presentFontPicker() }

        sizeField.onCommit = { [weak self] raw in self?.applyFontSize(raw) }

        formatControl.target = self; formatControl.action = #selector(formatChanged)
        colorWell.target = self; colorWell.action = #selector(colorChanged)
        alignControl.target = self; alignControl.action = #selector(alignChanged)

        lineSpacingPopup.addItems(withTitles: lineSpacings.map(\.0))
        lineSpacingPopup.target = self; lineSpacingPopup.action = #selector(lineSpacingChanged)

        // Keep the choosers honest about the app-global palettes: while one
        // floats, the matching control on EVERY window draws "engaged elsewhere"
        // and summons it rather than spawning a second.
        paletteObserver = NotificationCenter.default.addObserver(
            forName: FloatingPalette.visibilityDidChangeNotification, object: nil,
            queue: .main) { [weak self] _ in self?.paletteVisibilityChanged() }
        paletteVisibilityChanged()   // a window opened while palettes already float

        stack = NSStackView(views: [
            styleControl, separator(),
            fontControl, sizeField, separator(),
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
        let styleHelp = FloatingPalette.styles.isOpen
            ? "Styles live in the floating palette — click to bring it to the front"
            : "Paragraph style — try styles live on your letter: ↑↓ to browse, Return to keep, Esc to revert"
        let fontHelp = FloatingPalette.typefaces.isOpen
            ? "Typefaces live in the floating palette — click to bring it to the front"
            : "Typeface — try faces live on your letter: ↑↓ to browse, Return to keep, Esc to revert"
        let entries: [(NSView, String)] = [
            (styleControl, styleHelp),
            (fontControl, fontHelp),
            (sizeField, "Font size in points for the selected text"),
            (formatControl, "Bold (⌘B), Italic (⌘I), Underline (⌘U)"),
            (colorWell, "Text color for the selection"),
            (alignControl, "Paragraph alignment: left, center, right, or justified"),
            (lineSpacingPopup, "Line spacing for the selected paragraphs")
        ]
        helpItems = entries
        for (view, help) in entries { view.toolTip = help }
    }

    /// A palette opened or closed somewhere: flip the matching chooser between
    /// "opens the picker" and "lives in the palette" (and re-word its help).
    private func paletteVisibilityChanged() {
        fontControl.representsOpenPalette = FloatingPalette.typefaces.isOpen
        styleControl.representsOpenPalette = FloatingPalette.styles.isOpen
        registerHelp()
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

    /// Opens the typeface try-on picker: a popover that previews each highlighted
    /// family on the document live, committing or reverting as one undo step.
    /// Drag it off the control to tear it into the app-global floating Typefaces
    /// palette; while that palette is open, the control summons it instead.
    private func presentFontPicker() {
        guard FloatingPalette.typefaces.isOpen == false else {
            FloatingPalette.typefaces.bringToFront()
            return
        }
        guard let editor, !fontPicker.isActive else { return }
        let current = (editor.currentAttributes()[.font] as? NSFont)?.familyName
        editor.beginFormatPreview()
        fontPicker.present(from: fontControl, palette: .typefaces,
                           items: FloatingPalette.typefaceItems(), currentID: current,
                           specimenFont: FloatingPalette.typefaceSpecimenFont) { [weak self] item in
            self?.editor?.setFontFamily(item.id)
            self?.fontControl.title = item.title
        } onDetach: { [weak self] in
            self?.editor?.endFormatPreview(commit: true, actionName: "Font")
        } onFinish: { [weak self] commit in
            guard let self else { return }
            self.editor?.endFormatPreview(commit: commit, actionName: "Font")
            self.syncFromSelection()
            self.returnFocusToPage()
        }
    }

    /// The paragraph-style twin of presentFontPicker: each style listed as its
    /// own specimen, previewed live on the selected paragraphs, and tearable
    /// into the global Styles palette.
    private func presentStylePicker() {
        guard FloatingPalette.styles.isOpen == false else {
            FloatingPalette.styles.bringToFront()
            return
        }
        guard let editor, !stylePicker.isActive else { return }
        editor.beginFormatPreview()
        stylePicker.present(from: styleControl, palette: .styles,
                            items: FloatingPalette.styleItems(styles: editor.model.styles),
                            currentID: editor.currentStyleRole(),
                            specimenFont: { [weak self] item in
            FloatingPalette.styleSpecimenFont(role: item.id, styles: self?.editor?.model.styles)
        }) { [weak self] item in
            self?.editor?.applyStyleRole(item.id)
            self?.styleControl.title = item.title
        } onDetach: { [weak self] in
            self?.editor?.endFormatPreview(commit: true, actionName: "Apply Style")
        } onFinish: { [weak self] commit in
            guard let self else { return }
            self.editor?.endFormatPreview(commit: commit, actionName: "Apply Style")
            self.syncFromSelection()
            self.returnFocusToPage()
        }
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
        if let role = editor.currentStyleRole() {
            // Prefer the document's own style names (files can customise them);
            // fall back to the default table, then the raw role.
            styleControl.title = editor.model.styles[role]?.name
                ?? styleRoles.firstIndex(of: role).map { styleNames[$0] }
                ?? role
        }

        let attrs = editor.currentAttributes()
        if let font = attrs[.font] as? NSFont {
            if let family = font.familyName { fontControl.title = family }
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
