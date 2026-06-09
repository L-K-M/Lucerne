import AppKit

// The font "try-on" picker: a transient popover anchored to the toolbar's font
// control. Every family is listed in its own typeface; moving the selection
// (arrow keys, clicks, or filtering in the search field) applies the face to the
// document live WITHOUT closing the picker, so you can flip through typefaces
// and watch your actual letter change. Return or double-click keeps the current
// face, Esc reverts to the one you started with, and clicking outside keeps
// whatever you were trying. The whole session lands as a single undo step
// (EditorController.beginFontPreview / endFontPreview).
final class FontPickerPopover: NSObject, NSPopoverDelegate,
                               NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {

    private let families: [String]
    private var filtered: [String]
    private var popover: NSPopover?
    private var onPreview: ((String) -> Void)?
    private var onFinish: ((Bool) -> Void)?
    private var finished = false
    private var suppressPreview = false

    private let searchField = NSSearchField()
    private let tableView = KeyCommandTableView()

    override init() {
        families = NSFontManager.shared.availableFontFamilies
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        filtered = families
        super.init()
    }

    var isShown: Bool { popover?.isShown ?? false }

    func present(from anchor: NSView, current: String?,
                 onPreview: @escaping (String) -> Void,
                 onFinish: @escaping (Bool) -> Void) {
        guard popover == nil else { return }
        self.onPreview = onPreview
        self.onFinish = onFinish
        finished = false
        filtered = families
        searchField.stringValue = ""

        let pop = NSPopover()
        pop.behavior = .transient
        pop.appearance = NSAppearance(named: .aqua)
        let controller = NSViewController()
        controller.view = buildContent()
        pop.contentViewController = controller
        pop.contentSize = NSSize(width: 280, height: 400)
        pop.delegate = self
        popover = pop
        pop.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY)

        tableView.reloadData()
        if let current, let row = filtered.firstIndex(of: current) {
            selectRow(row, preview: false)
        }
        controller.view.window?.makeFirstResponder(searchField)
    }

    private func buildContent() -> NSView {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 280, height: 400))

        searchField.placeholderString = "Filter typefaces"
        searchField.font = NSFont.systemFont(ofSize: 12)
        searchField.delegate = self
        searchField.focusRingType = .none

        if tableView.tableColumns.isEmpty {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("family"))
            column.resizingMask = .autoresizingMask
            tableView.addTableColumn(column)
        }
        tableView.headerView = nil
        tableView.rowHeight = 24
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.doubleAction = #selector(rowDoubleClicked)
        tableView.onCommit = { [weak self] in self?.finish(commit: true) }
        tableView.onCancel = { [weak self] in self?.finish(commit: false) }

        let scroll = NSScrollView()
        scroll.documentView = tableView
        scroll.hasVerticalScroller = true
        scroll.borderType = .noBorder

        let hint = NSTextField(labelWithString: "↑↓ try on your letter  ·  Return keep  ·  Esc revert")
        hint.font = NSFont.systemFont(ofSize: 10)
        hint.textColor = NSColor(calibratedWhite: 0.45, alpha: 1)
        hint.alignment = .center
        hint.lineBreakMode = .byTruncatingTail

        for view in [searchField, scroll, hint] {
            view.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(view)
        }
        NSLayoutConstraint.activate([
            searchField.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
            searchField.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
            searchField.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),
            scroll.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 8),
            scroll.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            hint.topAnchor.constraint(equalTo: scroll.bottomAnchor, constant: 6),
            hint.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
            hint.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),
            hint.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -6)
        ])
        return container
    }

    // MARK: - Selection & preview

    private func selectRow(_ row: Int, preview: Bool) {
        guard filtered.indices.contains(row) else { return }
        suppressPreview = !preview
        tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        suppressPreview = false
        tableView.scrollRowToVisible(row)
    }

    private func step(_ delta: Int) {
        guard !filtered.isEmpty else { return }
        let current = tableView.selectedRow
        let next = current < 0 ? (delta > 0 ? 0 : filtered.count - 1)
                               : max(0, min(filtered.count - 1, current + delta))
        selectRow(next, preview: true)
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !suppressPreview, filtered.indices.contains(tableView.selectedRow) else { return }
        onPreview?(filtered[tableView.selectedRow])
    }

    @objc private func rowDoubleClicked() { finish(commit: true) }

    private func finish(commit: Bool) {
        guard !finished else { return }
        finished = true
        onFinish?(commit)
        popover?.close()
    }

    func popoverDidClose(_ notification: Notification) {
        if !finished {
            finished = true
            onFinish?(true)   // click-away keeps the current try-on
        }
        popover = nil
        onPreview = nil
        onFinish = nil
    }

    // MARK: - Search field: live filter; arrows steer the list without leaving it

    func controlTextDidChange(_ obj: Notification) {
        let query = searchField.stringValue.trimmingCharacters(in: .whitespaces)
        let selectedName = filtered.indices.contains(tableView.selectedRow)
            ? filtered[tableView.selectedRow] : nil
        filtered = query.isEmpty ? families
            : families.filter { $0.localizedCaseInsensitiveContains(query) }
        tableView.reloadData()
        if let name = selectedName, let row = filtered.firstIndex(of: name) {
            selectRow(row, preview: false)
        }
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
            finish(commit: true)
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            finish(commit: false)
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
        let family = filtered[row]
        field.stringValue = family
        // Each family shown in itself — the list is the specimen book.
        field.font = NSFontManager.shared.font(withFamily: family, traits: [], weight: 5, size: 13)
            ?? NSFont.systemFont(ofSize: 13)
        field.toolTip = family
        return field
    }
}

/// Table that turns Return/Enter and Esc into commit/cancel for the picker.
private final class KeyCommandTableView: NSTableView {

    var onCommit: (() -> Void)?
    var onCancel: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 36, 76: onCommit?()        // return / keypad enter
        case 53: onCancel?()            // esc
        default: super.keyDown(with: event)
        }
    }
}
