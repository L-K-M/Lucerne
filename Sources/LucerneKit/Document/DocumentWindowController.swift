import AppKit
import UniformTypeIdentifiers

// Builds and owns the document window: the toolbar, the ruler, and the scrolling
// page canvas. It is also the responder-chain target for the Format/Insert menu
// actions, forwarding them to the EditorController, and keeps the toolbar + ruler
// in sync with the current selection.
public final class DocumentWindowController: NSWindowController, NSWindowDelegate, NSMenuItemValidation {

    private let editor: EditorController
    private let toolbar = ToolbarView(frame: .zero)
    private let ruler = LucerneRulerView()
    private let scrollView = NSScrollView()
    private let statusBar = StatusBarView(frame: .zero)
    private let navigator = NavigatorView(frame: .zero)

    public init(editor: EditorController) {
        self.editor = editor

        let toolbarFitWidth = toolbar.preferredContentWidth + 24
        // Size the window — and the initial zoom — to the screen and the page format,
        // so a full page is visible at a comfortable scale (see initialLayout).
        let layout = DocumentWindowController.initialLayout(
            page: editor.pageMetrics.pageSize, toolbarWidth: toolbarFitWidth)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: layout.size),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        window.title = "Lucerne"
        window.tabbingMode = .disallowed
        // Keep the window at least as wide as the toolbar so its controls can never
        // be pushed off-screen (capped so it stays reasonable on small displays).
        window.minSize = NSSize(width: min(toolbarFitWidth, 1100), height: 420)
        // Lucerne is a white-paper document editor: render the whole window in the
        // light (aqua) appearance so the toolbar controls, ruler labels, and the
        // text caret stay visible on the white page even when macOS is in Dark Mode.
        window.appearance = NSAppearance(named: .aqua)
        super.init(window: window)

        window.delegate = self
        buildContentView()
        wireEditor()
        applyInitialZoom(layout.zoom)
        window.center()

        // Reposition the ruler when the user scrolls or zooms (the clip view's
        // bounds change covers both), so it keeps tracking the page.
        NotificationCenter.default.addObserver(
            self, selector: #selector(viewportChanged),
            name: NSView.boundsDidChangeNotification, object: scrollView.contentView)
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    // MARK: - Initial window size + zoom

    private struct InitialLayout { let size: NSSize; let zoom: CGFloat }

    /// Picks a window size and starting zoom from the screen and the page format:
    /// zoom so a whole page fits within ~90% of the screen (capped at 100%, so we
    /// never start enlarged), then a window just big enough to show that page plus
    /// the toolbar/ruler/status chrome — capped to the screen.
    private static func initialLayout(page: CGSize, toolbarWidth: CGFloat) -> InitialLayout {
        let chromeHeight: CGFloat = 96     // toolbar (44) + ruler (30) + status (22)
        let titleBar: CGFloat = 28         // outside the content rect, but must fit on screen
        let canvasVPad: CGFloat = 56       // PageCanvasView top + bottom inset
        let canvasHPad: CGFloat = 56       // PageCanvasView left + right inset
        let screen = NSScreen.main?.visibleFrame.size ?? NSSize(width: 1440, height: 900)

        let zoomToFitHeight = (screen.height * 0.90 - titleBar - chromeHeight) / (page.height + canvasVPad)
        let zoomToFitWidth = (screen.width * 0.92) / (page.width + canvasHPad)
        let zoom = min(1.0, max(0.3, min(zoomToFitHeight, zoomToFitWidth)))

        let height = min(screen.height * 0.95 - titleBar, (page.height + canvasVPad) * zoom + chromeHeight)
        let width = min(screen.width * 0.95, max(toolbarWidth, (page.width + canvasHPad) * zoom))
        return InitialLayout(size: NSSize(width: width.rounded(), height: height.rounded()), zoom: zoom)
    }

    private func applyInitialZoom(_ zoom: CGFloat) {
        scrollView.magnification = zoom
        statusBar.setZoom(percent: Int((zoom * 100).rounded()))
    }

    // MARK: - Build

