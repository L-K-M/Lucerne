import AppKit
import PDFKit

/// The document object the editor talks back to for undo + dirty tracking.
public protocol EditorControllerDocument: AnyObject {
    var editorUndoManager: UndoManager? { get }
    func editorDidChange()
}

/// The conductor of Avenue A. Owns the single NSTextStorage / NSLayoutManager, the
/// per-page containers + text views, the floating image views, and the canvas.
/// Drives pagination (text overflow → new page), exclusion paths (free placement),
/// and all formatting. See docs/architecture.md.
public final class EditorController: NSObject {

    // MARK: Model + text system
    public private(set) var model: LucerneDocumentModel
    public let textStorage = NSTextStorage()
    public let layoutManager = NSLayoutManager()
    private var metrics: PageMetrics
    public weak var document: EditorControllerDocument?

    /// Decoded images for display, keyed by their `src` path (e.g. "images/lake.png").
    public var images: [String: NSImage] = [:]
    /// Original image bytes keyed by `src`, kept so saving is byte-for-byte lossless.
    public var imageData: [String: Data] = [:]

    // MARK: Views
    public let canvasView = PageCanvasView()
    private final class PageInfo {
        let container: NSTextContainer
        let textView: PageTextView
        let pageView: PageContainerView
        init(container: NSTextContainer, textView: PageTextView, pageView: PageContainerView) {
            self.container = container; self.textView = textView; self.pageView = pageView
        }
    }
    private var pages: [PageInfo] = []
    private var imageViews: [String: FloatingImageView] = [:]

    public private(set) weak var activeTextView: PageTextView?
    private weak var selectedImageView: FloatingImageView?

    private var isUpdatingLayout = false
    private let maxPages = 2000     // safety cap against pathological geometry

    // MARK: - Init

    public init(model: LucerneDocumentModel) {
        self.model = model
        self.metrics = PageMetrics(page: model.page)
        super.init()

        textStorage.addLayoutManager(layoutManager)
        textStorage.delegate = self
        layoutManager.allowsNonContiguousLayout = false

        canvasView.pageSize = metrics.pageSize

        load(model: model)
    }

    // MARK: - Loading / snapshotting the model

    public func load(model: LucerneDocumentModel) {
        self.model = model
        self.metrics = PageMetrics(page: model.page)
        canvasView.pageSize = metrics.pageSize

        // Tear down existing pages/images (used on open/revert).
        while !pages.isEmpty { removeLastPage(force: true) }
        imageViews.values.forEach { $0.removeFromSuperview() }
        imageViews.removeAll()

        addPage()                       // ensure a container exists before text flows
        let attributed = AttributedStringBuilder.attributedString(for: model)
        textStorage.setAttributedString(attributed)
        relayoutText(syncImages: true)

        // Seed typing attributes from the first paragraph so an empty document
        // still types in the Body style rather than the system default.
        if let first = pages.first?.textView {
            let role = model.body.first?.style ?? LucerneDocumentModel.defaultStyleRole
            let id = model.body.first?.id ?? IDGenerator.next("p")
            first.typingAttributes = AttributedStringBuilder.typingAttributes(role: role, in: model, paragraphID: id)
        }
    }

    /// Folds the live text storage back into the canonical model (run on save).
    public func snapshotModel() -> LucerneDocumentModel {
        var snapshot = model
        snapshot.body = AttributedStringReader.paragraphs(from: textStorage, styles: model.styles)
        return snapshot
    }

    // MARK: - Pagination

    private func makeContainer() -> NSTextContainer {
        let container = NSTextContainer(size: metrics.contentSize)
        container.widthTracksTextView = false
        container.heightTracksTextView = false
        container.lineFragmentPadding = 0       // text starts exactly at the margin
        return container
    }

    private func makeTextView(container: NSTextContainer) -> PageTextView {
        let tv = PageTextView(frame: metrics.textFrameInPage, textContainer: container)
        tv.editor = self
        tv.isEditable = true
        tv.isSelectable = true
        tv.isRichText = true
        tv.allowsUndo = true
        tv.isVerticallyResizable = false
        tv.isHorizontallyResizable = false
        tv.drawsBackground = false
        tv.textContainerInset = .zero
        tv.usesFontPanel = true
        tv.usesRuler = false
        tv.minSize = metrics.contentSize
        tv.maxSize = metrics.contentSize
        tv.autoresizingMask = []
        tv.allowsImageEditing = false
        tv.importsGraphics = false
        return tv
    }

