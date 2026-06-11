import AppKit

/// One row of a try-on picker, floating palette, or the Style Library window: a
/// stable identity (a font family name or a paragraph-style key) plus the title
/// shown for it. `dimmed` rows draw in secondary gray (the palette's library
/// section); a `separator` row is an unselectable section caption.
struct PickerItem: Equatable {
    let id: String
    let title: String
    var dimmed: Bool = false
    var isSeparator: Bool = false

    static func separator(_ title: String) -> PickerItem {
        PickerItem(id: "separator:\(title)", title: title, dimmed: true, isSeparator: true)
    }
}

/// The shared specimen-list UI used by the attached try-on popovers, the floating
/// palettes, and the Style Library window: a filter field over a one-column table
/// whose rows draw in a per-item specimen font (the list is the specimen book),
/// with a hint line underneath. Moving the selection — clicks, ↑↓ from the filter
/// field, or filtering itself — reports through `onPick` without dismissing
/// anything; Return and Esc report through `onCommit`/`onCancel`.
///
/// Optional extras (off by default so the popovers stay lean):
///   • `onEdit` — rows grow a small pencil well (shown on hover), and a
///     double-click edits instead of committing (STYLES.md §6.1).
///   • `allowsReordering` + `onReorder` — rows can be dragged to reorder (the
///     Style Library window; disabled while a filter is active).
final class PickerListView: NSView, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {

    /// Selection landed on an item by user action (click, arrows, filter).
    var onPick: ((PickerItem) -> Void)?
    var onCommit: (() -> Void)?
    var onCancel: (() -> Void)?
    /// When set, rows show an edit well and double-click means "edit".
    var onEdit: ((PickerItem) -> Void)?
    /// Drag-to-reorder (only meaningful with no separators and no filter).
    var allowsReordering = false
    /// The full item list in its new order, after a drag.
    var onReorder: (([PickerItem]) -> Void)?
    /// Resolves the font a row is drawn in — lazily, per visible row, so listing
    /// every installed family doesn't load every installed font up front.
    var specimenFont: (PickerItem) -> NSFont = { _ in .systemFont(ofSize: 13) }

    private(set) var items: [PickerItem] = []
    private var filtered: [PickerItem] = []
    private var suppressPick = false

    private let searchField = NSSearchField()
    private let tableView = KeyCommandTableView()
    private let scroll = NSScrollView()
    private let hintLabel: NSTextField

    private static let reorderType = NSPasteboard.PasteboardType("ch.lkmc.lucerne.picker-row")

