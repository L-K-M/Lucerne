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

    public init(editor: EditorController) {
        self.editor = editor

        let metrics = editor.pageMetrics
        let initialWidth = min(metrics.pageSize.width + 2 * 28 + 16, 1100)
        let initialHeight: CGFloat = 880
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: max(initialWidth, 680), height: initialHeight),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        window.title = "Lucerne"
        window.tabbingMode = .disallowed
        // Lucerne is a white-paper document editor: render the whole window in the
        // light (aqua) appearance so the toolbar controls, ruler labels, and the
        // text caret stay visible on the white page even when macOS is in Dark Mode.
        window.appearance = NSAppearance(named: .aqua)
        super.init(window: window)

        window.delegate = self
        buildContentView()
        wireEditor()
        window.center()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    // MARK: - Build

    private func buildContentView() {
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = NSColor(calibratedWhite: 0.80, alpha: 1)
        scrollView.documentView = editor.canvasView

        let container = EditorContainerView(toolbar: toolbar, ruler: ruler, scroll: scrollView,
                                            statusBar: statusBar, pageWidth: editor.pageMetrics.pageSize.width)
        window?.contentView = container
        container.layoutContents()
    }

    private func wireEditor() {
        toolbar.editor = editor
        toolbar.onInsertImage = { [weak self] in self?.presentInsertImagePanel() }
        toolbar.onHoverHelp = { [weak self] hint in self?.showStatus(hint) }
        ruler.editor = editor
        let metrics = editor.pageMetrics
        ruler.updateGeometry(marginLeft: metrics.marginLeft, marginRight: metrics.marginRight,
                             pageWidth: metrics.pageSize.width)
        editor.selectionObserver = { [weak self] _ in self?.syncUI() }
        editor.onStatusHint = { [weak self] hint in self?.showStatus(hint) }
    }

    public override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        editor.focusInitialResponder()
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
    @objc func lucerneDeleteImage(_ sender: Any?) { editor.deleteSelectedImage() }
    @objc func lucerneWrapNone(_ sender: Any?) { editor.setWrapMode(.none) }
    @objc func lucerneWrapRectangular(_ sender: Any?) { editor.setWrapMode(.rectangular) }
    @objc func lucerneStandoffIncrease(_ sender: Any?) { editor.adjustSelectedStandoff(by: 4) }
    @objc func lucerneStandoffDecrease(_ sender: Any?) { editor.adjustSelectedStandoff(by: -4) }

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
    private let pageWidth: CGFloat
    private let toolbarHeight: CGFloat = 44
    private let statusHeight: CGFloat = 22

    init(toolbar: ToolbarView, ruler: LucerneRulerView, scroll: NSScrollView,
         statusBar: StatusBarView, pageWidth: CGFloat) {
        self.toolbar = toolbar
        self.ruler = ruler
        self.scroll = scroll
        self.statusBar = statusBar
        self.pageWidth = pageWidth
        super.init(frame: NSRect(x: 0, y: 0, width: 800, height: 800))
        addSubview(scroll)
        addSubview(ruler)
        addSubview(toolbar)
        addSubview(statusBar)
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

    func layoutContents() {
        let w = bounds.width, h = bounds.height
        guard w > 0, h > 0 else { return }

        toolbar.frame = NSRect(x: 0, y: h - toolbarHeight, width: w, height: toolbarHeight)

        let rulerHeight = ruler.rulerHeight
        let rulerX = max(0, ((w - pageWidth) / 2).rounded())
        ruler.frame = NSRect(x: rulerX, y: h - toolbarHeight - rulerHeight,
                             width: min(pageWidth, w), height: rulerHeight)

        statusBar.frame = NSRect(x: 0, y: 0, width: w, height: statusHeight)

        let scrollTop = h - toolbarHeight - rulerHeight
        scroll.frame = NSRect(x: 0, y: statusHeight, width: w, height: max(0, scrollTop - statusHeight))
        (scroll.documentView as? PageCanvasView)?.layoutPages()
    }
}
