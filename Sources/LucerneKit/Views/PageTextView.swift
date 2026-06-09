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
        let defs = DefaultDocuments.defaultStyles()
        for role in DefaultDocuments.styleRoleOrder {
            styleMenu.addItem(item(defs[role]?.name ?? role,
                                   #selector(DocumentWindowController.lucerneApplyStyle(_:)), represented: role))
        }
        styleItem.submenu = styleMenu
        menu.addItem(styleItem)

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