    private func buildContentView() {
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = NSColor(calibratedWhite: 0.68, alpha: 1)
        scrollView.documentView = editor.canvasView
        scrollView.allowsMagnification = true
        scrollView.minMagnification = 0.25
        scrollView.maxMagnification = 4
        scrollView.contentView.postsBoundsChangedNotifications = true

        let container = EditorContainerView(toolbar: toolbar, ruler: ruler, scroll: scrollView,
                                            statusBar: statusBar, navigator: navigator,
                                            pageWidth: editor.pageMetrics.pageSize.width)
        window?.contentView = container
        container.layoutContents()
    }

    private func wireEditor() {
        toolbar.editor = editor
        toolbar.onHoverHelp = { [weak self] hint in self?.showStatus(hint) }
        ruler.editor = editor
        ruler.onHoverHelp = { [weak self] hint in self?.showStatus(hint) }
        let metrics = editor.pageMetrics
        ruler.updateGeometry(marginLeft: metrics.marginLeft, marginRight: metrics.marginRight,
                             pageWidth: metrics.pageSize.width)
        editor.selectionObserver = { [weak self] _ in self?.syncUI() }
        editor.onStatusHint = { [weak self] hint in self?.showStatus(hint) }
        editor.outlineObserver = { [weak self] in
            guard let self else { return }
            self.navigator.setItems(self.editor.headingOutline())
        }
        navigator.onSelect = { [weak self] index in self?.editor.revealHeading(atCharacterIndex: index) }
        statusBar.onZoomIn = { [weak self] in self?.lucerneZoomIn(nil) }
        statusBar.onZoomOut = { [weak self] in self?.lucerneZoomOut(nil) }
        statusBar.onZoomReset = { [weak self] in self?.lucerneActualSize(nil) }
        statusBar.setZoom(percent: 100)
    }