    @discardableResult
    private func addPage() -> PageInfo {
        let index = pages.count
        let container = makeContainer()
        layoutManager.addTextContainer(container)        // appended → container index == page index
        let textView = makeTextView(container: container)
        let pageView = PageContainerView(pageIndex: index, frame: CGRect(origin: .zero, size: metrics.pageSize))
        pageView.addSubview(textView)
        let info = PageInfo(container: container, textView: textView, pageView: pageView)
        pages.append(info)
        canvasView.appendPageView(pageView)
        applyExclusionPaths(toPage: index)
        return info
    }

    private func removeLastPage(force: Bool = false) {
        guard let last = pages.last else { return }
        if !force, last.textView == activeTextView {
            // Move the caret to the end of the previous page before removing.
            if pages.count >= 2 {
                let prev = pages[pages.count - 2].textView
                window?.makeFirstResponder(prev)
                prev.setSelectedRange(NSRange(location: (prev.string as NSString).length, length: 0))
            }
        }
        let index = pages.count - 1
        layoutManager.removeTextContainer(at: index)
        last.pageView.removeFromSuperview()
        canvasView.removeLastPageView()
        pages.removeLast()
    }

    private func ensurePageCount() {
        guard metrics.contentSize.height > 1 else { return }
        if pages.isEmpty { addPage() }

        // Grow: add pages while text overflows the last container.
        while overflowsLastContainer() && pages.count < maxPages {
            addPage()
        }
        // Shrink: trim trailing pages that are truly empty (and image-free, and not
        // the page the caret is on).
        while pages.count > 1 && lastPageIsTrulyEmpty() {
            removeLastPage()
        }
    }

    private func overflowsLastContainer() -> Bool {
        guard let last = pages.last?.container else { return false }
        let laid = layoutManager.glyphRange(for: last)     // forces layout for this container
        return NSMaxRange(laid) < layoutManager.numberOfGlyphs
    }

    private func lastPageIsTrulyEmpty() -> Bool {
        guard pages.count >= 2, let last = pages.last else { return false }
        // Keep a page that hosts a floating image or the insertion point.
        if last.pageView.subviews.contains(where: { $0 is FloatingImageView }) { return false }
        if last.textView == activeTextView { return false }

        let range = layoutManager.glyphRange(for: last.container)
        if range.length != 0 { return false }
        if layoutManager.extraLineFragmentTextContainer === last.container { return false }

        let prev = pages[pages.count - 2].container
        let prevRange = layoutManager.glyphRange(for: prev)
        return NSMaxRange(prevRange) >= layoutManager.numberOfGlyphs
    }

    // MARK: - Exclusion paths (free placement)

    private func applyExclusionPaths(toPage index: Int) {
        guard index < pages.count else { return }
        let paths = ExclusionPathController.exclusionPaths(forPage: index, objects: model.objects, metrics: metrics)
        // Setting exclusionPaths invalidates and re-lays-out that container, which
        // is exactly the reflow we want.
        pages[index].container.exclusionPaths = paths
    }

    private func applyAllExclusionPaths() {
        for index in pages.indices { applyExclusionPaths(toPage: index) }
    }

    // MARK: - Relayout orchestration

    private func relayoutText(syncImages: Bool) {
        guard !isUpdatingLayout else { return }
        isUpdatingLayout = true
        ensurePageCount()
        if syncImages { syncImageViews() }
        canvasView.layoutPages()
        isUpdatingLayout = false
    }

    private func relayoutAfterObjectChange(page: Int?) {
        if let page { applyExclusionPaths(toPage: page) } else { applyAllExclusionPaths() }
        relayoutText(syncImages: true)
    }

    // MARK: - Floating image views

    private func makeImageView(for object: PlacedObject) -> FloatingImageView {
        let frame = object.frame.map { metrics.viewFrame(forObjectFrame: $0) } ?? .zero
        let view = FloatingImageView(objectID: object.id, frame: frame)
        view.delegate = self
        view.standoff = CGFloat(object.standoff)
        if let src = object.src { view.image = images[src]; view.placeholderLabel = labelStem(src) }
        return view
    }

