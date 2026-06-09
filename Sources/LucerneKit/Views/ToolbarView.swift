import AppKit

// The simple control strip across the top of the window (the plan's "simple
// toolbar at the top of the page"). It talks straight to the EditorController and
// is kept in sync with the selection via syncFromSelection().
public final class ToolbarView: NSView {

    public weak var editor: EditorController?
    public var onInsertImage: (() -> Void)?

    private let styleRoles = DefaultDocuments.styleRoleOrder
    private let styleNames: [String]

    private let stylePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let fontPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let sizeCombo = NSComboBox()
    private let boldButton = NSButton()
    private let italicButton = NSButton()
    private let underlineButton = NSButton()
    private let colorWell = NSColorWell()
    private let alignControl = NSSegmentedControl()
    private let lineSpacingPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let insertImageButton = NSButton()

    private let lineSpacings: [(String, CGFloat)] = [("1.0", 1.0), ("1.15", 1.15), ("1.5", 1.5), ("2.0", 2.0)]
    private let sizes = ["9", "10", "11", "12", "14", "18", "24", "36", "48", "72"]

    public override init(frame frameRect: NSRect) {
        let styles = DefaultDocuments.defaultStyles()
        styleNames = DefaultDocuments.styleRoleOrder.map { styles[$0]?.name ?? $0 }
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor(calibratedWhite: 0.93, alpha: 1).cgColor
        build()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private func build() {
        stylePopup.addItems(withTitles: styleNames)
        stylePopup.target = self; stylePopup.action = #selector(styleChanged)

        fontPopup.addItems(withTitles: NSFontManager.shared.availableFontFamilies)
        fontPopup.target = self; fontPopup.action = #selector(fontChanged)

        sizeCombo.addItems(withObjectValues: sizes)
        sizeCombo.target = self; sizeCombo.action = #selector(sizeChanged)
        sizeCombo.widthAnchor.constraint(equalToConstant: 56).isActive = true

        configureToggle(boldButton, title: "B", selector: #selector(boldClicked))
        boldButton.font = NSFont.boldSystemFont(ofSize: 13)
        configureToggle(italicButton, title: "I", selector: #selector(italicClicked))
        configureToggle(underlineButton, title: "U", selector: #selector(underlineClicked))

        colorWell.target = self; colorWell.action = #selector(colorChanged)
        colorWell.widthAnchor.constraint(equalToConstant: 40).isActive = true

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

        insertImageButton.title = "Insert Image"
        insertImageButton.bezelStyle = .rounded
        insertImageButton.target = self; insertImageButton.action = #selector(insertImageClicked)

        let stack = NSStackView(views: [
            stylePopup, separator(), fontPopup, sizeCombo, separator(),
            boldButton, italicButton, underlineButton, colorWell, separator(),
            alignControl, lineSpacingPopup, separator(), insertImageButton
        ])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 6
        stack.edgeInsets = NSEdgeInsets(top: 4, left: 10, bottom: 4, right: 10)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    private func configureToggle(_ button: NSButton, title: String, selector: Selector) {
        button.title = title
        button.bezelStyle = .texturedRounded
        button.setButtonType(.pushOnPushOff)
        button.target = self
        button.action = selector
        button.widthAnchor.constraint(equalToConstant: 30).isActive = true
    }

    private func separator() -> NSView {
        let box = NSBox()
        box.boxType = .separator
        box.translatesAutoresizingMaskIntoConstraints = false
        box.heightAnchor.constraint(equalToConstant: 22).isActive = true
        return box
    }

    // MARK: - Actions

    @objc private func styleChanged() {
        let index = stylePopup.indexOfSelectedItem
        guard styleRoles.indices.contains(index) else { return }
        editor?.applyStyleRole(styleRoles[index])
    }
    @objc private func fontChanged() {
        if let family = fontPopup.titleOfSelectedItem { editor?.setFontFamily(family) }
    }
    @objc private func sizeChanged() {
        let value = sizeCombo.doubleValue
        if value > 0 { editor?.setFontSize(CGFloat(value)) }
    }
    @objc private func boldClicked() { editor?.toggleBold(); syncFromSelection() }
    @objc private func italicClicked() { editor?.toggleItalic(); syncFromSelection() }
    @objc private func underlineClicked() { editor?.toggleUnderline(); syncFromSelection() }
    @objc private func colorChanged() { editor?.setTextColor(colorWell.color) }
    @objc private func alignChanged() {
        let map: [NSTextAlignment] = [.left, .center, .right, .justified]
        editor?.setAlignment(map[min(alignControl.selectedSegment, 3)])
    }
    @objc private func lineSpacingChanged() {
        let index = lineSpacingPopup.indexOfSelectedItem
        guard lineSpacings.indices.contains(index) else { return }
        editor?.setLineHeightMultiple(lineSpacings[index].1)
    }
    @objc private func insertImageClicked() { onInsertImage?() }

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
            boldButton.state = FontResolver.isBold(font) ? .on : .off
            italicButton.state = FontResolver.isItalic(font) ? .on : .off
        }
        underlineButton.state = ((attrs[.underlineStyle] as? Int) ?? 0) != 0 ? .on : .off
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