    init(hint: String) {
        hintLabel = NSTextField(labelWithString: hint)
        super.init(frame: NSRect(x: 0, y: 0, width: 280, height: 400))

        searchField.placeholderString = "Filter"
        searchField.font = NSFont.systemFont(ofSize: 12)
        searchField.delegate = self
        searchField.focusRingType = .none

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("item"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.rowHeight = 24
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.doubleAction = #selector(rowDoubleClicked)
        tableView.onCommit = { [weak self] in self?.onCommit?() }
        tableView.onCancel = { [weak self] in self?.onCancel?() }
        tableView.registerForDraggedTypes([Self.reorderType])

        scroll.documentView = tableView
        scroll.hasVerticalScroller = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = true
        scroll.backgroundColor = .white

        hintLabel.font = NSFont.systemFont(ofSize: 10)
        hintLabel.textColor = NSColor(calibratedWhite: 0.45, alpha: 1)
        hintLabel.alignment = .center
        hintLabel.lineBreakMode = .byTruncatingTail

        for view in [searchField, scroll, hintLabel] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            searchField.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            searchField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            searchField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            scroll.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 8),
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            hintLabel.topAnchor.constraint(equalTo: scroll.bottomAnchor, constant: 6),
            hintLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            hintLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            hintLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func setHint(_ hint: String) { hintLabel.stringValue = hint }

    override func draw(_ dirtyRect: NSRect) {
        // Hairline rules above and below the list, so the white well reads as
        // inset on the palette's gradient body.
        NSColor(calibratedWhite: 0.74, alpha: 1).setFill()
        let frame = scroll.frame
        NSRect(x: 0, y: frame.maxY, width: bounds.width, height: 1).fill()
        NSRect(x: 0, y: frame.minY - 1, width: bounds.width, height: 1).fill()
    }

    // MARK: - Items & selection

    var selectedItem: PickerItem? {
        guard filtered.indices.contains(tableView.selectedRow) else { return nil }
        let item = filtered[tableView.selectedRow]
        return item.isSeparator ? nil : item
    }

    func setItems(_ newItems: [PickerItem]) {
        let keep = selectedItem?.id
        items = newItems
        refilter(preserving: keep)
    }

    /// Moves the selection highlight programmatically (no onPick); nil clears it.
    /// A no-op when the row is already current, so palette re-syncs on every
    /// caret move don't keep yanking the scroll position around.
    func select(id: String?) {
        guard let id, let row = filtered.firstIndex(where: { $0.id == id }) else {
            suppressPick = true
            tableView.deselectAll(nil)
            suppressPick = false
            return
        }
        guard row != tableView.selectedRow else { return }
        selectRow(row, pick: false)
    }

    func clearFilter() {
        searchField.stringValue = ""
        refilter(preserving: selectedItem?.id)
    }

    func focusFilter() {
        window?.makeFirstResponder(searchField)
    }

    private func selectRow(_ row: Int, pick: Bool) {
        guard filtered.indices.contains(row) else { return }
        suppressPick = !pick
        tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        suppressPick = false
        tableView.scrollRowToVisible(row)
    }

    private func step(_ delta: Int) {
        guard !filtered.isEmpty else { return }
        let current = tableView.selectedRow
        var next = current < 0 ? (delta > 0 ? 0 : filtered.count - 1)
                               : max(0, min(filtered.count - 1, current + delta))
        // Skip section captions (stopping at the list edge if only captions remain).
        while filtered.indices.contains(next), filtered[next].isSeparator {
            let stepped = next + (delta > 0 ? 1 : -1)
            guard filtered.indices.contains(stepped) else { return }
            next = stepped
        }
        selectRow(next, pick: true)
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !suppressPick, let item = selectedItem else { return }
        onPick?(item)
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        filtered.indices.contains(row) && !filtered[row].isSeparator
    }

    @objc private func rowDoubleClicked() {
        if let onEdit, let item = selectedItem {
            onEdit(item)
        } else {
            onCommit?()
        }
    }

    // MARK: - Search field: live filter; arrows steer the list without leaving it

    private func refilter(preserving id: String?) {
        let query = searchField.stringValue.trimmingCharacters(in: .whitespaces)
        filtered = query.isEmpty ? items
            : items.filter { !$0.isSeparator && $0.title.localizedCaseInsensitiveContains(query) }
        tableView.reloadData()
        if let id, let row = filtered.firstIndex(where: { $0.id == id }) {
            selectRow(row, pick: false)
        }
    }

    func controlTextDidChange(_ obj: Notification) {
        refilter(preserving: selectedItem?.id)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.moveUp(_:)):
            step(-1)
            return true
        case #selector(NSResponder.moveDown(_:)):
            step(1)
            return true
        case #selector(NSResponder.insertNewline(_:)):
            onCommit?()
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            onCancel?()
            return true
        default:
            return false
        }
    }

    // MARK: - Table

    func numberOfRows(in tableView: NSTableView) -> Int { filtered.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let id = NSUserInterfaceItemIdentifier("cell")
        let cell = (tableView.makeView(withIdentifier: id, owner: self) as? PickerRowView) ?? {
            let v = PickerRowView()
            v.identifier = id
            return v
        }()
        let item = filtered[row]
        cell.configure(item: item,
                       font: item.isSeparator ? .systemFont(ofSize: 9, weight: .medium) : specimenFont(item),
                       showsEditWell: onEdit != nil && !item.isSeparator)
        cell.onEdit = { [weak self] in
            guard let self else { return }
            self.select(id: item.id)
            self.onEdit?(item)
        }
        return cell
    }

    // MARK: - Drag to reorder (the Style Library window)

    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
        guard allowsReordering, searchField.stringValue.isEmpty,
              filtered.indices.contains(row), !filtered[row].isSeparator else { return nil }
        let item = NSPasteboardItem()
        item.setString(String(row), forType: Self.reorderType)
        return item
    }

    func tableView(_ tableView: NSTableView, validateDrop info: NSDraggingInfo,
                   proposedRow row: Int, proposedDropOperation dropOperation: NSTableView.DropOperation) -> NSDragOperation {
        guard allowsReordering, searchField.stringValue.isEmpty,
              info.draggingSource as? NSTableView === tableView else { return [] }
        tableView.setDropRow(row, dropOperation: .above)
        return .move
    }

    func tableView(_ tableView: NSTableView, acceptDrop info: NSDraggingInfo,
                   row: Int, dropOperation: NSTableView.DropOperation) -> Bool {
        guard allowsReordering,
              let string = info.draggingPasteboard.string(forType: Self.reorderType),
              let from = Int(string), items.indices.contains(from) else { return false }
        var to = max(0, min(row, items.count))
        let moved = items.remove(at: from)
        if to > from { to -= 1 }
        items.insert(moved, at: to)
        refilter(preserving: moved.id)
        onReorder?(items)
        return true
    }
}