    private func labelStem(_ src: String) -> String {
        let name = (src as NSString).lastPathComponent
        let stem = (name as NSString).deletingPathExtension
        return stem.isEmpty ? "Image" : stem
    }

    /// Idempotent: make the image views match the model's page-anchored objects.
    private func syncImageViews() {
        var present = Set<String>()
        for object in model.objects where object.type == "image" {
            guard object.anchorMode == .page,
                  let pageIndex = object.page, pageIndex < pages.count,
                  let frame = object.frame else { continue }
            present.insert(object.id)

            let view = imageViews[object.id] ?? makeImageView(for: object)
            imageViews[object.id] = view

            let pageView = pages[pageIndex].pageView
            if view.superview !== pageView {
                view.removeFromSuperview()
                pageView.addSubview(view)
            }
            let target = metrics.viewFrame(forObjectFrame: frame)
            if view.frame != target { view.frame = target }
            view.standoff = CGFloat(object.standoff)
        }

        for (id, view) in imageViews where !present.contains(id) {
            view.removeFromSuperview()
            imageViews.removeValue(forKey: id)
        }
        restackImages()
    }

    private func restackImages() {
        for (index, page) in pages.enumerated() {
            let desired = model.objects
                .filter { $0.anchorMode == .page && $0.page == index }
                .sorted { $0.z < $1.z }
                .compactMap { imageViews[$0.id] }
            let current = page.pageView.subviews.compactMap { $0 as? FloatingImageView }
            // Idempotent: only reorder when the z-order actually differs, so typing
            // near an image doesn't churn its view every keystroke.
            if current.count == desired.count, zip(current, desired).allSatisfy({ $0 === $1 }) { continue }
            for view in desired {
                view.removeFromSuperview()
                page.pageView.addSubview(view)         // re-add in ascending z → last is frontmost
            }
        }
    }

    // MARK: - Image operations (public)

    /// Replace the image store (used after opening a .luce) and refresh the views.
    public func setImageData(_ data: [String: Data]) {
        imageData = data
        images = data.compactMapValues { NSImage(data: $0) }
        relayoutText(syncImages: true)
    }

    public func insertImage(data: Data, suggestedName: String) {
        insertImageCore(image: NSImage(data: data), data: data, suggestedName: suggestedName)
    }

    public func insertImage(_ image: NSImage, suggestedName: String) {
        insertImageCore(image: image, data: image.pngData() ?? Data(), suggestedName: suggestedName)
    }

    private func insertImageCore(image: NSImage?, data: Data, suggestedName: String) {
        let pageIndex = activePageIndex ?? 0
        let src = uniqueImageSrc(forSuggestedName: suggestedName)
        if !data.isEmpty { imageData[src] = data }
        if let image { images[src] = image }

        let maxW = metrics.contentSize.width * 0.5
        let nativeW = image?.size.width ?? 0
        let w = min(nativeW > 0 ? nativeW : maxW, maxW)
        let h = nativeW > 0 ? (image!.size.height) * (w / nativeW) : w * 0.75
        let frame = RectModel(x: Double(metrics.marginLeft + 24),
                              y: Double(metrics.marginTop + 24),
                              width: Double(w), height: Double(h))
        let nextZ = (model.objects.map(\.z).max() ?? 0) + 1
        let object = PlacedObject(id: IDGenerator.next("img"), type: "image", src: src,
                                  anchor: "page", page: pageIndex, frame: frame,
                                  wrap: "rectangular", standoff: 12, z: nextZ)
        addObject(object, undoName: "Insert Image")
    }

    public func deleteSelectedImage() {
        guard let view = selectedImageView else { return }
        removeObject(id: view.objectID, undoName: "Delete Image")
    }

    public func setStandoff(_ standoff: Double) {
        guard let view = selectedImageView else { return }
        setStandoffByID(view.objectID, standoff, undoName: "Change Standoff")
    }

    public func setWrapMode(_ wrap: PlacedObject.Wrap) {
        guard let view = selectedImageView else { return }
        setWrapByID(view.objectID, wrap.rawValue, undoName: "Change Text Wrap")
    }

    private func setStandoffByID(_ id: String, _ value: Double, undoName: String) {
        guard let index = model.objects.firstIndex(where: { $0.id == id }) else { return }
        let old = model.objects[index].standoff
        model.objects[index].standoff = value
        imageViews[id]?.standoff = CGFloat(value)
        relayoutAfterObjectChange(page: model.objects[index].page)
        registerObjectUndo(undoName) { $0.setStandoffByID(id, old, undoName: undoName) }
        document?.editorDidChange()
    }