    public override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        editor.documentTitle = (document as? NSDocument)?.displayName ?? ""
        editor.refreshFurniture()
        editor.focusInitialResponder()
        navigator.setItems(editor.headingOutline())
        syncUI()
    }

    private func syncUI() {
        toolbar.syncFromSelection()
        ruler.refresh()
        showStatus(nil)
    }

    /// Show a transient hint, or (when `hint` is nil) the default "what you're
    /// doing" status: current paragraph style and page count.
    private func showStatus(_ hint: String?) {
        statusBar.message = hint ?? defaultStatus()
    }

    private func defaultStatus() -> String {
        let pages = editor.pageCount
        let pageText = pages == 1 ? "1 page" : "\(pages) pages"
        if editor.hasSelectedImage {
            return "Image selected — drag to move · drag a corner to resize (⇧ for free aspect) · ⌫ to delete"
        }
        let styleName = editor.currentStyleRole().flatMap { editor.model.styles[$0]?.name } ?? "Body"
        return "\(styleName)  ·  \(pageText)"
    }

    public func windowDidResize(_ notification: Notification) {
        (window?.contentView as? EditorContainerView)?.layoutContents()
    }

    // MARK: - Insert image

    private func presentInsertImagePanel() {
        guard let window else { return }
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.png, .jpeg, .tiff, .gif, .heic, .bmp]
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url, let self else { return }
            do {
                let data = try Data(contentsOf: url)
                self.editor.insertImage(data: data, suggestedName: url.lastPathComponent)
            } catch {
                self.showError(error)
            }
        }
    }

    private func showError(_ error: Error) {
        guard let window else { return }
        NSAlert(error: error).beginSheetModal(for: window, completionHandler: nil)
    }

    // MARK: - Menu actions (reach here via the responder chain)

    @objc func lucerneToggleBold(_ sender: Any?) { editor.toggleBold(); syncUI() }
    @objc func lucerneToggleItalic(_ sender: Any?) { editor.toggleItalic(); syncUI() }
    @objc func lucerneToggleUnderline(_ sender: Any?) { editor.toggleUnderline(); syncUI() }

    @objc func lucerneAlignLeft(_ sender: Any?) { editor.setAlignment(.left); syncUI() }
    @objc func lucerneAlignCenter(_ sender: Any?) { editor.setAlignment(.center); syncUI() }
    @objc func lucerneAlignRight(_ sender: Any?) { editor.setAlignment(.right); syncUI() }
    @objc func lucerneAlignJustify(_ sender: Any?) { editor.setAlignment(.justified); syncUI() }

    @objc func lucerneApplyStyle(_ sender: NSMenuItem) {
        if let role = sender.representedObject as? String { editor.applyStyleRole(role); syncUI() }
    }

    @objc func lucerneInsertImage(_ sender: Any?) { presentInsertImagePanel() }
    @objc func lucerneInsertPageBreak(_ sender: Any?) { editor.insertPageBreak(); syncUI() }
    @objc func lucerneDeleteImage(_ sender: Any?) { editor.deleteSelectedImage() }
    @objc func lucerneWrapNone(_ sender: Any?) { editor.setWrapMode(.none) }
    @objc func lucerneWrapRectangular(_ sender: Any?) { editor.setWrapMode(.rectangular) }
    @objc func lucerneStandoffIncrease(_ sender: Any?) { editor.adjustSelectedStandoff(by: 4) }
    @objc func lucerneStandoffDecrease(_ sender: Any?) { editor.adjustSelectedStandoff(by: -4) }

    // MARK: - Zoom

    @objc func lucerneZoomIn(_ sender: Any?) { setMagnification(scrollView.magnification * 1.25) }
    @objc func lucerneZoomOut(_ sender: Any?) { setMagnification(scrollView.magnification / 1.25) }
    @objc func lucerneActualSize(_ sender: Any?) { setMagnification(1) }

    private func setMagnification(_ value: CGFloat) {
        scrollView.magnification = min(max(value, scrollView.minMagnification), scrollView.maxMagnification)
        statusBar.setZoom(percent: Int((scrollView.magnification * 100).rounded()))
        (window?.contentView as? EditorContainerView)?.layoutContents()
    }

    @objc func viewportChanged() {
        (window?.contentView as? EditorContainerView)?.layoutContents()
    }

    // MARK: - Headers/footers & navigator

    @objc func lucerneInsertPageNumber(_ sender: Any?) {
        // A plain, centered page number in the footer — the conventional minimal
        // setup. Use Header & Footer… for "Page x of y", other zones, or to choose
        // where numbering starts.
        var footer = editor.model.footer ?? PageFurniture()
        footer.center = "{page}"
        editor.updatePageFurniture(header: editor.model.header, footer: footer,
                                   pageNumberStart: editor.model.pageNumberStart)
    }

    @objc func lucerneHeaderFooter(_ sender: Any?) {
        guard let window else { return }
        HeaderFooterSheet.present(from: window, header: editor.model.header, footer: editor.model.footer,
                                  pageNumberStart: editor.model.pageNumberStart ?? 1) {
            [weak self] header, footer, start in
            self?.editor.updatePageFurniture(header: header, footer: footer, pageNumberStart: start)
        }
    }

    @objc func lucerneToggleNavigator(_ sender: Any?) {
        (window?.contentView as? EditorContainerView)?.toggleNavigator()
    }

    @objc func lucerneTableOfContents(_ sender: Any?) {
        editor.insertOrUpdateTableOfContents()
        syncUI()
    }

    @objc func lucerneInsertTable(_ sender: Any?) {
        guard let window else { return }
        TableInsertSheet.present(from: window) { [weak self] rows, columns in
            self?.editor.insertTable(rows: rows, columns: columns)
            self?.syncUI()
        }
    }

    @objc func lucerneInsertRowAbove(_ sender: Any?) { editor.insertTableRow(below: false); syncUI() }
    @objc func lucerneInsertRowBelow(_ sender: Any?) { editor.insertTableRow(below: true); syncUI() }
    @objc func lucerneInsertColumnBefore(_ sender: Any?) { editor.insertTableColumn(after: false); syncUI() }
    @objc func lucerneInsertColumnAfter(_ sender: Any?) { editor.insertTableColumn(after: true); syncUI() }
    @objc func lucerneDeleteRow(_ sender: Any?) { editor.deleteTableRow(); syncUI() }
    @objc func lucerneDeleteColumn(_ sender: Any?) { editor.deleteTableColumn(); syncUI() }
    @objc func lucerneDistributeColumns(_ sender: Any?) { editor.distributeTableColumnsEvenly(); syncUI() }
    @objc func lucerneSelectTable(_ sender: Any?) { editor.selectCurrentTable() }
    @objc func lucerneMergeCells(_ sender: Any?) { editor.mergeSelectedCells(); syncUI() }

    // MARK: - Document setup (page size + margins)

    @objc func lucerneDocumentSetup(_ sender: Any?) {
        guard let window else { return }
        DocumentSetupSheet.present(from: window, config: editor.model.page) { [weak self] newConfig in
            self?.applyPageConfig(newConfig)
        }
    }

    // Page Setup chooses the page/paper size (A4, Letter, …). Implemented here —
    // ahead of NSDocument in the responder chain — so it drives the document page
    // size (and the ruler/canvas refresh) as well as the print paper size.
    @objc func runPageLayout(_ sender: Any?) {
        guard let doc = document as? NSDocument else { return }
        if NSPageLayout().runModal(with: doc.printInfo) == NSApplication.ModalResponse.OK.rawValue {
            applyPageSize(doc.printInfo.paperSize)
        }
    }

    private func applyPageSize(_ paper: NSSize) {
        let sizeKey: String
        if approxEqual(paper, 595.28, 841.89) { sizeKey = "A4" }
        else if approxEqual(paper, 612, 792) { sizeKey = "Letter" }
        else { sizeKey = "custom" }
        applyPageConfig(PageConfig(size: sizeKey, width: Double(paper.width), height: Double(paper.height),
                                   margins: editor.model.page.margins))
    }

    private func approxEqual(_ size: NSSize, _ width: CGFloat, _ height: CGFloat) -> Bool {
        abs(size.width - width) < 2 && abs(size.height - height) < 2
    }

    private func applyPageConfig(_ newConfig: PageConfig) {
        editor.updatePageConfig(newConfig)
        let metrics = editor.pageMetrics
        ruler.updateGeometry(marginLeft: metrics.marginLeft, marginRight: metrics.marginRight,
                             pageWidth: metrics.pageSize.width)
        (window?.contentView as? EditorContainerView)?.setPageWidth(metrics.pageSize.width)
        syncUI()
    }

    public func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(lucerneDeleteImage(_:)),
             #selector(lucerneWrapNone(_:)),
             #selector(lucerneWrapRectangular(_:)),
             #selector(lucerneStandoffIncrease(_:)),
             #selector(lucerneStandoffDecrease(_:)):
            // Image commands require a selected image; reflect wrap mode with a check.
            if menuItem.action == #selector(lucerneWrapNone(_:)) {
                menuItem.state = editor.selectedImageWrapMode == PlacedObject.Wrap.none ? .on : .off
            } else if menuItem.action == #selector(lucerneWrapRectangular(_:)) {
                menuItem.state = editor.selectedImageWrapMode == .rectangular ? .on : .off
            }
            return editor.hasSelectedImage
        case #selector(lucerneApplyStyle(_:)):
            menuItem.state = (menuItem.representedObject as? String) == editor.currentStyleRole() ? .on : .off
            return true
        case #selector(lucerneAlignLeft(_:)), #selector(lucerneAlignCenter(_:)),
             #selector(lucerneAlignRight(_:)), #selector(lucerneAlignJustify(_:)):
            menuItem.state = alignmentState(for: menuItem.action) ? .on : .off
            return true
        case #selector(lucerneToggleBold(_:)), #selector(lucerneToggleItalic(_:)),
             #selector(lucerneToggleUnderline(_:)):
            return true
        case #selector(lucerneToggleNavigator(_:)):
            menuItem.state = (window?.contentView as? EditorContainerView)?.navigatorVisible == true ? .on : .off
            return true
        case #selector(lucerneInsertRowAbove(_:)), #selector(lucerneInsertRowBelow(_:)),
             #selector(lucerneInsertColumnBefore(_:)), #selector(lucerneInsertColumnAfter(_:)),
             #selector(lucerneDeleteRow(_:)), #selector(lucerneDeleteColumn(_:)),
             #selector(lucerneDistributeColumns(_:)), #selector(lucerneSelectTable(_:)):
            return editor.selectionIsInTableCell   // only valid with the caret in a table
        case #selector(lucerneMergeCells(_:)):
            return editor.selectionSpansMultipleCells   // needs ≥2 selected cells
        default:
            return true
        }
    }

    private func alignmentState(for action: Selector?) -> Bool {
        guard let alignment = editor.selectedParagraphStyle()?.alignment else { return false }
        switch action {
        case #selector(lucerneAlignLeft(_:)): return alignment == .left || alignment == .natural
        case #selector(lucerneAlignCenter(_:)): return alignment == .center
        case #selector(lucerneAlignRight(_:)): return alignment == .right
        case #selector(lucerneAlignJustify(_:)): return alignment == .justified
        default: return false
        }
    }
}

