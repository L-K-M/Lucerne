import LucerneCore
import AppKit
import UniformTypeIdentifiers

// One NSTextView per page. All page text views share a single NSLayoutManager and
// NSTextStorage (constructed by EditorController), which is what makes text flow
// from one page into the next. Constructing the view with an explicit container
// keeps it on the TextKit 1 path (see AGENTS.md ▸ "Why TextKit 1").
public final class PageTextView: NSTextView {

    public weak var editor: EditorController?

    public override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        if ok { editor?.textViewBecameActive(self) }
        return ok
    }

    // A click in the text deselects any selected floating image so the two
    // selection models don't fight.
    public override func mouseDown(with event: NSEvent) {
        editor?.deselectAllImages()
        super.mouseDown(with: event)
    }

    // In a table, ↑/↓ move to the cell above/below in the same column (the default
    // moves by visual line and lands in the wrong cell). Outside a table — or at the
    // table's top/bottom edge — fall through to normal movement.
    public override func moveDown(_ sender: Any?) {
        if editor?.moveCaretInTable(rowDelta: 1) == true { return }
        super.moveDown(sender)
    }

    public override func moveUp(_ sender: Any?) {
        if editor?.moveCaretInTable(rowDelta: -1) == true { return }
        super.moveUp(sender)
    }

    // In a table, Tab / Shift-Tab walk to the next / previous cell in row-major order
    // (the most ingrained table gesture). Outside a table — or at the table's first/last
    // cell — fall through to the normal tab behavior (inserting a tab / shifting focus).
    // Tab / Shift-Tab first walk table cells, then nest / unnest a list item; only
    // outside both do they insert a tab or shift focus.
    public override func insertTab(_ sender: Any?) {
        if editor?.moveCaretInTable(cellDelta: 1) == true { return }
        if editor?.handleListTab(in: self, outdent: false) == true { return }
        super.insertTab(sender)
    }

    public override func insertBacktab(_ sender: Any?) {
        if editor?.moveCaretInTable(cellDelta: -1) == true { return }
        if editor?.handleListTab(in: self, outdent: true) == true { return }
        super.insertBacktab(sender)
    }

    // Markdown block shortcuts: typing a space right after a start-of-line marker
    // ("# ", "## ", "### ", "#### ", "> ") converts the paragraph to the matching
    // paragraph style and swallows the space, instead of inserting a literal one.
    // Anything but a lone space — and this behaviour when the preference is off, or a
    // marker the stylesheet has no style for — types normally. Paste routes through a
    // different path, so it is never affected. See applyMarkdownShortcutOnSpace.
    public override func insertText(_ string: Any, replacementRange: NSRange) {
        if Self.isPlainSpace(string), editor?.applyMarkdownShortcutOnSpace(in: self) == true {
            return
        }
        if replacePageBreakSentinel(string, in: replacementRange) { return }
        super.insertText(string, replacementRange: replacementRange)
    }

    private static func isPlainSpace(_ string: Any) -> Bool {
        if let s = string as? String { return s == " " }
        if let s = string as? NSAttributedString { return s.string == " " }
        return false
    }

    /// Keep the internal layout carrier out of copied text and rich text. Normal
    /// selections still use NSTextView's full pasteboard support.
    public override func copy(_ sender: Any?) {
        guard let storage = textStorage else { return super.copy(sender) }
        let range = selectedRange()
        guard range.length > 0, NSMaxRange(range) <= storage.length else {
            return super.copy(sender)
        }
        let selected = storage.attributedSubstring(from: range)
        let sanitized = AttributedStringReader.removingPageBreakSentinels(from: selected)
        guard sanitized.length != selected.length else { return super.copy(sender) }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(sanitized.string, forType: .string)
        if let rtf = sanitized.rtf(
            from: NSRange(location: 0, length: sanitized.length), documentAttributes: [:]
        ) {
            pasteboard.setData(rtf, forType: .rtf)
        }
    }

    /// A final empty page-break paragraph has an invisible layout carrier. Replace
    /// that carrier as part of the first real insertion so it never remains as a
    /// hidden caret position, while transferring the structural break attributes
    /// to the inserted content in the same edit.
    private func replacePageBreakSentinel(
        _ value: Any, in requestedRange: NSRange
    ) -> Bool {
        let inserted = (value as? NSAttributedString)?.string ?? (value as? String) ?? ""
        guard !inserted.isEmpty, let storage = textStorage, storage.length > 0 else {
            return false
        }
        // A pure paragraph-separator insertion is a Return split, not content
        // replacing the carrier: let it insert normally so the split logic can
        // decide which side of the break keeps it.
        if inserted.allSatisfy({ $0 == "\n" || $0 == "\r" }) { return false }

        let editRange = requestedRange.location == NSNotFound ? selectedRange() : requestedRange
        guard editRange.location <= storage.length else { return false }

        var carrier: NSRange?
        storage.enumerateAttribute(
            .lucernePageBreakSentinel,
            in: NSRange(location: 0, length: storage.length), options: []
        ) { marker, range, stop in
            guard (marker as? Bool) == true else { return }
            let touches = editRange.length > 0
                ? NSIntersectionRange(editRange, range).length > 0
                : editRange.location >= range.location && editRange.location <= NSMaxRange(range)
            if touches {
                carrier = range
                stop.pointee = true
            }
        }
        guard let carrier else { return false }

        let carrierAttributes = storage.attributes(at: carrier.location, effectiveRange: nil)
        let structuralKeys: [NSAttributedString.Key] = [
            .lucernePageBreakBefore, .lucernePageBreakMarker,
            .lucerneStyleRole, .lucerneParagraphID, .lucerneList,
        ]
        var preparedTyping = typingAttributes
        for key in structuralKeys {
            if let structuralValue = carrierAttributes[key] {
                preparedTyping[key] = structuralValue
            } else {
                preparedTyping.removeValue(forKey: key)
            }
        }
        if preparedTyping[.paragraphStyle] == nil,
           let paragraphStyle = carrierAttributes[.paragraphStyle] {
            preparedTyping[.paragraphStyle] = paragraphStyle
        }
        preparedTyping.removeValue(forKey: .lucernePageBreakSentinel)

        let range = NSUnionRange(editRange, carrier)
        let prepared: NSMutableAttributedString
        let isAttributedInsertion = value is NSAttributedString
        if let attributed = value as? NSAttributedString {
            prepared = NSMutableAttributedString(attributedString: attributed)
            prepared.removeAttribute(.lucernePageBreakSentinel,
                                     range: NSRange(location: 0, length: prepared.length))
        } else {
            prepared = NSMutableAttributedString(string: inserted, attributes: preparedTyping)
        }

        let preparedString = prepared.string as NSString
        var location = 0
        var paragraphIndex = 0
        while location < preparedString.length {
            var start = 0, end = 0, contentsEnd = 0
            preparedString.getParagraphStart(&start, end: &end, contentsEnd: &contentsEnd,
                                             for: NSRange(location: location, length: 0))
            let paragraphRange = NSRange(location: start, length: end - start)
            if paragraphIndex == 0 {
                for key in structuralKeys {
                    if let structuralValue = carrierAttributes[key] {
                        prepared.addAttribute(key, value: structuralValue, range: paragraphRange)
                    } else {
                        prepared.removeAttribute(key, range: paragraphRange)
                    }
                }
                if let paragraphStyle = carrierAttributes[.paragraphStyle] {
                    prepared.addAttribute(.paragraphStyle, value: paragraphStyle, range: paragraphRange)
                }
            } else {
                prepared.addAttribute(.lucerneParagraphID, value: IDGenerator.next("p"),
                                      range: paragraphRange)
                if !isAttributedInsertion {
                    prepared.removeAttribute(.lucernePageBreakBefore, range: paragraphRange)
                    prepared.removeAttribute(.lucernePageBreakMarker, range: paragraphRange)
                }
                if prepared.attribute(.lucerneStyleRole, at: start, effectiveRange: nil) == nil,
                   let role = carrierAttributes[.lucerneStyleRole] {
                    prepared.addAttribute(.lucerneStyleRole, value: role, range: paragraphRange)
                }
                if prepared.attribute(.paragraphStyle, at: start, effectiveRange: nil) == nil,
                   let paragraphStyle = carrierAttributes[.paragraphStyle] {
                    prepared.addAttribute(.paragraphStyle, value: paragraphStyle, range: paragraphRange)
                }
            }
            if end == location { break }
            location = end
            paragraphIndex += 1
        }

        guard shouldChangeText(in: range, replacementString: inserted) else { return true }
        storage.replaceCharacters(in: range, with: prepared)
        var continuationAttributes = prepared.length > 0
            ? prepared.attributes(at: prepared.length - 1, effectiveRange: nil)
            : preparedTyping
        if let last = prepared.string.utf16.last, last == 0x0A || last == 0x0D {
            continuationAttributes[.lucerneParagraphID] = IDGenerator.next("p")
            continuationAttributes.removeValue(forKey: .lucernePageBreakBefore)
            continuationAttributes.removeValue(forKey: .lucernePageBreakMarker)
            continuationAttributes.removeValue(forKey: .lucernePageBreakSentinel)
            let terminator = NSRange(location: range.location + prepared.length - 1, length: 1)
            if let id = continuationAttributes[.lucerneParagraphID] {
                storage.addAttribute(.lucerneTrailingParagraphID, value: id, range: terminator)
            }
            if let role = continuationAttributes[.lucerneStyleRole] {
                storage.addAttribute(.lucerneTrailingStyleRole, value: role, range: terminator)
            }
            if let list = continuationAttributes[.lucerneList] {
                storage.addAttribute(.lucerneTrailingList, value: list, range: terminator)
            } else {
                storage.removeAttribute(.lucerneTrailingList, range: terminator)
            }
        }
        typingAttributes = continuationAttributes
        setSelectedRange(NSRange(location: range.location + prepared.length, length: 0))
        didChangeText()
        return true
    }

    // Deleting the last carrier of a forced-break final paragraph must not lose
    // the break: the paragraph still exists, it is only empty. Capture its
    // structural attributes before the edit and restore the invisible sentinel
    // carrier afterwards, so the trailing empty paragraph stays marked.
    public override func deleteBackward(_ sender: Any?) {
        let carrier = captureFinalBreakCarrier(deletingForward: false)
        super.deleteBackward(sender)
        restoreFinalBreakCarrier(carrier)
    }

    public override func deleteForward(_ sender: Any?) {
        let carrier = captureFinalBreakCarrier(deletingForward: true)
        super.deleteForward(sender)
        restoreFinalBreakCarrier(carrier)
    }

    /// The final paragraph's attributes when the pending deletion reaches the end
    /// of a break-marked final paragraph — nil in every other case.
    private func captureFinalBreakCarrier(
        deletingForward forward: Bool
    ) -> [NSAttributedString.Key: Any]? {
        guard let storage = textStorage, storage.length > 0 else { return nil }
        let ns = storage.string as NSString
        var range = selectedRange()
        if range.length == 0 {
            let location = forward ? range.location : range.location - 1
            guard location >= 0, location < ns.length else { return nil }
            range = NSRange(location: location, length: 1)
        }
        guard NSMaxRange(range) >= ns.length else { return nil }
        let last = ns.character(at: ns.length - 1)
        guard last != 0x0A, last != 0x0D else { return nil }
        var start = 0
        ns.getParagraphStart(&start, end: nil, contentsEnd: nil,
                             for: NSRange(location: ns.length - 1, length: 0))
        var marked = false
        let paragraph = NSRange(location: start, length: ns.length - start)
        storage.enumerateAttribute(.lucernePageBreakMarker, in: paragraph,
                                   options: []) { value, _, stop in
            if value is String { marked = true; stop.pointee = true }
        }
        if !marked {
            storage.enumerateAttribute(.lucernePageBreakBefore, in: paragraph,
                                       options: []) { value, _, stop in
                if (value as? Bool) == true { marked = true; stop.pointee = true }
            }
        }
        return marked ? storage.attributes(at: start, effectiveRange: nil) : nil
    }

    /// Re-add the sentinel carrier when the deletion emptied a marked final
    /// paragraph. The caret goes before the sentinel so the next Backspace removes
    /// the separator — and the paragraph — instead of looping on the carrier.
    private func restoreFinalBreakCarrier(_ attributes: [NSAttributedString.Key: Any]?) {
        guard let attributes, let storage = textStorage, storage.length > 0 else { return }
        let last = (storage.string as NSString).character(at: storage.length - 1)
        guard last == 0x0A || last == 0x0D else { return }
        var carrier = attributes
        carrier[.lucernePageBreakSentinel] = true
        carrier[.lucernePageBreakBefore] = true
        for key in [NSAttributedString.Key.lucerneTrailingParagraphID,
                    .lucerneTrailingStyleRole, .lucerneTrailingParagraphStyle,
                    .lucerneTrailingList] {
            carrier.removeValue(forKey: key)
        }
        let insertion = NSRange(location: storage.length, length: 0)
        guard shouldChangeText(in: insertion,
                               replacementString: AttributedStringBuilder.pageBreakSentinel) else { return }
        storage.insert(NSAttributedString(string: AttributedStringBuilder.pageBreakSentinel,
                                          attributes: carrier),
                       at: storage.length)
        setSelectedRange(NSRange(location: storage.length - 1, length: 0))
        didChangeText()
    }

    // Return behaviour, in priority order:
    //   • On an empty list item — outdent it, or drop the list (no blank line inserted).
    //   • In a non-empty list item — continue the list on the next line.
    //   • At the end of a heading — start the following paragraph in Body ("next style").
    // Otherwise it's an ordinary paragraph break. (Shift-Return routes to
    // insertLineBreak — a soft break within the paragraph — and is left alone.) Each
    // decision is taken before the newline is inserted and applied to the new paragraph
    // after, since only then does it exist.
    public override func insertNewline(_ sender: Any?) {
        if editor?.handleEmptyListItemNewline(in: self) == true { return }
        let continuedList = editor?.listItemContinuedByReturn(in: self)
        let demote = continuedList == nil
            && (editor?.caretIsAtHeadingParagraphEnd(in: self) ?? false)
        super.insertNewline(sender)
        editor?.didInsertParagraphBreak(in: self, continuedList: continuedList)
        if continuedList != nil { editor?.didInsertListContinuationNewline(in: self) }
        else if demote { editor?.startBodyParagraphAfterHeadingNewline(in: self) }
    }

    // MARK: - Context menu

    // Augment the standard editing menu (Cut/Copy/Paste/…) with Lucerne's formatting
    // and insert commands. They target nil so they route up the responder chain to the
    // DocumentWindowController, exactly like the main-menu items.
    public override func menu(for event: NSEvent) -> NSMenu? {
        let menu = super.menu(for: event) ?? NSMenu()
        menu.addItem(.separator())

        menu.addItem(item("Bold", #selector(DocumentWindowController.lucerneToggleBold(_:))))
        menu.addItem(item("Italic", #selector(DocumentWindowController.lucerneToggleItalic(_:))))
        menu.addItem(item("Underline", #selector(DocumentWindowController.lucerneToggleUnderline(_:))))

        let styleItem = NSMenuItem(title: "Paragraph Style", action: nil, keyEquivalent: "")
        let styleMenu = NSMenu(title: "Paragraph Style")
        // The document's own stylesheet, in its list order — not a hardcoded set.
        let defs = editor?.model.styles ?? DefaultDocuments.defaultStyles()
        for role in LucerneDocumentModel.orderedStyleRoles(in: defs) {
            styleMenu.addItem(item(defs[role]?.name ?? role,
                                   #selector(DocumentWindowController.lucerneApplyStyle(_:)), represented: role))
        }
        styleItem.submenu = styleMenu
        menu.addItem(styleItem)

        let listItem = NSMenuItem(title: "List", action: nil, keyEquivalent: "")
        let listMenu = NSMenu(title: "List")
        listMenu.addItem(item("Bulleted List", #selector(DocumentWindowController.lucerneToggleBulletedList(_:))))
        listMenu.addItem(item("Numbered List", #selector(DocumentWindowController.lucerneToggleNumberedList(_:))))
        listItem.submenu = listMenu
        menu.addItem(listItem)

        menu.addItem(.separator())
        menu.addItem(item("Insert Image…", #selector(DocumentWindowController.lucerneInsertImage(_:))))
        menu.addItem(item("Insert Table…", #selector(DocumentWindowController.lucerneInsertTable(_:))))
        appendTableCommands(to: menu)
        return menu
    }

    private func item(_ title: String, _ action: Selector, represented: Any? = nil) -> NSMenuItem {
        let menuItem = NSMenuItem(title: title, action: action, keyEquivalent: "")
        menuItem.representedObject = represented
        return menuItem
    }

    /// When the caret is inside a table cell, add the table-editing commands.
    private func appendTableCommands(to menu: NSMenu) {
        guard editor?.selectionIsInTableCell == true else { return }
        menu.addItem(.separator())
        menu.addItem(item("Select Table", #selector(DocumentWindowController.lucerneSelectTable(_:))))
        menu.addItem(item("Insert Row Above", #selector(DocumentWindowController.lucerneInsertRowAbove(_:))))
        menu.addItem(item("Insert Row Below", #selector(DocumentWindowController.lucerneInsertRowBelow(_:))))
        menu.addItem(item("Insert Column Before", #selector(DocumentWindowController.lucerneInsertColumnBefore(_:))))
        menu.addItem(item("Insert Column After", #selector(DocumentWindowController.lucerneInsertColumnAfter(_:))))
        menu.addItem(item("Merge Cells", #selector(DocumentWindowController.lucerneMergeCells(_:))))
        menu.addItem(item("Delete Row", #selector(DocumentWindowController.lucerneDeleteRow(_:))))
        menu.addItem(item("Delete Column", #selector(DocumentWindowController.lucerneDeleteColumn(_:))))
        menu.addItem(item("Distribute Columns Evenly", #selector(DocumentWindowController.lucerneDistributeColumns(_:))))
    }

    // MARK: - Image drag & drop

    // Dropping an image (a file or image data) creates a free-placed floating image
    // at the drop point, instead of NSTextView inserting the path/attachment into
    // the text. Non-image drags fall through to the normal text behavior.

    public override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        Self.hasImage(sender.draggingPasteboard) ? .copy : super.draggingEntered(sender)
    }

    public override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        Self.hasImage(sender.draggingPasteboard) ? .copy : super.draggingUpdated(sender)
    }

    public override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        Self.hasImage(sender.draggingPasteboard) ? true : super.prepareForDragOperation(sender)
    }

    public override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let (data, name) = Self.imagePayload(from: sender.draggingPasteboard) else {
            return super.performDragOperation(sender)
        }
        let pageView = superview as? PageContainerView
        let pagePoint = (pageView ?? self).convert(sender.draggingLocation, from: nil)
        editor?.insertImage(data: data, suggestedName: name,
                            onPage: pageView?.pageIndex ?? 0, centeredAt: pagePoint)
        return true
    }

    // MARK: - Paste image

    // An image on the pasteboard (⌘V after copying from Preview, a browser, etc.)
    // inserts as a free-placed floating image on this view's page — reusing the exact
    // drop-path insertion — instead of NSTextView beeping or pasting a text
    // attachment. Anything else falls through to the normal paste.
    public override func paste(_ sender: Any?) {
        guard let (data, name) = Self.imagePayload(from: .general) else {
            super.paste(sender)
            return
        }
        let pageView = superview as? PageContainerView
        editor?.insertImage(data: data, suggestedName: name,
                            onPage: pageView?.pageIndex ?? 0,
                            centeredAt: imagePasteCenter(inPage: pageView))
    }

    /// Rich text from other applications can carry attributes Lucerne cannot save.
    /// Normalize it before insertion so the visible result is already canonical;
    /// plain text remains on AppKit's normal Paste and Match Style path.
    public override func readSelection(from pasteboard: NSPasteboard,
                                       type: NSPasteboard.PasteboardType) -> Bool {
        guard PasteNormalizer.supports(type),
              let source = PasteNormalizer.read(from: pasteboard, type: type),
              let editor else {
            return super.readSelection(from: pasteboard, type: type)
        }
        let selection = selectedRange()
        let destination: [NSAttributedString.Key: Any]
        if let storage = textStorage,
           let carrier = PasteNormalizer.pageBreakSentinelRange(touching: selection,
                                                                in: storage) {
            // Pasting into the trailing empty break paragraph takes its structure
            // from the sentinel carrier itself, not from transient typing state.
            destination = storage.attributes(at: carrier.location, effectiveRange: nil)
        } else if selection.length > 0, let storage = textStorage,
           selection.location < storage.length {
            destination = storage.attributes(at: selection.location, effectiveRange: nil)
        } else {
            destination = typingAttributes
        }
        let normalized = PasteNormalizer.normalize(
            source, destination: destination, model: editor.model)
        guard normalized.length > 0 else { return false }
        guard let storage = textStorage else { return false }
        let replacement = PasteNormalizer.replacement(
            normalized, for: selection, in: storage)
        guard shouldChangeText(in: replacement.range,
                               replacementString: replacement.content.string) else { return false }
        storage.replaceCharacters(in: replacement.range, with: replacement.content)
        setSelectedRange(NSRange(location: replacement.caretLocation, length: 0))
        didChangeText()
        return true
    }

    /// A page-relative point to centre a pasted image on: the caret's line rect when
    /// the layout manager reports a usable one, otherwise the centre of the visible
    /// area of this page (so the image lands where the reader is looking).
    private func imagePasteCenter(inPage pageView: PageContainerView?) -> CGPoint {
        let target: NSView = pageView ?? self
        if let layoutManager, let textContainer {
            let glyphRange = layoutManager.glyphRange(forCharacterRange: selectedRange(),
                                                      actualCharacterRange: nil)
            var caret = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
            if caret.width > 0 || caret.height > 0 {
                caret.origin.x += textContainerOrigin.x
                caret.origin.y += textContainerOrigin.y
                return target.convert(CGPoint(x: caret.midX, y: caret.midY), from: self)
            }
        }
        let visible = visibleRect
        return target.convert(CGPoint(x: visible.midX, y: visible.midY), from: self)
    }

    private static func hasImage(_ pasteboard: NSPasteboard) -> Bool {
        let urlOptions: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true,
            .urlReadingContentsConformToTypes: [UTType.image.identifier]
        ]
        if pasteboard.canReadObject(forClasses: [NSURL.self], options: urlOptions) { return true }
        return pasteboard.canReadObject(forClasses: [NSImage.self], options: nil)
    }

    /// Returns (original bytes, suggested filename) for a dropped image, preferring
    /// the original file bytes (lossless) over a re-encode.
    private static func imagePayload(from pasteboard: NSPasteboard) -> (Data, String)? {
        let urlOptions: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true,
            .urlReadingContentsConformToTypes: [UTType.image.identifier]
        ]
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: urlOptions) as? [URL],
           let url = urls.first, let data = try? Data(contentsOf: url) {
            return (data, url.lastPathComponent)
        }
        if let image = NSImage(pasteboard: pasteboard), let data = image.pngData() {
            return (data, "image.png")
        }
        return nil
    }
}
