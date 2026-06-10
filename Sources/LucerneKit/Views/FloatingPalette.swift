import AppKit

// The app-global floating palettes torn off the format bar's chooser controls:
// exactly ONE per kind (Typefaces, Styles) for the whole app, floating above
// every document. A palette acts on whichever document window is currently main
// — switch windows and its list/selection re-syncs — and every pick is a
// committed edit (its own undo step) on that document. While a palette is open,
// every window's chooser control draws "engaged elsewhere" and summons it
// instead of spawning a second one; closing it (the classic close box) returns
// the controls to their normal popover behavior everywhere.
final class FloatingPalette: NSObject {

    enum Kind { case typefaces, styles }

    static let typefaces = FloatingPalette(kind: .typefaces, title: "Typefaces")
    static let styles = FloatingPalette(kind: .styles, title: "Styles")

    /// Posted (object = the palette) when a palette opens or closes, so every
    /// window's format bar can flip its chooser between "opens the picker" and
    /// "lives in the palette".
    static let visibilityDidChangeNotification =
        Notification.Name("LucernePaletteVisibilityDidChange")

    private(set) var isOpen = false
    private let kind: Kind
    private let paletteTitle: String
    private var panel: ClassicPaletteWindow?
    private lazy var list = PickerListView(hint: "Applies to the front document")
    private var observers: [NSObjectProtocol] = []

    private init(kind: Kind, title: String) {
        self.kind = kind
        self.paletteTitle = title
        super.init()
    }

    // MARK: - Open / close

    /// Builds and configures the panel for a try-on popover's tear-off
    /// (NSPopoverDelegate.detachableWindow), without showing it or marking the
    /// palette open — AppKit only commits the detach afterwards (didDetach).
    func windowForDetach(selecting id: String?) -> NSWindow {
        let panel = ensurePanel()
        list.clearFilter()
        refreshFromActiveDocument(selecting: id)
        // Pre-position under the cursor; the detach machinery normally re-places
        // the panel at the drag, this just keeps a stale frame from flashing.
        let mouse = NSEvent.mouseLocation
        panel.setFrameTopLeftPoint(NSPoint(x: mouse.x - 24, y: mouse.y + 8))
        return panel
    }

    /// Whether the panel is actually on screen (the tear-off fallback signal).
    var isShowingPanel: Bool { panel?.isVisible == true }