// MARK: - Content layout container

private final class EditorContainerView: NSView {
    private let toolbar: ToolbarView
    private let ruler: LucerneRulerView
    private let scroll: NSScrollView
    private let statusBar: StatusBarView
    private let navigator: NavigatorView
    private var pageWidth: CGFloat
    private let toolbarHeight: CGFloat = 44
    private let statusHeight: CGFloat = 22
    private let navigatorWidth: CGFloat = 210
    private(set) var navigatorVisible = false

    func setPageWidth(_ width: CGFloat) {
        pageWidth = width
        layoutContents()
    }

    func toggleNavigator() {
        navigatorVisible.toggle()
        navigator.isHidden = !navigatorVisible
        layoutContents()
    }

    init(toolbar: ToolbarView, ruler: LucerneRulerView, scroll: NSScrollView,
         statusBar: StatusBarView, navigator: NavigatorView, pageWidth: CGFloat) {
        self.toolbar = toolbar
        self.ruler = ruler
        self.scroll = scroll
        self.statusBar = statusBar
        self.navigator = navigator
        self.pageWidth = pageWidth
        super.init(frame: NSRect(x: 0, y: 0, width: 800, height: 800))
        addSubview(scroll)
        addSubview(ruler)
        addSubview(navigator)
        addSubview(toolbar)
        addSubview(statusBar)
        navigator.isHidden = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        layoutContents()
    }