    private func setWrapByID(_ id: String, _ value: String, undoName: String) {
        guard let index = model.objects.firstIndex(where: { $0.id == id }) else { return }
        let old = model.objects[index].wrap
        model.objects[index].wrap = value
        relayoutAfterObjectChange(page: model.objects[index].page)
        registerObjectUndo(undoName) { $0.setWrapByID(id, old, undoName: undoName) }
        document?.editorDidChange()
    }

    private func uniqueImageSrc(forSuggestedName name: String) -> String {
        let ext = (name as NSString).pathExtension
        let stem = (name as NSString).deletingPathExtension
        let safeStem = stem.isEmpty ? "image" : stem
        let safeExt = ext.isEmpty ? "png" : ext
        var candidate = "images/\(safeStem).\(safeExt)"
        var counter = 2
        while images[candidate] != nil || imageData[candidate] != nil {
            candidate = "images/\(safeStem)-\(counter).\(safeExt)"
            counter += 1
        }
        return candidate
    }

    private func addObject(_ object: PlacedObject, undoName: String) {
        model.objects.append(object)
        relayoutAfterObjectChange(page: object.page)
        registerObjectUndo(undoName) { $0.removeObject(id: object.id, undoName: undoName) }
        document?.editorDidChange()
    }

    private func removeObject(id: String, undoName: String) {
        guard let index = model.objects.firstIndex(where: { $0.id == id }) else { return }
        let removed = model.objects.remove(at: index)
        if let view = imageViews[id], view === selectedImageView { selectedImageView = nil }
        imageViews[id]?.removeFromSuperview()
        imageViews.removeValue(forKey: id)
        relayoutAfterObjectChange(page: removed.page)
        // The image bytes stay in `images`, so re-adding restores the picture too.
        registerObjectUndo(undoName) { $0.addObject(removed, undoName: undoName) }
        document?.editorDidChange()
    }

    private func setObjectFrame(id: String, to newFrame: CGRect, undoName: String) {
        guard let index = model.objects.firstIndex(where: { $0.id == id }) else { return }
        let clamped = metrics.clampObjectFrame(newFrame)
        let previous = model.objects[index].frame
        model.objects[index].frame = RectModel(clamped)
        if let view = imageViews[id], view.frame != clamped { view.frame = clamped }
        relayoutAfterObjectChange(page: model.objects[index].page)
        registerObjectUndo(undoName) { controller in
            controller.setObjectFrame(id: id, to: (previous ?? RectModel(clamped)).cgRect, undoName: undoName)
        }
        document?.editorDidChange()
    }

    private func registerObjectUndo(_ name: String, _ action: @escaping (EditorController) -> Void) {
        guard let undo = document?.editorUndoManager else { return }
        undo.registerUndo(withTarget: self) { action($0) }
        undo.setActionName(name)
    }

    // MARK: - Formatting

    /// Whole-text snapshot undo for attribute edits (small letters → cheap & exact).
    private func withUndo(_ name: String, _ changes: () -> Void) {
        guard let storage = activeTextView?.textStorage else { changes(); return }
        let before = storage.copy() as! NSAttributedString
        changes()
        relayoutText(syncImages: false)
        if let undo = document?.editorUndoManager {
            undo.registerUndo(withTarget: self) { $0.restoreText(before, name: name) }
            undo.setActionName(name)
        }
        document?.editorDidChange()
    }

    private func restoreText(_ snapshot: NSAttributedString, name: String) {
        let storage = textStorage
        let redo = storage.copy() as! NSAttributedString
        storage.setAttributedString(snapshot)
        relayoutText(syncImages: false)
        if let undo = document?.editorUndoManager {
            undo.registerUndo(withTarget: self) { $0.restoreText(redo, name: name) }
            undo.setActionName(name)
        }
        document?.editorDidChange()
    }

    public func toggleBold() { toggleTrait(.boldFontMask, name: "Bold") }
    public func toggleItalic() { toggleTrait(.italicFontMask, name: "Italic") }