// MARK: - Row view (specimen label + optional edit well)

/// A list row: the specimen label, plus — when the list is editable — a small
/// classic edit well (a pencil in a bezel) shown while the pointer is over the
/// row (STYLES.md §6.1).
private final class PickerRowView: NSView {

    var onEdit: (() -> Void)?

    private let label = NSTextField(labelWithString: "")
    private let editWell = PickerEditWell()
    private var showsEditWell = false
    private var editWellWidth: NSLayoutConstraint!

    init() {
        super.init(frame: .zero)
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        editWell.translatesAutoresizingMaskIntoConstraints = false
        editWell.isHidden = true
        addSubview(label)
        addSubview(editWell)
        editWellWidth = editWell.widthAnchor.constraint(equalToConstant: 0)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.trailingAnchor.constraint(lessThanOrEqualTo: editWell.leadingAnchor, constant: -4),
            editWell.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            editWell.centerYAnchor.constraint(equalTo: centerYAnchor),
            editWellWidth,
            editWell.heightAnchor.constraint(equalToConstant: 16)
        ])
        editWell.target = self
        editWell.action = #selector(editPressed)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func configure(item: PickerItem, font: NSFont, showsEditWell: Bool) {
        label.stringValue = item.isSeparator ? item.title.uppercased() : item.title
        label.font = font
        label.textColor = item.dimmed ? NSColor(calibratedWhite: 0.45, alpha: 1) : .labelColor
        label.toolTip = item.title
        self.showsEditWell = showsEditWell
        // Reserve the well's width only in editable lists, so the popovers'
        // specimen labels keep their full row.
        editWellWidth.constant = showsEditWell ? 19 : 0
        editWell.isHidden = true
        updateTrackingAreas()
    }

    @objc private func editPressed() { onEdit?() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        guard showsEditWell else { return }
        addTrackingArea(NSTrackingArea(rect: bounds,
                                       options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) {
        if showsEditWell { editWell.isHidden = false }
    }

    override func mouseExited(with event: NSEvent) {
        editWell.isHidden = true
    }
}

/// The hand-drawn pencil well: a miniature classic bezel with a pencil glyph,
/// at row scale.
private final class PickerEditWell: NSControl {

    private var isPressed = false

    init() { super.init(frame: .zero) }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var needsPanelToBecomeKey: Bool { false }

    override func mouseDown(with event: NSEvent) {
        isPressed = true
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        let inside = bounds.contains(convert(event.locationInWindow, from: nil))
        isPressed = false
        needsDisplay = true
        if inside { sendAction(action, to: target) }
    }

    override func draw(_ dirtyRect: NSRect) {
        let active = ClassicChrome.active(for: self)
        let outline = ClassicChrome.bezelOutline(in: bounds, radius: 3)
        NSGraphicsContext.saveGraphicsState()
        outline.addClip()
        ClassicChrome.bezelGradient(isPressed ? .pressed : .normal, active: active).draw(in: bounds, angle: 90)
        NSGraphicsContext.restoreGraphicsState()
        ClassicChrome.bezelBorder(active).setStroke()
        outline.lineWidth = 1
        outline.stroke()

        // The pencil: a slanted shaft with a small nib triangle at its point.
        let color = ClassicChrome.glyphColor(active)
        color.setStroke()
        let shaft = NSBezierPath()
        shaft.move(to: NSPoint(x: bounds.midX - 1.5, y: bounds.midY - 1.5))
        shaft.line(to: NSPoint(x: bounds.midX + 3.5, y: bounds.midY + 3.5))
        shaft.lineWidth = 2
        shaft.stroke()
        color.setFill()
        let nib = NSBezierPath()
        nib.move(to: NSPoint(x: bounds.midX - 3.5, y: bounds.midY - 3.5))
        nib.line(to: NSPoint(x: bounds.midX - 1.0, y: bounds.midY - 1.0))
        nib.line(to: NSPoint(x: bounds.midX - 3.0, y: bounds.midY - 1.5))
        nib.close()
        nib.fill()
    }
}

/// Table that turns Return/Enter and Esc into commit/cancel, takes the first
/// click even when its window isn't key, and never drags key status over to a
/// non-activating palette panel (browsing must not steal focus from the page).
final class KeyCommandTableView: NSTableView {

    var onCommit: (() -> Void)?
    var onCancel: (() -> Void)?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override var needsPanelToBecomeKey: Bool { false }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 36, 76: onCommit?()        // return / keypad enter
        case 53: onCancel?()            // esc
        default: super.keyDown(with: event)
        }
    }
}
