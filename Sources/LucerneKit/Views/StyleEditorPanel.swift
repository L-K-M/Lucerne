import AppKit

// The style editor (STYLES.md §6): ONE app-global, modeless panel in the classic
// palette chrome, opened from a palette row's edit well, a double-click, the
// Format menu, or the Style Library window. It always edits the definition whose
// effect is in front of you (S8): the front document's copy when the document
// defines the key (applied live through the S3 re-apply engine), or the
// library's copy for library-targeted sessions. The title bar names the target;
// the strip at the bottom shows the document↔library relationship as explicit
// verbs, never a mode switch.
//
// Undo: contiguous tweaks to one document style coalesce into a single
// "Edit Style" step (sealed on retarget/close — see
// EditorController.registerStyleRedefinitionUndo). Library-target edits register
// on the panel's own undo manager, best-effort.
final class StyleEditorPanel: NSObject {

    static let shared = StyleEditorPanel()

    enum Target: Equatable {
        case document(key: String)
        case library(key: String)

        var key: String {
            switch self {
            case .document(let key), .library(let key): return key
            }
        }
    }

    private(set) var target: Target?
    private var panel: ClassicPaletteWindow?
    private var chrome: PaletteChromeView?
    private var observers: [NSObjectProtocol] = []

    /// The coalesced-undo session for a document target: where the definition
    /// stood when the current run of tweaks began (nil def = key didn't exist).
    private var session: (key: String, initialDef: ParagraphStyleDef?, editor: EditorController)?

    /// Suppresses populate-feedback while the panel itself writes the library.
    private var isApplyingChange = false

    // MARK: Controls