    private func toggleTrait(_ trait: NSFontTraitMask, name: String) {
        guard let tv = activeTextView, let storage = tv.textStorage else { return }
        let range = tv.selectedRange()
        let fm = NSFontManager.shared

        if range.length == 0 {
            let current = (tv.typingAttributes[.font] as? NSFont) ?? NSFont.systemFont(ofSize: 12)
            let has = fm.traits(of: current).contains(trait)
            tv.typingAttributes[.font] = has ? fm.convert(current, toNotHaveTrait: trait)
                                             : fm.convert(current, toHaveTrait: trait)
            return
        }

        var allHaveTrait = true
        storage.enumerateAttribute(.font, in: range, options: []) { value, _, _ in
            let font = (value as? NSFont) ?? NSFont.systemFont(ofSize: 12)
            if !fm.traits(of: font).contains(trait) { allHaveTrait = false }
        }
        withUndo(name) {
            storage.beginEditing()
            storage.enumerateAttribute(.font, in: range, options: []) { value, sub, _ in
                let font = (value as? NSFont) ?? NSFont.systemFont(ofSize: 12)
                let converted = allHaveTrait ? fm.convert(font, toNotHaveTrait: trait)
                                             : fm.convert(font, toHaveTrait: trait)
                storage.addAttribute(.font, value: converted, range: sub)
            }
            storage.endEditing()
        }
    }

    public func toggleUnderline() {
        guard let tv = activeTextView, let storage = tv.textStorage else { return }
        let range = tv.selectedRange()
        if range.length == 0 {
            let on = (tv.typingAttributes[.underlineStyle] as? Int ?? 0) != 0
            tv.typingAttributes[.underlineStyle] = on ? 0 : NSUnderlineStyle.single.rawValue
            return
        }
        var allUnderlined = true
        storage.enumerateAttribute(.underlineStyle, in: range, options: []) { value, _, _ in
            if (value as? Int ?? 0) == 0 { allUnderlined = false }
        }
        withUndo("Underline") {
            let newValue = allUnderlined ? 0 : NSUnderlineStyle.single.rawValue
            storage.addAttribute(.underlineStyle, value: newValue, range: range)
        }
    }

    public func setAlignment(_ alignment: NSTextAlignment) {
        modifyParagraphStyle(name: "Alignment") { $0.alignment = alignment }
    }
    public func setLineHeightMultiple(_ multiple: CGFloat) {
        modifyParagraphStyle(name: "Line Spacing") { $0.lineHeightMultiple = multiple }
    }
    public func setParagraphSpacingAfter(_ points: CGFloat) {
        modifyParagraphStyle(name: "Paragraph Spacing") { $0.paragraphSpacing = points }
    }
    public func setIndents(left: CGFloat, firstLine: CGFloat, right: CGFloat) {
        modifyParagraphStyle(name: "Indents") {
            $0.headIndent = left
            $0.firstLineHeadIndent = left + firstLine
            $0.tailIndent = right > 0 ? -right : 0
        }
    }
    public func setTabStops(_ tabs: [NSTextTab]) {
        modifyParagraphStyle(name: "Tab Stops") { $0.tabStops = tabs }
    }