    /// The tear-off committed: the popover closed detaching to our panel. Mark
    /// the palette open (every format bar flips its chooser) and make sure the
    /// panel landed on screen with a shadow matching the custom silhouette.
    func didDetach() {
        setOpen(true)
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isOpen, let panel = self.panel else { return }
            if !panel.isVisible { panel.orderFront(nil) }
            panel.invalidateShadow()
        }
    }

    /// Raises the open palette (the chooser controls route clicks here while it
    /// floats). Non-activating: no focus moves.
    func bringToFront() {
        guard isOpen, let panel else { return }
        panel.orderFront(nil)
    }

    func close() {
        panel?.orderOut(nil)
        setOpen(false)
        returnFocusToDocument()
    }

    private func setOpen(_ open: Bool) {
        guard isOpen != open else { return }
        isOpen = open
        if open { installObservers() } else { removeObservers() }
        NotificationCenter.default.post(name: Self.visibilityDidChangeNotification, object: self)
    }

    // MARK: - Panel

    private func ensurePanel() -> ClassicPaletteWindow {
        if let panel { return panel }
        let panel = ClassicPaletteWindow(
            contentSize: NSSize(width: 280, height: 400 + PaletteChromeView.titleBarHeight))
        let chrome = PaletteChromeView(title: paletteTitle)
        chrome.onClose = { [weak self] in self?.close() }
        panel.contentView = chrome

        list.specimenFont = { [weak self] item in
            self?.specimenFont(for: item) ?? .systemFont(ofSize: 13)
        }
        list.onPick = { [weak self] item in self?.apply(item) }
        // Return / double-click / Esc in a palette just hand the keyboard back to
        // the page — picks were already committed as they happened.
        list.onCommit = { [weak self] in self?.returnFocusToDocument() }
        list.onCancel = { [weak self] in self?.returnFocusToDocument() }
        chrome.embedContent(list)

        self.panel = panel
        return panel
    }

    // MARK: - The document a palette acts on

    /// The document window the palette applies to: the main window if it's a
    /// document, else the frontmost document window. (The palette itself can be
    /// key while the user types in its filter — main stays with the document.)
    static func activeDocumentWindowController() -> DocumentWindowController? {
        if let wc = NSApp.mainWindow?.delegate as? DocumentWindowController { return wc }
        for window in NSApp.orderedWindows {
            if let wc = window.delegate as? DocumentWindowController { return wc }
        }
        return nil
    }

    /// Lets document windows nudge every open palette when the active selection
    /// or main window changes, so the highlighted face/style tracks the caret.
    static func syncOpenPalettes() {
        for palette in [typefaces, styles] where palette.isOpen {
            palette.refreshFromActiveDocument()
        }
    }

    /// Re-targets the palette at the current main document: styles re-resolve
    /// from that document's stylesheet, and the selection highlight follows the
    /// document's current font/style (`preferredID` overrides, for the tear-off
    /// moment).
    private func refreshFromActiveDocument(selecting preferredID: String? = nil) {
        let wc = Self.activeDocumentWindowController()
        let newItems: [PickerItem]
        switch kind {
        case .typefaces:
            newItems = list.items.isEmpty ? Self.typefaceItems() : list.items
        case .styles:
            newItems = Self.styleItems(styles: wc?.editor.model.styles)
        }
        if newItems != list.items { list.setItems(newItems) }
        list.select(id: preferredID ?? currentID(of: wc?.editor))
    }

    private func currentID(of editor: EditorController?) -> String? {
        guard let editor else { return nil }
        switch kind {
        case .typefaces:
            return (editor.currentAttributes()[.font] as? NSFont)?.familyName
        case .styles:
            return editor.currentStyleRole()
        }
    }

    private func apply(_ item: PickerItem) {
        guard let wc = Self.activeDocumentWindowController() else { return }
        switch kind {
        case .typefaces: wc.editor.setFontFamily(item.id)
        case .styles: wc.editor.applyStyleRole(item.id)
        }
        // Put the caret back on the page so a caret-only change (typing
        // attributes) is immediately usable — without moving key status.
        wc.editor.focusActiveTextView()
        wc.paletteDidApplyFormatting()
    }

    private func returnFocusToDocument() {
        guard let wc = Self.activeDocumentWindowController(), let window = wc.window else { return }
        window.makeKey()
        wc.editor.focusActiveTextView()
    }

    private func installObservers() {
        let center = NotificationCenter.default
        // Track the active document as windows trade places (and as the last one
        // closes — the selection highlight clears when no document remains).
        observers.append(center.addObserver(
            forName: NSWindow.didBecomeMainNotification, object: nil, queue: .main) { [weak self] _ in
                self?.refreshFromActiveDocument()
            })
        observers.append(center.addObserver(
            forName: NSWindow.willCloseNotification, object: nil, queue: .main) { [weak self] note in
                guard (note.object as? NSWindow)?.delegate is DocumentWindowController else { return }
                DispatchQueue.main.async { self?.refreshFromActiveDocument() }
            })
    }

    private func removeObservers() {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers = []
    }

    // MARK: - Item tables (shared with the attached try-on popovers)

    static func typefaceItems() -> [PickerItem] {
        NSFontManager.shared.availableFontFamilies
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            .map { PickerItem(id: $0, title: $0) }
    }

    static func typefaceSpecimenFont(for item: PickerItem) -> NSFont {
        NSFontManager.shared.font(withFamily: item.id, traits: [], weight: 5, size: 13)
            ?? NSFont.systemFont(ofSize: 13)
    }

    static func styleItems(styles: [String: ParagraphStyleDef]?) -> [PickerItem] {
        let table = styles ?? DefaultDocuments.defaultStyles()
        return DefaultDocuments.styleRoleOrder.map {
            PickerItem(id: $0, title: table[$0]?.name ?? $0)
        }
    }

    /// Each style row is its own specimen: the style's face and traits, at a
    /// size clamped to fit the 24 pt row.
    static func styleSpecimenFont(role: String, styles: [String: ParagraphStyleDef]?) -> NSFont {
        let table = styles ?? DefaultDocuments.defaultStyles()
        guard let def = table[role] else { return .systemFont(ofSize: 13) }
        return FontResolver.font(family: def.font, size: min(CGFloat(def.size ?? 12), 15),
                                 bold: def.bold ?? false, italic: def.italic ?? false)
    }

    private func specimenFont(for item: PickerItem) -> NSFont {
        switch kind {
        case .typefaces:
            return Self.typefaceSpecimenFont(for: item)
        case .styles:
            return Self.styleSpecimenFont(
                role: item.id,
                styles: Self.activeDocumentWindowController()?.editor.model.styles)
        }
    }
}

// MARK: - Palette window

/// The floating palette's window: borderless (the chrome draws its own classic
/// half-height title bar), non-activating so clicks never pull focus from the
/// document, floating above document windows, and hidden while the app is
/// inactive — the classic utility-palette contract.
final class ClassicPaletteWindow: NSPanel {