    private let nameField = NSTextField()
    private let nameWarning = NSTextField(labelWithString: "")
    private let exportsPopup = ClassicPopUp(width: 168)
    private let fontPopup = ClassicPopUp(width: 168)
    private let sizeField = ClassicSizeField(
        presets: ["9", "10", "11", "12", "14", "18", "24", "36", "48", "72"], width: 46)
    private let traitsControl = ClassicSegmentedControl(
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
    private let lineSpacingField = NSTextField()
    private let beforeField = NSTextField()
    private let afterField = NSTextField()
    private let indentLeftField = NSTextField()
    private let indentFirstField = NSTextField()
    private let indentRightField = NSTextField()
    private var indentRowLabel: NSTextField?
    private let specimen = StyleSpecimenView()
    private let captureButton = ClassicButton(title: "Capture from Selection")
    private let blastLabel = NSTextField(labelWithString: "")

    // The library strip (§6.4)
    private let stripLabel = NSTextField(labelWithString: "")
    private let addToLibraryButton = ClassicButton(title: "Add to Library")
    private let updateLibraryButton = ClassicButton(title: "Update Library")
    private let useLibraryButton = ClassicButton(title: "Use Library Copy")
    private let editLibraryCopyButton = ClassicButton(title: "Edit Library Copy…")
    private let addToLetterButton = ClassicButton(title: "Add to This Letter")

    private static let exportChoices: [(title: String, markdown: String)] = [
        ("Paragraph", "p"), ("Heading 1", "h1"), ("Heading 2", "h2"),
        ("Heading 3", "h3"), ("List item", "li"), ("Quotation", "blockquote")
    ]

    private override init() {
        super.init()
    }

    // MARK: - Open / close / retarget

    /// Opens (or retargets) the panel. `library: true` edits the library's copy.
    func open(key: String, library: Bool, focusName: Bool = false) {
        let newTarget: Target = library ? .library(key: key) : .document(key: key)
        if target != newTarget { sealUndoSession() }
        target = newTarget
        let panel = ensurePanel()
        installObservers()
        reloadFromTarget()
        panel.orderFront(nil)
        if focusName {
            panel.makeKey()
            panel.makeFirstResponder(nameField)
        }
    }

    func close() {
        sealUndoSession()
        panel?.orderOut(nil)
        target = nil
        removeObservers()
    }

    var isOpen: Bool { panel?.isVisible == true && target != nil }

    /// A document selection moved (called alongside the palettes' sync): keep
    /// the blast-radius line live.
    func noteSelectionChanged() {
        guard isOpen else { return }
        refreshDynamicLabels()
    }

    // MARK: - Targets

    private func targetWindowController() -> DocumentWindowController? {
        FloatingPalette.activeDocumentWindowController()
    }

    /// The definition the panel is editing right now, from its source of truth.
    private func currentDefinition() -> ParagraphStyleDef? {
        guard let target else { return nil }
        switch target {
        case .document(let key):
            return targetWindowController()?.editor.model.styles[key]
        case .library(let key):
            return StyleLibrary.shared.load()[key]
        }
    }

    /// The front document changed (or the library was rewritten elsewhere):
    /// re-resolve the same key against the new state — never silently switching
    /// which copy is edited (§6.5).
    private func retarget() {
        guard isOpen else { return }
        sealUndoSession()
        reloadFromTarget()
    }

    // MARK: - Undo session (document targets, §6.3)

    private func noteWillChangeDocumentStyle(key: String, editor: EditorController) {
        if let session, session.key == key, session.editor === editor { return }
        sealUndoSession()
        session = (key, editor.model.styles[key], editor)
    }

    private func sealUndoSession() {
        guard let session else { return }
        self.session = nil
        session.editor.registerStyleRedefinitionUndo(key: session.key,
                                                     restoring: session.initialDef)
    }

    // MARK: - Applying edits

    @objc private func controlChanged() {
        guard let target, var def = currentDefinition() else { return }
        readControls(into: &def)
        apply(def, to: target)
    }

    @objc private func captureFromSelection() {
        guard case .document(let key)? = target,
              let editor = targetWindowController()?.editor,
              var def = editor.model.styles[key] else { return }
        def = editor.capturedStyleFromSelection(basedOn: def)
        apply(def, to: .document(key: key))
        populate(def)
    }

    private func apply(_ def: ParagraphStyleDef, to target: Target) {
        isApplyingChange = true
        defer { isApplyingChange = false }
        switch target {
        case .document(let key):
            guard let wc = targetWindowController() else { return }
            noteWillChangeDocumentStyle(key: key, editor: wc.editor)
            wc.editor.redefineStyle(key, to: def, registerUndo: false)
            wc.paletteDidApplyFormatting()
        case .library(let key):
            let old = StyleLibrary.shared.load()[key]
            StyleLibrary.shared.saveStyle(def, forKey: key)
            registerLibraryUndo(key: key, restoring: old)
        }
        refreshDynamicLabels()
        specimen.definition = def
        chrome?.title = titleText(for: def)
    }

    /// Best-effort undo for library-target edits, on the panel's own manager —
    /// no document is involved, so no document undo stack is either (§6.3).
    private func registerLibraryUndo(key: String, restoring old: ParagraphStyleDef?) {
        guard let undo = panel?.paletteUndoManager else { return }
        undo.registerUndo(withTarget: self) { panel in
            let current = StyleLibrary.shared.load()[key]
            if let old {
                StyleLibrary.shared.saveStyle(old, forKey: key)
            } else {
                StyleLibrary.shared.removeStyle(forKey: key)
            }
            panel.registerLibraryUndo(key: key, restoring: current)
            panel.reloadFromTarget()
        }
        undo.setActionName("Edit Library Style")
    }

    // MARK: - Strip verbs (§6.4)

    @objc private func pushToLibrary() {
        guard case .document(let key)? = target,
              let editor = targetWindowController()?.editor,
              let def = editor.model.styles[key] else { return }
        let oldLibraryDef = StyleLibrary.shared.load()[key]
        StyleLibrary.shared.saveStyle(def, forKey: key)
        offerUpdateToOpenDocuments(key: key, oldLibraryDef: oldLibraryDef,
                                   newDef: def, excluding: editor)
        reloadFromTarget()
    }

    @objc private func pullFromLibrary() {
        guard case .document(let key)? = target,
              let wc = targetWindowController(),
              var libraryDef = StyleLibrary.shared.load()[key] else { return }
        sealUndoSession()
        libraryDef.order = wc.editor.model.styles[key]?.order   // keep the letter's list position
        wc.editor.redefineStyle(key, to: libraryDef, actionName: "Use Library Style")
        wc.paletteDidApplyFormatting()
        reloadFromTarget()
    }

    @objc private func editLibraryCopyInstead() {
        guard let target else { return }
        open(key: target.key, library: true)
    }

    @objc private func addToFrontLetter() {
        guard case .library(let key)? = target,
              let wc = targetWindowController(),
              let def = StyleLibrary.shared.load()[key] else { return }
        wc.editor.addOrReplaceStyle(def, forKey: key, actionName: "Add Library Style")
        wc.paletteDidApplyFormatting()
        reloadFromTarget()
    }

    /// The open-documents offer (§6.4): letters whose copy still matched the old
    /// library definition are offered the update — never forced. Closed
    /// documents are never touched.
    private func offerUpdateToOpenDocuments(key: String, oldLibraryDef: ParagraphStyleDef?,
                                            newDef: ParagraphStyleDef, excluding editor: EditorController?) {
        guard let oldLibraryDef else { return }
        let eligible = Self.openDocumentWindowControllers().filter { wc in
            wc.editor !== editor
                && (wc.editor.model.styles[key].map { $0.visuallyEquals(oldLibraryDef) } ?? false)
        }
        guard !eligible.isEmpty else { return }
        let names = eligible.map { $0.window?.title ?? "Untitled" }.joined(separator: ", ")
        let alert = NSAlert()
        alert.messageText = eligible.count == 1
            ? "Also restyle 1 open letter?"
            : "Also restyle \(eligible.count) open letters?"
        alert.informativeText = "These open letters still use the Library version of "
            + "“\(newDef.name)”: \(names). Each update is its own undo step. "
            + "Closed letters are never touched."
        alert.addButton(withTitle: "Restyle")
        alert.addButton(withTitle: "Leave Them")
        if alert.runModal() == .alertFirstButtonReturn {
            for wc in eligible {
                var def = newDef
                def.order = wc.editor.model.styles[key]?.order
                wc.editor.redefineStyle(key, to: def, actionName: "Update Style from Library")
                wc.paletteDidApplyFormatting()
            }
        }
    }

    static func openDocumentWindowControllers() -> [DocumentWindowController] {
        NSApp.windows.compactMap { $0.delegate as? DocumentWindowController }
    }

    // MARK: - Populate

    private func reloadFromTarget() {
        guard let target else { return }
        guard let def = currentDefinition() else {
            // The key vanished from this side (front letter doesn't define it, or
            // the library entry was removed): go quiet, strip states the way
            // forward (§6.5).
            setFormEnabled(false)
            chrome?.title = "Style"
            refreshStrip(def: nil)
            refreshDynamicLabels()
            return
        }
        setFormEnabled(true)
        populate(def)
        chrome?.title = titleText(for: def)
        refreshStrip(def: def)
        refreshDynamicLabels()
        if case .document? = target {
            captureButton.isEnabled = true
        } else {
            captureButton.isEnabled = false
        }
    }

    private func titleText(for def: ParagraphStyleDef) -> String {
        switch target {
        case .document?: return "\(def.name) — this letter"
        case .library?: return "\(def.name) — Library"
        case nil: return "Style"
        }
    }

    private func populate(_ def: ParagraphStyleDef) {
        nameField.stringValue = def.name
        // Unknown future markdown hints normalize to Paragraph on edit — the
        // exporter treats them as "p" anyway (spec §5.1).
        let exportIndex = Self.exportChoices.firstIndex { $0.markdown == def.markdown } ?? 0
        exportsPopup.selectItem(at: exportIndex)
        fontPopup.selectItem(withTitle: def.font ?? "Helvetica")
        sizeField.stringValue = formatNumber(def.size ?? 12)
        traitsControl.setSelected(def.bold ?? false, forSegment: 0)
        traitsControl.setSelected(def.italic ?? false, forSegment: 1)
        traitsControl.setSelected(def.underline ?? false, forSegment: 2)
        colorWell.color = def.color.flatMap { NSColor(hexString: $0) } ?? .black
        let alignIndex: Int
        switch def.alignment {
        case "center": alignIndex = 1
        case "right": alignIndex = 2
        case "justified": alignIndex = 3
        default: alignIndex = 0
        }
        alignControl.setSelected(true, forSegment: alignIndex)
        lineSpacingField.stringValue = def.lineSpacing.map { formatNumber($0) } ?? ""
        beforeField.stringValue = formatNumber(def.spaceBefore ?? 0)
        afterField.stringValue = formatNumber(def.spaceAfter ?? 0)
        let unit = Preferences.rulerUnit.pointsPerUnit
        indentLeftField.stringValue = formatNumber((def.leftIndent ?? 0) / Double(unit))
        indentFirstField.stringValue = formatNumber((def.firstLineIndent ?? 0) / Double(unit))
        indentRightField.stringValue = formatNumber((def.rightIndent ?? 0) / Double(unit))
        indentRowLabel?.stringValue = indentRowTitle()
        specimen.definition = def
        refreshNameWarning(def)
    }

    private func readControls(into def: inout ParagraphStyleDef) {
        let trimmedName = nameField.stringValue.trimmingCharacters(in: .whitespaces)
        if !trimmedName.isEmpty { def.name = trimmedName }
        def.markdown = Self.exportChoices[max(0, min(exportsPopup.indexOfSelectedItem,
                                                     Self.exportChoices.count - 1))].markdown
        if let family = fontPopup.titleOfSelectedItem { def.font = family }
        if let size = Double(sizeField.stringValue), size > 0 { def.size = size }
        def.bold = traitsControl.isSelected(forSegment: 0)
        def.italic = traitsControl.isSelected(forSegment: 1)
        def.underline = traitsControl.isSelected(forSegment: 2)
        def.color = colorWell.color.lucerneHexString
        switch alignControl.selectedSegment {
        case 1: def.alignment = "center"
        case 2: def.alignment = "right"
        case 3: def.alignment = "justified"
        default: def.alignment = "left"
        }
        if let spacing = Double(lineSpacingField.stringValue), spacing > 0 {
            def.lineSpacing = spacing
        } else if lineSpacingField.stringValue.trimmingCharacters(in: .whitespaces).isEmpty {
            def.lineSpacing = nil
        }
        def.spaceBefore = Double(beforeField.stringValue) ?? def.spaceBefore
        def.spaceAfter = Double(afterField.stringValue) ?? def.spaceAfter
        let unit = Double(Preferences.rulerUnit.pointsPerUnit)
        if let left = Double(indentLeftField.stringValue) { def.leftIndent = left * unit }
        if let first = Double(indentFirstField.stringValue) { def.firstLineIndent = first * unit }
        if let right = Double(indentRightField.stringValue) { def.rightIndent = right * unit }
        refreshNameWarning(def)
    }

    private func refreshNameWarning(_ def: ParagraphStyleDef) {
        guard let target else { nameWarning.stringValue = ""; return }
        let table: [String: ParagraphStyleDef]
        switch target {
        case .document: table = targetWindowController()?.editor.model.styles ?? [:]
        case .library: table = StyleLibrary.shared.load()
        }
        let collides = table.contains { $0.key != target.key && $0.value.name == def.name }
        nameWarning.stringValue = collides ? "Another style already has this name." : ""
    }

    private func refreshDynamicLabels() {
        switch target {
        case .document(let key)?:
            if let editor = targetWindowController()?.editor, editor.model.styles[key] != nil {
                let count = editor.paragraphCount(withStyleRole: key)
                blastLabel.stringValue = count == 1
                    ? "Restyles 1 paragraph in this letter"
                    : "Restyles \(count) paragraphs in this letter"
            } else {
                blastLabel.stringValue = "Not in the front letter"
            }
        case .library?:
            blastLabel.stringValue = "In your Library — seeds new letters"
        case nil:
            blastLabel.stringValue = ""
        }
    }

    /// The strip's three document states, or the library-target inversion (§6.4).
    private func refreshStrip(def: ParagraphStyleDef?) {
        [addToLibraryButton, updateLibraryButton, useLibraryButton,
         editLibraryCopyButton, addToLetterButton].forEach { $0.isHidden = true }
        guard let target else { stripLabel.stringValue = ""; return }
        switch target {
        case .document(let key):
            guard let def else {
                stripLabel.stringValue = "“\(key)” is not in the front letter."
                if StyleLibrary.shared.load()[key] != nil {
                    editLibraryCopyButton.isHidden = false
                }
                return
            }
            switch StyleLibrary.syncState(documentDef: def,
                                          libraryDef: StyleLibrary.shared.load()[key]) {
            case .notInLibrary:
                stripLabel.stringValue = "Library: not in your Library"
                addToLibraryButton.isHidden = false
            case .matches:
                stripLabel.stringValue = "Library: matches your copy ✓"
            case .differs:
                stripLabel.stringValue = "Library: differs from your copy"
                updateLibraryButton.isHidden = false
                useLibraryButton.isHidden = false
                editLibraryCopyButton.isHidden = false
            }
        case .library(let key):
            guard def != nil else {
                stripLabel.stringValue = "This style is no longer in your Library."
                return
            }
            if let wc = targetWindowController() {
                if wc.editor.model.styles[key] == nil {
                    stripLabel.stringValue = "Not in this letter"
                    addToLetterButton.isHidden = false
                } else {
                    stripLabel.stringValue = "Also used in the front letter (its own copy)"
                }
            } else {
                stripLabel.stringValue = "Applies to new letters"
            }
        }
    }

    private func setFormEnabled(_ enabled: Bool) {
        nameField.isEditable = enabled
        nameField.isEnabled = enabled
        for control in [exportsPopup, fontPopup, traitsControl, alignControl, colorWell] as [NSControl] {
            control.isEnabled = enabled
        }
        for field in [lineSpacingField, beforeField, afterField,
                      indentLeftField, indentFirstField, indentRightField] {
            field.isEditable = enabled
            field.isEnabled = enabled
        }
        captureButton.isEnabled = enabled
    }

    private func formatNumber(_ value: Double) -> String {
        let rounded = (value * 100).rounded() / 100
        return rounded == rounded.rounded() ? String(Int(rounded)) : String(rounded)
    }

    private func indentRowTitle() -> String {
        Preferences.rulerUnit == .centimeters ? "Indents (cm)" : "Indents (in)"
    }

    // MARK: - Panel construction

    private func ensurePanel() -> ClassicPaletteWindow {
        if let panel { return panel }
        let height: CGFloat = 472
        let panel = ClassicPaletteWindow(
            contentSize: NSSize(width: 312, height: height + PaletteChromeView.titleBarHeight))
        panel.paletteUndoManager = UndoManager()
        let chrome = PaletteChromeView(title: "Style")
        chrome.onClose = { [weak self] in self?.close() }
        panel.contentView = chrome
        chrome.embedContent(buildForm())
        self.panel = panel
        self.chrome = chrome
        return panel
    }

    private func buildForm() -> NSView {
        // Field plumbing
        for field in [nameField, lineSpacingField, beforeField, afterField,
                      indentLeftField, indentFirstField, indentRightField] {
            field.font = .systemFont(ofSize: 11)
            field.focusRingType = .none
            field.target = self
            field.action = #selector(controlChanged)
            (field.cell as? NSTextFieldCell)?.sendsActionOnEndEditing = true
        }
        for field in [lineSpacingField, beforeField, afterField,
                      indentLeftField, indentFirstField, indentRightField] {
            field.alignment = .right
            field.widthAnchor.constraint(equalToConstant: 44).isActive = true
        }
        nameField.widthAnchor.constraint(equalToConstant: 168).isActive = true

        exportsPopup.addItems(withTitles: Self.exportChoices.map(\.title))
        exportsPopup.target = self
        exportsPopup.action = #selector(controlChanged)

        fontPopup.addItems(withTitles: NSFontManager.shared.availableFontFamilies
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending })
        fontPopup.target = self
        fontPopup.action = #selector(controlChanged)

        sizeField.onCommit = { [weak self] _ in self?.controlChanged() }
        traitsControl.target = self
        traitsControl.action = #selector(controlChanged)
        colorWell.target = self
        colorWell.action = #selector(controlChanged)
        alignControl.target = self
        alignControl.action = #selector(controlChanged)

        captureButton.target = self
        captureButton.action = #selector(captureFromSelection)

        nameWarning.font = .systemFont(ofSize: 10)
        nameWarning.textColor = NSColor(calibratedRed: 0.65, green: 0.25, blue: 0.1, alpha: 1)
        nameWarning.lineBreakMode = .byTruncatingTail

        blastLabel.font = .systemFont(ofSize: 10)
        blastLabel.textColor = NSColor(calibratedWhite: 0.4, alpha: 1)
        blastLabel.lineBreakMode = .byTruncatingTail

        stripLabel.font = .systemFont(ofSize: 10)
        stripLabel.textColor = NSColor(calibratedWhite: 0.3, alpha: 1)
        stripLabel.lineBreakMode = .byTruncatingTail

        for button in [addToLibraryButton, updateLibraryButton, useLibraryButton,
                       editLibraryCopyButton, addToLetterButton] {
            button.target = self
        }
        addToLibraryButton.action = #selector(pushToLibrary)
        updateLibraryButton.action = #selector(pushToLibrary)
        useLibraryButton.action = #selector(pullFromLibrary)
        editLibraryCopyButton.action = #selector(editLibraryCopyInstead)
        addToLetterButton.action = #selector(addToFrontLetter)

        specimen.translatesAutoresizingMaskIntoConstraints = false
        specimen.heightAnchor.constraint(equalToConstant: 56).isActive = true
        specimen.widthAnchor.constraint(equalToConstant: 290).isActive = true

        let indentLabel = formLabel(indentRowTitle())
        indentRowLabel = indentLabel

        let rows: [NSView] = [
            row("Name", [nameField]),
            indentedNote(nameWarning),
            row("Exports as", [exportsPopup]),
            row("Typeface", [fontPopup]),
            row("Size", [sizeField, traitsControl, colorWell]),
            row("Align", [alignControl, formLabel("Line"), lineSpacingField]),
            row("Space (pt)", [formLabel("Before"), beforeField, formLabel("After"), afterField]),
            rowWith(indentLabel, [indentLeftField, indentFirstField, indentRightField]),
            specimen,
            row("", [captureButton]),
            indentedNote(blastLabel)
        ]
        let form = NSStackView(views: rows)
        form.orientation = .vertical
        form.alignment = .leading
        form.spacing = 8

        let strip = buildStrip()

        let content = NSView()
        form.translatesAutoresizingMaskIntoConstraints = false
        strip.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(form)
        content.addSubview(strip)
        NSLayoutConstraint.activate([
            form.topAnchor.constraint(equalTo: content.topAnchor, constant: 10),
            form.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 10),
            form.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -10),
            strip.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            strip.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            strip.bottomAnchor.constraint(equalTo: content.bottomAnchor)
        ])
        return content
    }

    private func buildStrip() -> NSView {
        let buttons = NSStackView(views: [addToLibraryButton, updateLibraryButton,
                                          useLibraryButton, addToLetterButton])
        buttons.orientation = .horizontal
        buttons.spacing = 6
        let secondRow = NSStackView(views: [editLibraryCopyButton])
        secondRow.orientation = .horizontal
        let stack = NSStackView(views: [stripLabel, buttons, secondRow])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 5

        let strip = StripBackgroundView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        strip.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: strip.topAnchor, constant: 7),
            stack.leadingAnchor.constraint(equalTo: strip.leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: strip.trailingAnchor, constant: -10),
            stack.bottomAnchor.constraint(equalTo: strip.bottomAnchor, constant: -7)
        ])
        return strip
    }

    private func row(_ title: String, _ views: [NSView]) -> NSStackView {
        rowWith(formLabel(title), views)
    }

    private func rowWith(_ label: NSTextField, _ views: [NSView]) -> NSStackView {
        label.alignment = .right
        label.widthAnchor.constraint(equalToConstant: 76).isActive = true
        let stack = NSStackView(views: [label] + views)
        stack.orientation = .horizontal
        stack.spacing = 6
        return stack
    }

    private func formLabel(_ title: String) -> NSTextField {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 11)
        label.textColor = NSColor(calibratedWhite: 0.25, alpha: 1)
        return label
    }

    private func indentedNote(_ label: NSTextField) -> NSStackView {
        let spacer = NSView()
        spacer.widthAnchor.constraint(equalToConstant: 76).isActive = true
        let stack = NSStackView(views: [spacer, label])
        stack.orientation = .horizontal
        stack.spacing = 6
        return stack
    }

    // MARK: - Observers

    private func installObservers() {
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: NSWindow.didBecomeMainNotification, object: nil, queue: .main) { [weak self] _ in
                self?.retarget()
            })
        observers.append(center.addObserver(
            forName: NSWindow.willCloseNotification, object: nil, queue: .main) { [weak self] note in
                guard (note.object as? NSWindow)?.delegate is DocumentWindowController else { return }
                DispatchQueue.main.async { self?.retarget() }
            })
        observers.append(center.addObserver(
            forName: StyleLibrary.didChange, object: nil, queue: .main) { [weak self] _ in
                guard let self, !self.isApplyingChange else { return }
                self.reloadFromTarget()
            })
        observers.append(center.addObserver(
            forName: Preferences.didChange, object: nil, queue: .main) { [weak self] _ in
                self?.reloadFromTarget()   // indent fields re-display in the new unit
            })
    }

    private func removeObservers() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
    }
}

