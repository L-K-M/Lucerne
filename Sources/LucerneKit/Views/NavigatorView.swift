import AppKit

// A heading navigator: a sidebar list of the document's headings (built from the
// heading paragraph styles). Clicking a row reveals that heading. Pure navigation —
// it does not modify the document.
public final class NavigatorView: NSView, NSTableViewDataSource, NSTableViewDelegate {

    public var onSelect: ((Int) -> Void)?   // character index of the chosen heading

    private let tableView = NSTableView()
    private let scrollView = NSScrollView()
    private let titleLabel = NSTextField(labelWithString: "Contents")
    private var items: [EditorController.HeadingItem] = []

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor(calibratedWhite: 0.92, alpha: 1).cgColor

        titleLabel.font = NSFont.systemFont(ofSize: 10, weight: .semibold)
        titleLabel.textColor = NSColor(calibratedWhite: 0.4, alpha: 1)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("title"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.backgroundColor = .clear
        tableView.rowHeight = 20
        tableView.intercellSpacing = NSSize(width: 0, height: 2)
        tableView.selectionHighlightStyle = .regular
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.action = #selector(rowClicked)

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            scrollView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 6),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    public func setItems(_ newItems: [EditorController.HeadingItem]) {
        guard newItems != items else { return }
        items = newItems
        tableView.reloadData()
    }

    @objc private func rowClicked() {
        let row = tableView.clickedRow
        guard items.indices.contains(row) else { return }
        onSelect?(items[row].characterIndex)
    }

    public func numberOfRows(in tableView: NSTableView) -> Int { items.count }

    public func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let id = NSUserInterfaceItemIdentifier("cell")
        let field = (tableView.makeView(withIdentifier: id, owner: self) as? NSTextField)
            ?? {
                let f = NSTextField(labelWithString: "")
                f.identifier = id
                f.lineBreakMode = .byTruncatingTail
                f.cell?.truncatesLastVisibleLine = true
                return f
            }()
        let item = items[row]
        field.stringValue = String(repeating: "   ", count: max(0, item.level - 1)) + item.title
        field.font = item.level == 1 ? NSFont.boldSystemFont(ofSize: 12) : NSFont.systemFont(ofSize: 11)
        field.textColor = .labelColor
        return field
    }
}
