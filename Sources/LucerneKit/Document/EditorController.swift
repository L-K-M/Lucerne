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
    private var dragStartPlacement: (page: Int?, frame: RectModel?)?
    private var movingImageID: String?

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
        tv.delegate = self
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
        pageView.marginTop = metrics.marginTop
        pageView.marginLeft = metrics.marginLeft
        pageView.marginBottom = metrics.marginBottom
        pageView.marginRight = metrics.marginRight
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

    /// Grows/trims pages to fit the text and assigns each container's exclusion
    /// paths (image wrap + forced page-break bands). When the document has no page
    /// breaks this behaves exactly like simple overflow pagination.
    private func paginateAndExclude() {
        guard metrics.contentSize.height > 1 else { return }
        if pages.isEmpty { addPage() }

        let breaks = pageBreakCharIndices()
        var bandedPages = Set<Int>()
        for index in pages.indices { pages[index].container.exclusionPaths = imageExclusions(index) }

        var guardCount = 0
        let limit = maxPages + breaks.count + 4
        while guardCount < limit {
            guardCount += 1
            _ = layoutManager.glyphRange(for: pages[pages.count - 1].container)  // force layout

            if overflowsLastContainer(), pages.count < maxPages {
                addPage()
                continue
            }
            if !breaks.isEmpty, let page = firstPageNeedingBreakBand(breaks: breaks, banded: bandedPages) {
                pages[page].container.exclusionPaths = imageExclusions(page) + breakBands(forPage: page, breaks: breaks)
                bandedPages.insert(page)
                continue
            }
            break
        }

        while pages.count > 1 && lastPageIsTrulyEmpty() { removeLastPage() }
    }

    private func imageExclusions(_ index: Int) -> [NSBezierPath] {
        ExclusionPathController.exclusionPaths(forPage: index, objects: model.objects, metrics: metrics)
    }

    private func pageBreakCharIndices() -> [Int] {
        guard textStorage.length > 0 else { return [] }
        var result: [Int] = []
        textStorage.enumerateAttribute(.lucernePageBreakBefore,
                                       in: NSRange(location: 0, length: textStorage.length),
                                       options: []) { value, range, _ in
            if (value as? Bool) == true { result.append(range.location) }
        }
        return result
    }

    private func breakPageAndLineTop(forCharAt charIndex: Int) -> (page: Int, top: CGFloat)? {
        guard charIndex < textStorage.length else { return nil }
        let glyph = layoutManager.glyphIndexForCharacter(at: charIndex)
        guard let container = layoutManager.textContainer(forGlyphAt: glyph, effectiveRange: nil),
              let page = pages.firstIndex(where: { $0.container === container }) else { return nil }
        let line = layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
        return (page, line.minY)
    }

    private func firstPageNeedingBreakBand(breaks: [Int], banded: Set<Int>) -> Int? {
        for charIndex in breaks {
            guard let (page, top) = breakPageAndLineTop(forCharAt: charIndex) else { continue }
            if top > 0.5, !banded.contains(page) { return page }
        }
        return nil
    }

    private func breakBands(forPage page: Int, breaks: [Int]) -> [NSBezierPath] {
        // Exclude from the topmost break's line down to the page bottom, so that
        // line (and everything after it) flows to the next page.
        var topmost: CGFloat?
        for charIndex in breaks {
            guard let (p, top) = breakPageAndLineTop(forCharAt: charIndex), p == page, top > 0.5 else { continue }
            topmost = min(topmost ?? top, top)
        }
        guard let top = topmost else { return [] }
        let band = NSRect(x: 0, y: top, width: metrics.contentSize.width,
                          height: max(0, metrics.contentSize.height - top))
        return [NSBezierPath(rect: band)]
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
        pages[index].container.exclusionPaths = imageExclusions(index)
    }

    // MARK: - Relayout orchestration

    private func relayoutText(syncImages: Bool) {
        guard !isUpdatingLayout else { return }
        isUpdatingLayout = true
        paginateAndExclude()
        if syncImages { syncImageViews() }
        canvasView.layoutPages()
        updateFurniture()
        isUpdatingLayout = false
        outlineObserver?()
    }

    private func relayoutAfterObjectChange(page: Int?) {
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

    /// Insert at a specific page-relative point (used by drag-and-drop), centering
    /// the image on the drop location.
    public func insertImage(data: Data, suggestedName: String, onPage pageIndex: Int, centeredAt center: CGPoint) {
        insertImageCore(image: NSImage(data: data), data: data, suggestedName: suggestedName,
                        page: pageIndex, center: center)
    }

    private func insertImageCore(image: NSImage?, data: Data, suggestedName: String,
                                 page: Int? = nil, center: CGPoint? = nil) {
        let pageIndex = page ?? activePageIndex ?? 0
        let src = uniqueImageSrc(forSuggestedName: suggestedName)
        if !data.isEmpty { imageData[src] = data }
        if let image { images[src] = image }

        let maxW = metrics.contentSize.width * 0.5
        let nativeW = image?.size.width ?? 0
        let w = min(nativeW > 0 ? nativeW : maxW, maxW)
        let h = nativeW > 0 ? (image!.size.height) * (w / nativeW) : w * 0.75
        let origin: CGPoint = center.map { CGPoint(x: $0.x - w / 2, y: $0.y - h / 2) }
            ?? CGPoint(x: metrics.marginLeft + 24, y: metrics.marginTop + 24)
        let clamped = metrics.clampObjectFrame(CGRect(x: origin.x, y: origin.y, width: w, height: h))
        let nextZ = (model.objects.map(\.z).max() ?? 0) + 1
        let object = PlacedObject(id: IDGenerator.next("img"), type: "image", src: src,
                                  anchor: "page", page: pageIndex, frame: RectModel(clamped),
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

    private func registerObjectUndo(_ name: String, _ action: @escaping (EditorController) -> Void) {
        guard let undo = document?.editorUndoManager else { return }
        undo.registerUndo(withTarget: self) { action($0) }
        undo.setActionName(name)
    }

    // MARK: - Formatting

    /// The text view formatting commands act on: the active one, or the first page
    /// if focus hasn't landed in the text yet. This means a toolbar/menu command
    /// always has a target — fixing "the tools look active but do nothing" when no
    /// text view is first responder. With no selection, commands set the typing
    /// attributes so the next typed text picks up the change.
    private func formattingTextView() -> PageTextView? {
        if activeTextView == nil { activeTextView = pages.first?.textView }
        return activeTextView
    }

    /// Returns keyboard focus to the editing surface — called after a toolbar action
    /// so a change made with no selection (a typing-attribute change) is immediately
    /// usable: the caret returns to the page, ready to type in the new format.
    public func focusActiveTextView() {
        let tv = activeTextView ?? pages.first?.textView
        tv?.window?.makeFirstResponder(tv)
    }

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
        guard let tv = formattingTextView(), let storage = tv.textStorage else { return }
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
        guard let tv = formattingTextView(), let storage = tv.textStorage else { return }
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
    /// Tab stops are document-global: setting them on the ruler applies the same
    /// stops to every paragraph (and to typing attributes, so new paragraphs
    /// inherit them too). Indents remain per-paragraph.
    public func setTabStops(_ tabs: [NSTextTab]) {
        guard let tv = formattingTextView(), let storage = tv.textStorage else { return }

        if storage.length > 0 {
            withUndo("Tab Stops") {
                let whole = NSRange(location: 0, length: storage.length)
                storage.beginEditing()
                storage.enumerateAttribute(.paragraphStyle, in: whole, options: []) { value, sub, _ in
                    let ps = (value as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle
                        ?? NSMutableParagraphStyle()
                    ps.tabStops = tabs
                    storage.addAttribute(.paragraphStyle, value: ps, range: sub)
                }
                storage.endEditing()
            }
        }

        let typingPS = (tv.typingAttributes[.paragraphStyle] as? NSParagraphStyle)?.mutableCopy()
            as? NSMutableParagraphStyle ?? NSMutableParagraphStyle()
        typingPS.tabStops = tabs
        tv.typingAttributes[.paragraphStyle] = typingPS
    }

    private func modifyParagraphStyle(name: String, _ transform: @escaping (NSMutableParagraphStyle) -> Void) {
        guard let tv = formattingTextView(), let storage = tv.textStorage else { return }
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
        guard let tv = formattingTextView(), let storage = tv.textStorage else { return }
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
        guard let tv = formattingTextView(), let storage = tv.textStorage else { return }
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
        guard let tv = formattingTextView(), let storage = tv.textStorage else { return }
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

    /// Inserts a forced page break at the caret: the text from here on starts on a
    /// new page. Implemented by flagging the paragraph that begins at the caret
    /// (splitting the current paragraph first if the caret is mid-paragraph).
    public func insertPageBreak() {
        guard let tv = formattingTextView(), let storage = tv.textStorage else { return }
        withUndo("Insert Page Break") {
            let ns = storage.string as NSString
            let loc = min(tv.selectedRange().location, ns.length)
            let atParagraphStart = loc == 0 || ns.character(at: loc - 1) == 0x0A || ns.character(at: loc - 1) == 0x0D
            var markLoc = loc
            if !atParagraphStart {
                storage.insert(NSAttributedString(string: "\n", attributes: tv.typingAttributes), at: loc)
                markLoc = loc + 1
            }
            if markLoc >= storage.length {
                // Page break at the very end: add an empty paragraph to carry it.
                storage.insert(NSAttributedString(string: "\n", attributes: tv.typingAttributes), at: storage.length)
            }
            if markLoc < storage.length {
                storage.addAttribute(.lucernePageBreakBefore, value: true,
                                     range: NSRange(location: markLoc, length: 1))
            }
            tv.setSelectedRange(NSRange(location: min(markLoc, (storage.string as NSString).length), length: 0))
        }
    }

    // MARK: - Tables

    /// Inserts a `rows × columns` table at the caret. Each cell is an empty paragraph
    /// carrying its `NSTextTableBlock`; TextKit lays them into the grid and flows the
    /// table through the page containers. The cell paragraphs round-trip to the model
    /// as `Paragraph.cell` (see AttributedStringBuilder/Reader). Click a cell to type;
    /// the table is bounded above/below by ordinary body paragraphs.
    public func insertTable(rows: Int, columns: Int) {
        guard rows > 0, columns > 0,
              let tv = formattingTextView(), let storage = tv.textStorage else { return }
        let table = AttributedStringBuilder.makeTextTable(columns: columns)
        let cells = NSMutableAttributedString()
        for r in 0 ..< rows {
            for c in 0 ..< columns {
                let block = AttributedStringBuilder.makeTableBlock(
                    table: table, row: r, column: c, rowSpan: 1, columnSpan: 1)
                cells.append(NSAttributedString(string: "\n", attributes: tableCellAttributes(block: block)))
            }
        }
        withUndo("Insert Table") {
            let ns = storage.string as NSString
            let caret = min(tv.selectedRange().location, ns.length)
            let atParagraphStart = caret == 0 || ns.character(at: caret - 1) == 0x0A
            let bodyAttrs = AttributedStringBuilder.typingAttributes(
                role: LucerneDocumentModel.defaultStyleRole, in: model, paragraphID: IDGenerator.next("p"))
            // Prepend a body paragraph when the caret is mid-paragraph (to break out of
            // it) OR at the very start of the document — otherwise a table that is the
            // first paragraph has no line above it, and the caret can't be placed there.
            let needsLeading = !atParagraphStart || caret == 0
            let insert = NSMutableAttributedString()
            if needsLeading { insert.append(NSAttributedString(string: "\n", attributes: bodyAttrs)) }
            insert.append(cells)
            // Ensure a normal body paragraph follows the table (terminates the last
            // cell with non-cell text) when inserting at the very end of the document.
            if caret == ns.length { insert.append(NSAttributedString(string: "\n", attributes: bodyAttrs)) }
            storage.insert(insert, at: caret)
            let firstCell = caret + (needsLeading ? 1 : 0)
            tv.setSelectedRange(NSRange(location: min(firstCell, (storage.string as NSString).length), length: 0))
        }
    }

    /// Attributes for a single (empty) table cell paragraph: the Body typing
    /// attributes (so the cell inherits the body font and, crucially, the *empty*
    /// tab-stop array rather than NSParagraphStyle's default stops, which otherwise
    /// show up as phantom tabs on the ruler) plus the cell's block.
    private func tableCellAttributes(block: NSTextTableBlock) -> [NSAttributedString.Key: Any] {
        let role = LucerneDocumentModel.defaultStyleRole
        var attrs = AttributedStringBuilder.typingAttributes(
            role: role, in: model, paragraphID: IDGenerator.next("cell"))
        let ps = (attrs[.paragraphStyle] as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle
            ?? NSMutableParagraphStyle()
        ps.textBlocks = [block]
        attrs[.paragraphStyle] = ps
        return attrs
    }

    // MARK: - Table editing (insert / delete row & column)

    /// Whether the caret is currently inside a table cell (drives menu validation
    /// and the context menu's table commands).
    public var selectionIsInTableCell: Bool {
        guard let tv = activeTextView else { return false }
        return tableBlock(atCharacterIndex: tv.selectedRange().location) != nil
    }

    public func insertTableRow(below: Bool) {
        modifyCurrentTable { grid, caretRow, _ in
            let columns = grid.first?.count ?? 0
            let at = min(max(0, below ? caretRow + 1 : caretRow), grid.count)
            grid.insert(Array(repeating: NSAttributedString(string: ""), count: columns), at: at)
            return (min(at, grid.count - 1), 0)
        }
    }

    public func insertTableColumn(after: Bool) {
        modifyCurrentTable { grid, _, caretCol in
            let at = after ? caretCol + 1 : caretCol
            for r in grid.indices { grid[r].insert(NSAttributedString(string: ""), at: min(max(0, at), grid[r].count)) }
            return (0, min(at, (grid.first?.count ?? 1) - 1))
        }
    }

    public func deleteTableRow() {
        modifyCurrentTable { grid, caretRow, caretCol in
            guard grid.count > 1 else { return nil }   // keep at least one row
            grid.remove(at: min(caretRow, grid.count - 1))
            return (min(caretRow, grid.count - 1), caretCol)
        }
    }

    public func deleteTableColumn() {
        modifyCurrentTable { grid, caretRow, caretCol in
            guard (grid.first?.count ?? 0) > 1 else { return nil }   // keep at least one column
            for r in grid.indices { grid[r].remove(at: min(caretCol, grid[r].count - 1)) }
            return (caretRow, min(caretCol, (grid.first?.count ?? 1) - 1))
        }
    }

    /// The NSTextTableBlock of the cell a character index is in (nil if not a cell).
    private func tableBlock(atCharacterIndex index: Int) -> NSTextTableBlock? {
        guard textStorage.length > 0 else { return nil }
        let probe = min(max(0, index), textStorage.length - 1)
        let ps = textStorage.attribute(.paragraphStyle, at: probe, effectiveRange: nil) as? NSParagraphStyle
        return ps?.textBlocks.compactMap { $0 as? NSTextTableBlock }.first
    }

    private struct ParsedTable {
        var range: NSRange                 // the table's full character range in storage
        var rows: Int
        var columns: Int
        var cells: [[NSAttributedString]]  // per-cell content (without the terminating newline)
        var columnWidths: [Double]         // per-column width, percent of the table
    }

    /// Reads a table's grid out of the storage as a rectangular array of cell content
    /// (single paragraph per cell — multi-paragraph cells collapse to their first).
    private func parseTable(containing table: NSTextTable) -> ParsedTable? {
        let ns = textStorage.string as NSString
        var contentByCell: [String: NSAttributedString] = [:]
        var widthByColumn: [Int: Double] = [:]
        var maxRow = 0, maxColumn = 0
        var rangeStart = -1, rangeEnd = -1
        var location = 0
        while location < ns.length {
            var start = 0, end = 0, contentsEnd = 0
            ns.getParagraphStart(&start, end: &end, contentsEnd: &contentsEnd,
                                 for: NSRange(location: location, length: 0))
            let probe = contentsEnd > start ? start : min(start, max(0, ns.length - 1))
            let ps = textStorage.attribute(.paragraphStyle, at: probe, effectiveRange: nil) as? NSParagraphStyle
            if let block = ps?.textBlocks.compactMap({ $0 as? NSTextTableBlock }).first, block.table === table {
                if rangeStart < 0 { rangeStart = start }
                rangeEnd = end
                let key = "\(block.startingRow),\(block.startingColumn)"
                if contentByCell[key] == nil {
                    contentByCell[key] = textStorage.attributedSubstring(
                        from: NSRange(location: start, length: contentsEnd - start))
                }
                if widthByColumn[block.startingColumn] == nil,
                   block.valueType(for: .width) == .percentageValueType {
                    let w = Double(block.value(for: .width))
                    if w > 0 { widthByColumn[block.startingColumn] = w }
                }
                maxRow = max(maxRow, block.startingRow)
                maxColumn = max(maxColumn, block.startingColumn)
            } else if rangeStart >= 0 {
                break   // a table's cells are contiguous; stop at the first paragraph after it
            }
            if end == location { break }
            location = end
        }
        guard rangeStart >= 0 else { return nil }
        let rows = maxRow + 1, columns = maxColumn + 1
        let grid = (0 ..< rows).map { r in
            (0 ..< columns).map { c in contentByCell["\(r),\(c)"] ?? NSAttributedString(string: "") }
        }
        let widths = (0 ..< columns).map { widthByColumn[$0] ?? (100.0 / Double(columns)) }
        return ParsedTable(range: NSRange(location: rangeStart, length: rangeEnd - rangeStart),
                           rows: rows, columns: columns, cells: grid, columnWidths: widths)
    }

    /// Find the caret's table, apply `transform` to a mutable grid (returning the new
    /// caret cell, or nil to cancel — e.g. deleting the last row), then rebuild and
    /// replace the table in one undoable edit.
    private func modifyCurrentTable(_ transform: (inout [[NSAttributedString]], Int, Int) -> (Int, Int)?) {
        guard let tv = formattingTextView(), let storage = tv.textStorage else { return }
        let caret = min(tv.selectedRange().location, max(0, storage.length))
        guard let block = tableBlock(atCharacterIndex: caret),
              let parsed = parseTable(containing: block.table) else { return }
        let caretRow = min(block.startingRow, parsed.rows - 1)
        let caretColumn = min(block.startingColumn, parsed.columns - 1)
        var grid = parsed.cells
        guard let target = transform(&grid, caretRow, caretColumn) else { return }
        // Preserve column widths on row edits (column count unchanged); reset to equal
        // when columns were added or removed.
        let newColumns = grid.first?.count ?? 0
        let widths = newColumns == parsed.columns ? parsed.columnWidths : nil
        let rebuilt = rebuildTableAttributed(grid: grid, columnWidths: widths)
        withUndo("Edit Table") {
            storage.replaceCharacters(in: parsed.range, with: rebuilt)
            let offset = parsed.range.location + cellStartOffset(row: target.0, column: target.1, grid: grid)
            tv.setSelectedRange(NSRange(location: min(offset, (storage.string as NSString).length), length: 0))
        }
    }

    /// Rebuilds a table's attributed text from a grid, stamping freshly-numbered cell
    /// blocks (so inserted/deleted rows and columns renumber correctly). `columnWidths`
    /// are percentages of the table; nil gives equal columns.
    private func rebuildTableAttributed(grid: [[NSAttributedString]], columnWidths: [Double]?) -> NSAttributedString {
        let columns = grid.first?.count ?? 0
        let table = AttributedStringBuilder.makeTextTable(columns: columns)
        let result = NSMutableAttributedString()
        for (r, row) in grid.enumerated() {
            for (c, content) in row.enumerated() {
                let widthPercent = (columnWidths != nil && c < columnWidths!.count)
                    ? CGFloat(columnWidths![c]) : nil
                let block = AttributedStringBuilder.makeTableBlock(
                    table: table, row: r, column: c, rowSpan: 1, columnSpan: 1, widthPercent: widthPercent)
                result.append(buildCell(content: content, block: block))
            }
        }
        return result
    }

    // MARK: - Table column widths (resize)

    /// The caret's table's column widths as percentages, or nil if not in a table.
    /// Used by the ruler to draw and drag column dividers.
    public func currentTableColumnWidths() -> [Double]? {
        guard let tv = activeTextView,
              let block = tableBlock(atCharacterIndex: tv.selectedRange().location),
              let parsed = parseTable(containing: block.table) else { return nil }
        return parsed.columnWidths
    }

    /// Sets the caret's table's column widths (percentages) and rebuilds it.
    public func setCurrentTableColumnWidths(_ widths: [Double]) {
        guard let tv = formattingTextView(), let storage = tv.textStorage,
              let block = tableBlock(atCharacterIndex: tv.selectedRange().location),
              let parsed = parseTable(containing: block.table),
              widths.count == parsed.columns else { return }
        let caret = tv.selectedRange().location
        let rebuilt = rebuildTableAttributed(grid: parsed.cells, columnWidths: widths)
        withUndo("Resize Column") {
            storage.replaceCharacters(in: parsed.range, with: rebuilt)
            tv.setSelectedRange(NSRange(location: min(caret, (storage.string as NSString).length), length: 0))
        }
    }

    /// Resets the caret's table to equal column widths.
    public func distributeTableColumnsEvenly() {
        guard let block = tableBlock(atCharacterIndex: activeTextView?.selectedRange().location ?? 0),
              let parsed = parseTable(containing: block.table), parsed.columns > 0 else { return }
        setCurrentTableColumnWidths(Array(repeating: 100.0 / Double(parsed.columns), count: parsed.columns))
    }

    // MARK: - Table navigation & selection

    /// Moves the caret `rowDelta` rows within the current table (used for ↑/↓ arrow
    /// keys, which otherwise move by visual line and skip to the wrong cell). Returns
    /// false when not in a table or at the table's top/bottom edge, so the caller
    /// falls back to normal movement (and steps out of the table).
    public func moveCaretInTable(rowDelta: Int) -> Bool {
        guard let tv = activeTextView,
              let block = tableBlock(atCharacterIndex: tv.selectedRange().location),
              let parsed = parseTable(containing: block.table) else { return false }
        let targetRow = block.startingRow + rowDelta
        guard targetRow >= 0, targetRow < parsed.rows else { return false }
        let column = min(block.startingColumn, parsed.columns - 1)
        let offset = parsed.range.location + cellStartOffset(row: targetRow, column: column, grid: parsed.cells)
        revealHeading(atCharacterIndex: offset)   // places the caret (handles a table that spans pages)
        return true
    }

    /// Selects the whole table the caret is in (so it can be deleted/cut/copied like
    /// a single object). Returns false if the caret isn't in a table.
    @discardableResult
    public func selectCurrentTable() -> Bool {
        guard let tv = activeTextView,
              let block = tableBlock(atCharacterIndex: tv.selectedRange().location),
              let parsed = parseTable(containing: block.table) else { return false }
        revealHeading(atCharacterIndex: parsed.range.location)   // focus the table's page
        activeTextView?.setSelectedRange(parsed.range)
        selectionObserver?(self)
        return true
    }

    /// A cell = its content plus a terminating newline, with `block` stamped onto
    /// every run's paragraph style.
    private func buildCell(content: NSAttributedString, block: NSTextTableBlock) -> NSAttributedString {
        let cell = NSMutableAttributedString(attributedString: content)
        let terminatorAttrs: [NSAttributedString.Key: Any] = content.length > 0
            ? content.attributes(at: content.length - 1, effectiveRange: nil)
            : tableCellAttributes(block: block)
        cell.append(NSAttributedString(string: "\n", attributes: terminatorAttrs))
        cell.enumerateAttribute(.paragraphStyle, in: NSRange(location: 0, length: cell.length), options: []) { value, range, _ in
            let ps = (value as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle ?? NSMutableParagraphStyle()
            ps.textBlocks = [block]
            cell.addAttribute(.paragraphStyle, value: ps, range: range)
        }
        return cell
    }

    private func cellStartOffset(row: Int, column: Int, grid: [[NSAttributedString]]) -> Int {
        var offset = 0
        for r in grid.indices {
            for c in grid[r].indices {
                if r == row && c == column { return offset }
                offset += grid[r][c].length + 1   // +1 for the cell's terminating newline
            }
        }
        return offset
    }

    // MARK: - Style table editing (used by the inspector / style menu)

    public func currentStyleRole() -> String? {
        guard let tv = activeTextView, let storage = tv.textStorage, storage.length > 0 else {
            return activeTextView?.typingAttributes[.lucerneStyleRole] as? String
        }
        let loc = min(tv.selectedRange().location, storage.length - 1)
        return storage.attribute(.lucerneStyleRole, at: loc, effectiveRange: nil) as? String
    }

    /// Attributes for toolbar sync. With a real selection, read the run at its start;
    /// with a collapsed caret, use the typing attributes — that's the format the next
    /// typed character will take, so a bold/italic/etc. toggle made with no selection
    /// is reflected on the toolbar instead of snapping back to the character behind.
    public func currentAttributes() -> [NSAttributedString.Key: Any] {
        guard let tv = activeTextView else { return [:] }
        if tv.selectedRange().length == 0 { return tv.typingAttributes }
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

    /// Contextual help text for the status bar; nil means "no transient hint, show
    /// the default status". Driven by image hover (and could be extended).
    public var onStatusHint: ((String?) -> Void)?

    /// Called when the heading outline may have changed (drives the navigator).
    public var outlineObserver: (() -> Void)?

    /// Used to resolve the {title} token in headers/footers.
    public var documentTitle: String = ""

    /// Number of laid-out pages (for the status bar).
    public var pageCount: Int { pages.count }

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

    // MARK: - Page numbers (shared primitive) and headers/footers

    /// The 1-based page number a character is laid out on.
    public func pageNumber(forCharacterAt index: Int) -> Int {
        guard index >= 0, index < textStorage.length else { return 1 }
        let glyph = layoutManager.glyphIndexForCharacter(at: index)
        guard let container = layoutManager.textContainer(forGlyphAt: glyph, effectiveRange: nil),
              let page = pages.firstIndex(where: { $0.container === container }) else { return 1 }
        return page + 1
    }

    /// Sets the running header/footer (and where page numbering starts) and redraws —
    /// no reflow, they live in the margins. `pageNumberStart` is the 1-based physical
    /// page that shows page number 1; earlier pages are unnumbered.
    public func updatePageFurniture(header: PageFurniture?, footer: PageFurniture?, pageNumberStart: Int?) {
        model.header = header
        model.footer = footer
        model.pageNumberStart = pageNumberStart
        updateFurniture()
        document?.editorDidChange()
    }

    /// Re-resolve and redraw headers/footers without marking the document dirty
    /// (e.g. after the document title becomes known).
    public func refreshFurniture() { updateFurniture() }

    private func updateFurniture() {
        let date = EditorController.dateFormatter.string(from: Date())
        let header = model.header ?? PageFurniture()
        let footer = model.footer ?? PageFurniture()
        // Page numbering starts at 1 on physical page `start`; earlier pages are
        // unnumbered, and the total shown by {pages} counts only numbered pages.
        let start = max(1, model.pageNumberStart ?? 1)
        let numberedCount = max(0, pages.count - (start - 1))
        for (index, page) in pages.enumerated() {
            let displayed: Int? = (index + 1) >= start ? (index + 1) - (start - 1) : nil
            let view = page.pageView
            view.headerLeft = resolve(header.left, page: displayed, of: numberedCount, date: date)
            view.headerCenter = resolve(header.center, page: displayed, of: numberedCount, date: date)
            view.headerRight = resolve(header.right, page: displayed, of: numberedCount, date: date)
            view.footerLeft = resolve(footer.left, page: displayed, of: numberedCount, date: date)
            view.footerCenter = resolve(footer.center, page: displayed, of: numberedCount, date: date)
            view.footerRight = resolve(footer.right, page: displayed, of: numberedCount, date: date)
        }
    }

    /// Substitutes the furniture tokens. `page` is nil on an unnumbered page (before
    /// the numbering start): a zone that references a page number is then blanked so
    /// you don't get "Page  of 3", while date/title-only zones still render.
    private func resolve(_ template: String, page: Int?, of count: Int, date: String) -> String {
        guard !template.isEmpty else { return "" }
        if page == nil, template.contains("{page}") || template.contains("{pages}") { return "" }
        return template
            .replacingOccurrences(of: "{page}", with: page.map { "\($0)" } ?? "")
            .replacingOccurrences(of: "{pages}", with: "\(count)")
            .replacingOccurrences(of: "{date}", with: date)
            .replacingOccurrences(of: "{title}", with: documentTitle)
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .long
        f.timeStyle = .none
        return f
    }()

    // MARK: - Heading outline (navigator)

    public struct HeadingItem: Equatable {
        public let title: String
        public let characterIndex: Int
        public let level: Int
    }

    /// The document's headings (paragraphs whose style maps to markdown h1/h2/h3),
    /// in order, for the navigator.
    public func headingOutline() -> [HeadingItem] {
        guard textStorage.length > 0 else { return [] }
        var items: [HeadingItem] = []
        let ns = textStorage.string as NSString
        var location = 0
        while location < ns.length {
            var start = 0, end = 0, contentsEnd = 0
            ns.getParagraphStart(&start, end: &end, contentsEnd: &contentsEnd,
                                 for: NSRange(location: location, length: 0))
            if let role = textStorage.attribute(.lucerneStyleRole, at: start, effectiveRange: nil) as? String,
               let level = headingLevel(for: role) {
                let title = ns.substring(with: NSRange(location: start, length: contentsEnd - start))
                    .trimmingCharacters(in: .whitespaces)
                if !title.isEmpty {
                    items.append(HeadingItem(title: title, characterIndex: start, level: level))
                }
            }
            if end == location { break }
            location = end
        }
        return items
    }

    private func headingLevel(for role: String) -> Int? {
        switch model.styles[role]?.markdown {
        case "h1": return 1
        case "h2": return 2
        case "h3": return 3
        default: return nil
        }
    }

    // MARK: - Table of contents

    private static let tocRole = "toc"

    /// Inserts (or, if one already exists, replaces) a table of contents at the top
    /// of the document: one entry per heading, with the page number right-aligned at
    /// the margin. Page numbers are converged by re-laying out a couple of times.
    public func insertOrUpdateTableOfContents() {
        guard let tv = formattingTextView(), let storage = tv.textStorage else { return }
        ensureTOCStyle()
        withUndo("Table of Contents") {
            removeTOCParagraphs(in: storage)
            let headings = headingOutline()             // clean indices (ToC removed)
            guard !headings.isEmpty else { return }     // nothing to list (old ToC cleared)
            var pages = headings.map { pageNumber(forCharacterAt: $0.characterIndex) }
            for _ in 0 ..< 3 {
                removeTOCParagraphs(in: storage)
                let toc = buildTOCAttributed(headings: headings, pages: pages)
                storage.insert(toc, at: 0)
                relayoutText(syncImages: false)         // settle pagination
                let shifted = headings.map { pageNumber(forCharacterAt: $0.characterIndex + toc.length) }
                if shifted == pages { break }
                pages = shifted
            }
        }
    }

    private func ensureTOCStyle() {
        guard model.styles[EditorController.tocRole] == nil else { return }
        let body = model.resolvedStyle(for: LucerneDocumentModel.defaultStyleRole)
        model.styles[EditorController.tocRole] = ParagraphStyleDef(
            name: "Contents Entry", font: body.font, size: body.size,
            spaceAfter: 2, markdown: "p")
    }

    private func removeTOCParagraphs(in storage: NSTextStorage) {
        let ns = storage.string as NSString
        var ranges: [NSRange] = []
        var location = 0
        while location < ns.length {
            var start = 0, end = 0, contentsEnd = 0
            ns.getParagraphStart(&start, end: &end, contentsEnd: &contentsEnd,
                                 for: NSRange(location: location, length: 0))
            if (storage.attribute(.lucerneStyleRole, at: start, effectiveRange: nil) as? String) == EditorController.tocRole {
                ranges.append(NSRange(location: start, length: end - start))
            }
            if end == location { break }
            location = end
        }
        for range in ranges.reversed() { storage.deleteCharacters(in: range) }
    }

    private func buildTOCAttributed(headings: [HeadingItem], pages: [Int]) -> NSAttributedString {
        let font = tocMeasuringFont()
        var tocModel = model
        tocModel.objects = []
        tocModel.body = zip(headings, pages).map { heading, page in
            let leftIndent = Double((heading.level - 1) * 18)
            // Left-aligned line with a measured dotted leader (no tab — Cocoa tabs
            // have no leader fill), so the page number lands at the right margin.
            return Paragraph(id: IDGenerator.next("toc"),
                             style: EditorController.tocRole,
                             indent: IndentModel(left: leftIndent),
                             runs: [Run(text: tocLine(title: heading.title, page: page,
                                                      leftIndent: CGFloat(leftIndent), font: font))])
        }
        let attributed = NSMutableAttributedString(
            attributedString: AttributedStringBuilder.attributedString(for: tocModel))
        // Trailing paragraph break so the body stays its own paragraph after the ToC.
        let separator = AttributedStringBuilder.typingAttributes(
            role: EditorController.tocRole, in: tocModel, paragraphID: IDGenerator.next("toc"))
        attributed.append(NSAttributedString(string: "\n", attributes: separator))
        return attributed
    }

    /// The font the ToC entries render in, so leader measurement matches layout.
    private func tocMeasuringFont() -> NSFont {
        let style = model.resolvedStyle(for: EditorController.tocRole)
        return FontResolver.font(family: style.font, size: CGFloat(style.size ?? 12),
                                 bold: style.bold ?? false, italic: style.italic ?? false)
    }

    /// "Title …… 12" — title, a dotted leader, then the page number near the right
    /// margin. Falls back to two spaces when there's no room (e.g. a long title).
    private func tocLine(title: String, page: Int, leftIndent: CGFloat, font: NSFont) -> String {
        let available = metrics.contentSize.width - leftIndent
        let dots = EditorController.leaderDotCount(title: title, page: "\(page)",
                                                   availableWidth: available, font: font)
        guard dots > 0 else { return "\(title)  \(page)" }
        return "\(title) " + String(repeating: ".", count: dots) + " \(page)"
    }

    /// Pure, testable: how many '.' fit between `title` and a right-aligned `page`
    /// number on a line `availableWidth` points wide, leaving a space each side of
    /// the dots. Returns 0 when the title + number already fill (or overflow) the line.
    static func leaderDotCount(title: String, page: String,
                               availableWidth: CGFloat, font: NSFont) -> Int {
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        let titleW = (title as NSString).size(withAttributes: attrs).width
        let pageW = (page as NSString).size(withAttributes: attrs).width
        let dotW = ("." as NSString).size(withAttributes: attrs).width
        let spaceW = (" " as NSString).size(withAttributes: attrs).width
        guard dotW > 0 else { return 0 }
        let room = availableWidth - titleW - pageW - 2 * spaceW
        guard room > dotW else { return 0 }
        return max(0, Int(room / dotW))
    }

    /// Scrolls the given character into view and places the caret there.
    public func revealHeading(atCharacterIndex index: Int) {
        guard index >= 0, index < textStorage.length else { return }
        let glyph = layoutManager.glyphIndexForCharacter(at: index)
        guard let container = layoutManager.textContainer(forGlyphAt: glyph, effectiveRange: nil),
              let page = pages.first(where: { $0.container === container }) else { return }
        let lineRect = layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
        // container coords → text view → page view → canvas
        let inTextView = lineRect.offsetBy(dx: page.textView.frame.minX, dy: page.textView.frame.minY)
        let inCanvas = page.pageView.convert(inTextView, to: canvasView)
        canvasView.scrollToVisible(inCanvas.insetBy(dx: 0, dy: -40))
        window?.makeFirstResponder(page.textView)
        page.textView.setSelectedRange(NSRange(location: index, length: 0))
    }

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

    /// Lossy interchange export. Text, fonts, color, and paragraph formatting
    /// survive; free-placed images are dropped (RTF can't express page-anchored
    /// frames — plan §4). The pictures live on in the .luce package and the PDF.
    public func makeRTFData() -> Data {
        let range = NSRange(location: 0, length: textStorage.length)
        return textStorage.rtf(from: range, documentAttributes: [:]) ?? Data()
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

// MARK: - NSTextViewDelegate (selection tracking for toolbar/ruler sync)

extension EditorController: NSTextViewDelegate {
    public func textViewDidChangeSelection(_ notification: Notification) {
        guard let textView = notification.object as? PageTextView else { return }
        activeSelectionChanged(in: textView)
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

    public func floatingImageView(_ view: FloatingImageView, beganDrag isMove: Bool) {
        if let object = model.objects.first(where: { $0.id == view.objectID }) {
            dragStartPlacement = (object.page, object.frame)
        }
        movingImageID = isMove ? view.objectID : nil
        // Bring the image's page to the front so the image stays visible while it's
        // dragged over neighbouring pages (the image itself is not re-parented until
        // the drag commits, which keeps mouse tracking intact).
        if isMove, let pageView = view.superview as? PageContainerView {
            canvasView.addSubview(pageView)
        }
    }

    public func floatingImageView(_ view: FloatingImageView, didChangeFrameLive frame: CGRect) {
        guard let index = model.objects.firstIndex(where: { $0.id == view.objectID }) else { return }
        if view.objectID == movingImageID, let pageView = view.superview {
            // Moving: map the view's (page-space) frame through the canvas to find
            // which page it's over now, so text reflows on that page live.
            let canvasFrame = pageView.convert(frame, to: canvasView)
            let target = pageIndex(forCanvasPoint: CGPoint(x: canvasFrame.midX, y: canvasFrame.midY))
            model.objects[index].page = target
            model.objects[index].frame = RectModel(canvasView.convert(canvasFrame, to: pages[target].pageView))
        } else {
            // Resizing within the page: `frame` is already in page coordinates.
            model.objects[index].frame = RectModel(frame)
        }
        relayoutText(syncImages: false)   // paginateAndExclude recomputes wrap from the model
    }

    public func floatingImageView(_ view: FloatingImageView, didCommitFrom oldFrame: CGRect, to newFrame: CGRect) {
        let previous = dragStartPlacement
        dragStartPlacement = nil
        let moving = view.objectID == movingImageID
        movingImageID = nil

        let targetPage: Int
        let targetFrame: RectModel
        if moving, let pageView = view.superview {
            let canvasFrame = pageView.convert(newFrame, to: canvasView)
            targetPage = pageIndex(forCanvasPoint: CGPoint(x: canvasFrame.midX, y: canvasFrame.midY))
            let pageRelative = canvasView.convert(canvasFrame, to: pages[targetPage].pageView)
            targetFrame = RectModel(metrics.clampObjectFrame(pageRelative))
        } else {
            targetPage = model.objects.first(where: { $0.id == view.objectID })?.page ?? 0
            targetFrame = RectModel(metrics.clampObjectFrame(newFrame))
        }
        // applyPlacement → relayout(syncImages:true) re-parents the image into its
        // target page (and restores normal page z-order) via syncImageViews.
        applyPlacement(id: view.objectID, page: targetPage, frame: targetFrame,
                       previous: previous, undoName: moving ? "Move Image" : "Resize Image")
    }

    public func floatingImageViewRequestsDelete(_ view: FloatingImageView) {
        removeObject(id: view.objectID, undoName: "Delete Image")
    }

    /// Sets a placed object's page + frame and re-parents its view into that page
    /// (via syncImageViews). `previous` is the pre-drag placement to restore on undo.
    private func applyPlacement(id: String, page: Int, frame: RectModel,
                                previous: (page: Int?, frame: RectModel?)?, undoName: String) {
        guard let index = model.objects.firstIndex(where: { $0.id == id }) else { return }
        let restore = previous ?? (model.objects[index].page, model.objects[index].frame)
        model.objects[index].page = page
        model.objects[index].frame = frame
        relayoutText(syncImages: true)
        registerObjectUndo(undoName) { controller in
            controller.applyPlacement(id: id, page: restore.page ?? page, frame: restore.frame ?? frame,
                                      previous: (page, frame), undoName: undoName)
        }
        document?.editorDidChange()
    }

    /// The page whose view contains the given canvas-space point, or the vertically
    /// nearest page if the point is in a gap.
    private func pageIndex(forCanvasPoint point: CGPoint) -> Int {
        for (index, page) in pages.enumerated() where page.pageView.frame.contains(point) { return index }
        var best = 0
        var bestDistance = CGFloat.greatestFiniteMagnitude
        for (index, page) in pages.enumerated() {
            let f = page.pageView.frame
            let dy: CGFloat = point.y < f.minY ? f.minY - point.y : (point.y > f.maxY ? point.y - f.maxY : 0)
            if dy < bestDistance { bestDistance = dy; best = index }
        }
        return best
    }

    public func floatingImageView(_ view: FloatingImageView, didHover entered: Bool) {
        onStatusHint?(entered
            ? "Image — drag to move · drag a corner to resize (hold ⇧ for free aspect) · ⌫ to delete"
            : nil)
    }
}