    private func modifyParagraphStyle(name: String, _ transform: @escaping (NSMutableParagraphStyle) -> Void) {
        guard let tv = activeTextView, let storage = tv.textStorage else { return }
        let ns = storage.string as NSString

        if storage.length == 0 {
            let ps = (tv.typingAttributes[.paragraphStyle] as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle ?? NSMutableParagraphStyle()
            transform(ps)
            tv.typingAttributes[.paragraphStyle] = ps
            return
        }

        withUndo(name) {
            storage.beginEditing()
            for selection in tv.selectedRanges.map({ $0.rangeValue }) {
                let paragraphRange = ns.paragraphRange(for: selection)
                storage.enumerateAttribute(.paragraphStyle, in: paragraphRange, options: []) { value, sub, _ in
                    let ps = (value as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle ?? NSMutableParagraphStyle()
                    transform(ps)
                    storage.addAttribute(.paragraphStyle, value: ps, range: sub)
                }
            }
            storage.endEditing()
        }
    }

    public func setFontFamily(_ family: String) {
        applyFontTransform(name: "Font") { NSFontManager.shared.convert($0, toFamily: family) }
    }
    public func setFontSize(_ size: CGFloat) {
        applyFontTransform(name: "Font Size") { NSFontManager.shared.convert($0, toSize: size) }
    }

    private func applyFontTransform(name: String, _ transform: @escaping (NSFont) -> NSFont) {
        guard let tv = activeTextView, let storage = tv.textStorage else { return }
        let range = tv.selectedRange()
        if range.length == 0 {
            let current = (tv.typingAttributes[.font] as? NSFont) ?? NSFont.systemFont(ofSize: 12)
            tv.typingAttributes[.font] = transform(current)
            return
        }
        withUndo(name) {
            storage.beginEditing()
            storage.enumerateAttribute(.font, in: range, options: []) { value, sub, _ in
                let font = (value as? NSFont) ?? NSFont.systemFont(ofSize: 12)
                storage.addAttribute(.font, value: transform(font), range: sub)
            }
            storage.endEditing()
        }
    }

    public func setTextColor(_ color: NSColor) {
        guard let tv = activeTextView, let storage = tv.textStorage else { return }
        let range = tv.selectedRange()
        if range.length == 0 {
            tv.typingAttributes[.foregroundColor] = color
            return
        }
        withUndo("Text Color") {
            storage.addAttribute(.foregroundColor, value: color, range: range)
        }
    }

    public func applyStyleRole(_ role: String) {
        guard let tv = activeTextView, let storage = tv.textStorage else { return }
        let ns = storage.string as NSString
        if storage.length == 0 {
            let id = model.body.first?.id ?? IDGenerator.next("p")
            tv.typingAttributes = AttributedStringBuilder.typingAttributes(role: role, in: model, paragraphID: id)
            return
        }
        withUndo("Apply Style") {
            storage.beginEditing()
            for selection in tv.selectedRanges.map({ $0.rangeValue }) {
                let paragraphRange = ns.paragraphRange(for: selection)
                // Re-apply per individual paragraph to preserve each paragraph's id.
                var cursor = paragraphRange.location
                while cursor < NSMaxRange(paragraphRange) {
                    let single = ns.paragraphRange(for: NSRange(location: cursor, length: 0))
                    let id = (storage.attribute(.lucerneParagraphID, at: single.location, effectiveRange: nil) as? String)
                        ?? IDGenerator.next("p")
                    let attrs = AttributedStringBuilder.typingAttributes(role: role, in: model, paragraphID: id)
                    storage.setAttributes(attrs, range: single)
                    if NSMaxRange(single) == cursor { break }
                    cursor = NSMaxRange(single)
                }
            }
            storage.endEditing()
        }
    }

    // MARK: - Style table editing (used by the inspector / style menu)

    public func currentStyleRole() -> String? {
        guard let tv = activeTextView, let storage = tv.textStorage, storage.length > 0 else {
            return activeTextView?.typingAttributes[.lucerneStyleRole] as? String
        }
        let loc = min(tv.selectedRange().location, storage.length - 1)
        return storage.attribute(.lucerneStyleRole, at: loc, effectiveRange: nil) as? String
    }

    /// Attributes at the caret/selection start (or typing attributes), for toolbar sync.
    public func currentAttributes() -> [NSAttributedString.Key: Any] {
        guard let tv = activeTextView else { return [:] }
        if let storage = tv.textStorage, storage.length > 0 {
            let loc = min(tv.selectedRange().location, storage.length - 1)
            return storage.attributes(at: loc, effectiveRange: nil)
        }
        return tv.typingAttributes
    }

    public var hasSelectedImage: Bool { selectedImageView != nil }

    public var selectedImageWrapMode: PlacedObject.Wrap? {
        guard let id = selectedImageView?.objectID,
              let object = model.objects.first(where: { $0.id == id }) else { return nil }
        return object.wrapMode
    }

    public func adjustSelectedStandoff(by delta: Double) {
        guard let id = selectedImageView?.objectID,
              let index = model.objects.firstIndex(where: { $0.id == id }) else { return }
        let newValue = max(0, model.objects[index].standoff + delta)
        setStandoffByID(id, newValue, undoName: "Change Standoff")
    }

    /// Put the keyboard focus on the first page so typing works as soon as the
    /// window appears.
    public func focusInitialResponder() {
        guard let tv = pages.first?.textView else { return }
        tv.window?.makeFirstResponder(tv)
    }

    // MARK: - Active view / selection tracking

    public var activePageIndex: Int? {
        guard let active = activeTextView else { return pages.isEmpty ? nil : 0 }
        return pages.firstIndex { $0.textView === active }
    }

    func textViewBecameActive(_ textView: PageTextView) {
        activeTextView = textView
        deselectAllImages()
    }

    func activeSelectionChanged(in textView: PageTextView) {
        activeTextView = textView
        selectionObserver?(self)
    }

    /// Called when the selection or active formatting changes (for toolbar/ruler sync).
    public var selectionObserver: ((EditorController) -> Void)?

    func deselectAllImages() {
        selectedImageView?.isSelected = false
        selectedImageView = nil
    }

    private var window: NSWindow? { canvasView.window }

    // MARK: - Page configuration

    public func updatePageConfig(_ page: PageConfig) {
        var snapshot = snapshotModel()
        snapshot.page = page
        load(model: snapshot)
        document?.editorDidChange()
    }

    /// Read-only access for the ruler.
    public func selectedParagraphStyle() -> NSParagraphStyle? {
        guard let tv = activeTextView, let storage = tv.textStorage else { return nil }
        if storage.length == 0 { return tv.typingAttributes[.paragraphStyle] as? NSParagraphStyle }
        let loc = min(tv.selectedRange().location, storage.length - 1)
        return storage.attribute(.paragraphStyle, at: loc, effectiveRange: nil) as? NSParagraphStyle
    }

    public var pageMetrics: PageMetrics { metrics }

    // MARK: - PDF / print rendering

    /// One single-page PDF per document page, captured from the real view drawing
    /// (text + images), so fidelity matches the screen. Selection chrome is hidden
    /// first. The page size is the document page size, in points.
    public func makePagePDFs() -> [Data] {
        deselectAllImages()
        canvasView.layoutPages()
        if let last = pages.last?.container { layoutManager.ensureLayout(for: last) }
        return pages.map { $0.pageView.dataWithPDF(inside: $0.pageView.bounds) }
    }

    /// The whole document as a single multi-page PDF (share / print / export).
    public func makePDFData() -> Data {
        let document = PDFDocument()
        for data in makePagePDFs() {
            guard let pageDoc = PDFDocument(data: data), let page = pageDoc.page(at: 0) else { continue }
            document.insert(page, at: document.pageCount)
        }
        return document.dataRepresentation() ?? Data()
    }
}

// MARK: - NSTextStorageDelegate (drive pagination on every edit)

extension EditorController: NSTextStorageDelegate {
    public func textStorage(_ textStorage: NSTextStorage,
                            didProcessEditing editedMask: NSTextStorageEditActions,
                            range editedRange: NSRange,
                            changeInLength delta: Int) {
        guard editedMask.contains(.editedCharacters) || editedMask.contains(.editedAttributes) else { return }
        // Defer to the next runloop turn so layout settles before we add/trim pages.
        DispatchQueue.main.async { [weak self] in
            self?.relayoutText(syncImages: true)
        }
    }
}

// MARK: - FloatingImageViewDelegate

extension EditorController: FloatingImageViewDelegate {
    public func floatingImageViewDidSelect(_ view: FloatingImageView) {
        if selectedImageView !== view {
            selectedImageView?.isSelected = false
            selectedImageView = view
        }
        view.isSelected = true
        selectionObserver?(self)
    }

    public func floatingImageView(_ view: FloatingImageView, didChangeFrameLive frame: CGRect) {
        guard let index = model.objects.firstIndex(where: { $0.id == view.objectID }) else { return }
        let clamped = metrics.clampObjectFrame(frame)
        if clamped != frame { view.frame = clamped }
        model.objects[index].frame = RectModel(clamped)
        applyExclusionPaths(toPage: model.objects[index].page ?? 0)
        relayoutText(syncImages: false)
    }

    public func floatingImageView(_ view: FloatingImageView, didCommitFrom oldFrame: CGRect, to newFrame: CGRect) {
        guard let index = model.objects.firstIndex(where: { $0.id == view.objectID }) else { return }
        // The live updates already moved the model to `newFrame`; reset to `oldFrame`
        // then route through setObjectFrame so a single undo step is recorded.
        model.objects[index].frame = RectModel(oldFrame)
        setObjectFrame(id: view.objectID, to: newFrame, undoName: "Move Image")
    }

    public func floatingImageViewRequestsDelete(_ view: FloatingImageView) {
        removeObject(id: view.objectID, undoName: "Delete Image")
    }
}