    init(contentSize: NSSize) {
        super.init(contentRect: NSRect(origin: .zero, size: contentSize),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .floating
        becomesKeyOnlyIfNeeded = true
        hidesOnDeactivate = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isReleasedWhenClosed = false
        isMovableByWindowBackground = false
        collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        animationBehavior = .utilityWindow
        appearance = NSAppearance(named: .aqua)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    // Borderless windows refuse key status by default; the filter field needs it.
    // becomesKeyOnlyIfNeeded keeps ordinary clicks from grabbing it.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

// MARK: - Palette chrome

/// Draws the palette's classic shell: the ClassicWindow silhouette with a
/// tighter top radius (a small panel reads better with less sweep), a
/// half-height title bar in the bar gradient with engraved lettering and a
/// small red close dot — the standard close button at palette scale — the
/// panel-gradient body, and a hairline window border. Palettes hide when the
/// app deactivates, so the chrome always draws at full (active) strength.
final class PaletteChromeView: NSView {

    /// Half the standard title bar — the classic cue that this isn't a document
    /// window.
    static let titleBarHeight: CGFloat = 16

    /// Tighter than the document windows' top radius; the bottom keeps the
    /// shared gentle rounding.
    private static let topCornerRadius: CGFloat = 6

    var onClose: (() -> Void)?
    private let title: String
    private var closeBoxPressed = false

    init(title: String) {
        self.title = title
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Hosts the palette content below the title bar, inset 1 pt at the sides
    /// and bottom so the full-bleed list never paints over the window border.
    func embedContent(_ view: NSView) {
        view.translatesAutoresizingMaskIntoConstraints = false
        addSubview(view)
        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: topAnchor, constant: Self.titleBarHeight),
            view.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 1),
            view.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -1),
            view.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -1)
        ])
    }

    private var titleBarRect: NSRect {
        NSRect(x: 0, y: bounds.height - Self.titleBarHeight,
               width: bounds.width, height: Self.titleBarHeight)
    }

    private var closeBoxRect: NSRect {
        let bar = titleBarRect
        return NSRect(x: 6, y: bar.minY + ((bar.height - 9) / 2).rounded(), width: 9, height: 9)
    }

    override func draw(_ dirtyRect: NSRect) {
        let silhouette = ClassicChrome.windowSilhouette(in: bounds, top: Self.topCornerRadius)
        NSGraphicsContext.saveGraphicsState()
        silhouette.addClip()

        ClassicChrome.gradient(top: 0.97, bottom: 0.86).draw(in: bounds, angle: 90)

        let bar = titleBarRect
        ClassicChrome.gradient(top: 0.965, bottom: 0.80).draw(in: bar, angle: 90)
        ClassicChrome.barTopHighlight.setFill()
        NSRect(x: 0, y: bounds.height - 1, width: bounds.width, height: 1).fill()
        ClassicChrome.barBottomBorder(true).setFill()
        NSRect(x: 0, y: bar.minY, width: bounds.width, height: 1).fill()

        NSGraphicsContext.restoreGraphicsState()

        NSColor(calibratedWhite: 0.45, alpha: 1).setStroke()
        let border = ClassicChrome.windowSilhouette(in: bounds.insetBy(dx: 0.5, dy: 0.5),
                                                    top: Self.topCornerRadius)
        border.lineWidth = 1
        border.stroke()

        drawTitle(in: bar)
        drawCloseBox()
    }

    private func drawTitle(in bar: NSRect) {
        let styled = ClassicText.engraved(title, size: 10.5, weight: .medium)
        let size = styled.size()
        styled.draw(at: NSPoint(x: (bar.midX - size.width / 2).rounded(),
                                y: (bar.midY - size.height / 2).rounded()))
    }

    private func drawCloseBox() {
        // The standard red close button at palette scale (9 pt vs the usual 12),
        // darkening while pressed like the real one.
        let circle = NSBezierPath(ovalIn: closeBoxRect.insetBy(dx: 0.5, dy: 0.5))
        (closeBoxPressed
            ? NSColor(calibratedRed: 0.78, green: 0.27, blue: 0.25, alpha: 1)
            : NSColor(calibratedRed: 1.00, green: 0.37, blue: 0.34, alpha: 1)).setFill()
        circle.fill()
        NSColor(calibratedRed: 0.88, green: 0.27, blue: 0.24, alpha: 1).setStroke()
        circle.lineWidth = 1
        circle.stroke()
    }

    // MARK: - Mouse: close box tracking + title-bar dragging

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if closeBoxRect.insetBy(dx: -3, dy: -3).contains(point) {
            trackCloseBox(with: event)
        } else if titleBarRect.contains(point) {
            window?.performDrag(with: event)
        }
    }

    /// Close-button tracking: darkened while the mouse is inside, fires on
    /// release inside.
    private func trackCloseBox(with event: NSEvent) {
        let hitRect = closeBoxRect.insetBy(dx: -3, dy: -3)
        closeBoxPressed = true
        needsDisplay = true
        while let next = window?.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            let inside = hitRect.contains(convert(next.locationInWindow, from: nil))
            if inside != closeBoxPressed {
                closeBoxPressed = inside
                needsDisplay = true
            }
            if next.type == .leftMouseUp {
                closeBoxPressed = false
                needsDisplay = true
                if inside { onClose?() }
                return
            }
        }
    }
}