    override func layout() {
        super.layout()
        layoutContents()
    }

    private var isLayingOut = false

    func layoutContents() {
        let w = bounds.width, h = bounds.height
        guard w > 0, h > 0, !isLayingOut else { return }
        isLayingOut = true
        defer { isLayingOut = false }

        toolbar.frame = NSRect(x: 0, y: h - toolbarHeight, width: w, height: toolbarHeight)
        statusBar.frame = NSRect(x: 0, y: 0, width: w, height: statusHeight)

        let midTop = h - toolbarHeight
        let midHeight = max(0, midTop - statusHeight)
        var leftX: CGFloat = 0
        if navigatorVisible {
            navigator.frame = NSRect(x: 0, y: statusHeight, width: navigatorWidth, height: midHeight)
            leftX = navigatorWidth
        }
        let rightW = w - leftX

        // The ruler + canvas occupy the region to the right of the navigator. The
        // ruler's background/border are continuous across that region; its scale is
        // aligned to the page's on-screen rectangle (so it tracks scroll + zoom).
        let rulerHeight = ruler.rulerHeight
        ruler.frame = NSRect(x: leftX, y: midTop - rulerHeight, width: rightW, height: rulerHeight)
        scroll.frame = NSRect(x: leftX, y: statusHeight, width: rightW, height: max(0, midHeight - rulerHeight))
        (scroll.documentView as? PageCanvasView)?.layoutPages()

        if let pageRect = currentPageOnScreenRect() {
            ruler.setPageGeometry(originX: pageRect.minX, onScreenWidth: pageRect.width)
        } else {
            let pw = min(pageWidth, rightW)
            ruler.setPageGeometry(originX: max(0, ((rightW - pw) / 2).rounded()), onScreenWidth: pw)
        }
    }

    private func currentPageOnScreenRect() -> CGRect? {
        guard let canvas = scroll.documentView as? PageCanvasView,
              let page = canvas.pageViews.first else { return nil }
        return page.convert(page.bounds, to: ruler)
    }
}