// MARK: - Specimen

/// A live sample line set exactly as the style prints, on page white.
final class StyleSpecimenView: NSView {

    var definition: ParagraphStyleDef? {
        didSet { needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.setFill()
        bounds.fill()
        NSColor(calibratedWhite: 0.6, alpha: 1).setStroke()
        let border = NSBezierPath(rect: bounds.insetBy(dx: 0.5, dy: 0.5))
        border.lineWidth = 1
        border.stroke()

        guard let def = definition else { return }
        let font = FontResolver.font(family: def.font,
                                     size: min(CGFloat(def.size ?? 12), 18),
                                     bold: def.bold ?? false,
                                     italic: def.italic ?? false)
        var attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: def.color.flatMap { NSColor(hexString: $0) } ?? NSColor.black
        ]
        if def.underline ?? false { attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue }
        let ps = NSMutableParagraphStyle()
        ps.alignment = AttributedStringBuilder.alignment(from: def.alignment)
        ps.lineBreakMode = .byTruncatingTail
        attrs[.paragraphStyle] = ps
        let sample = NSAttributedString(
            string: "Hamburgevons 0123 — the quick brown fox jumps over the lazy dog.",
            attributes: attrs)
        sample.draw(in: bounds.insetBy(dx: 7, dy: 7))
    }
}

/// The strip's backdrop: the classic bar gradient under a hairline rule, so it
/// reads as a footer distinct from the form above it.
private final class StripBackgroundView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let active = ClassicChrome.active(for: self)
        ClassicChrome.gradient(top: active ? 0.955 : 0.965,
                               bottom: active ? 0.85 : 0.91).draw(in: bounds, angle: 90)
        NSColor(calibratedWhite: 0.72, alpha: 1).setFill()
        NSRect(x: 0, y: bounds.height - 1, width: bounds.width, height: 1).fill()
    }
}
