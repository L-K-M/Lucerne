import AppKit

/// One row of a try-on picker or floating palette: a stable identity (a font
/// family name or a paragraph-style role) plus the title shown for it.
struct PickerItem: Equatable {
    let id: String
    let title: String
}

/// The shared specimen-list UI used by the attached try-on popovers and the
/// floating palettes: a filter field over a one-column table whose rows draw in
/// a per-item specimen font (the list is the specimen book), with a hint line
/// underneath. Moving the selection — clicks, ↑↓ from the filter field, or
/// filtering itself — reports through `onPick` without dismissing anything;
/// Return/double-click and Esc report through `onCommit`/`onCancel`.
final class PickerListView: NSView, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {

    /// Selection landed on an item by user action (click, arrows, filter).
    var onPick: ((PickerItem) -> Void)?
    var onCommit: (() -> Void)?
    var onCancel: (() -> Void)?
    /// Resolves the font a row is drawn in — lazily, per visible row, so listing
    /// every installed family doesn't load every installed font up front.
    var specimenFont: (PickerItem) -> NSFont = { _ in .systemFont(ofSize: 13) }

    private(set) var items: [PickerItem] = []
    private var filtered: [PickerItem] = []
    private var suppressPick = false

    private let searchField = NSSearchField()
    private let tableView = KeyCommandTableView()
    private let scroll = NSScrollView()

    init(hint: String) {
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

        scroll.documentView = tableView
        scroll.hasVerticalScroller = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = true
        scroll.backgroundColor = .white

        let hintLabel = NSTextField(labelWithString: hint)
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
        filtered.indices.contains(tableView.selectedRow) ? filtered[tableView.selectedRow] : nil
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
        let next = current < 0 ? (delta > 0 ? 0 : filtered.count - 1)
                               : max(0, min(filtered.count - 1, current + delta))
        selectRow(next, pick: true)
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !suppressPick, let item = selectedItem else { return }
        onPick?(item)
    }

    @objc private func rowDoubleClicked() {
        onCommit?()
    }

    // MARK: - Search field: live filter; arrows steer the list without leaving it

    private func refilter(preserving id: String?) {
        let query = searchField.stringValue.trimmingCharacters(in: .whitespaces)
        filtered = query.isEmpty ? items
            : items.filter { $0.title.localizedCaseInsensitiveContains(query) }
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
        let field = (tableView.makeView(withIdentifier: id, owner: self) as? NSTextField) ?? {
            let f = NSTextField(labelWithString: "")
            f.identifier = id
            f.lineBreakMode = .byTruncatingTail
            return f
        }()
        let item = filtered[row]
        field.stringValue = item.title
        // Each row shown in its own face — the list is the specimen book.
        field.font = specimenFont(item)
        field.toolTip = item.title
        return field
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
