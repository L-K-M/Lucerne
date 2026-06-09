import AppKit

// A simple start screen shown when the app launches (or is reopened) with no
// document window — offering New / Open / sample and a list of recent documents.
// Saved/recovered documents are restored by macOS before this appears, so it only
// shows when there's genuinely nothing open.
final class WelcomeWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {

    var onNew: (() -> Void)?
    var onOpen: (() -> Void)?
    var onSample: (() -> Void)?
    var onOpenRecent: ((URL) -> Void)?

    private let tableView = NSTableView()
    private var recents: [URL] = []

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 460),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Welcome to Lucerne"
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .aqua)
        self.init(window: window)
        buildContent()
        window.center()
    }

    func refreshRecents() {
        recents = NSDocumentController.shared.recentDocumentURLs
        tableView.reloadData()
    }

    private func buildContent() {
        guard let content = window?.contentView else { return }

        let icon = NSImageView()
        icon.image = NSApp.applicationIconImage
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.widthAnchor.constraint(equalToConstant: 84).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 84).isActive = true

        let title = label("Lucerne", font: .systemFont(ofSize: 24, weight: .bold), color: .labelColor)
        let subtitle = label("Create a new letter or open a recent one",
                             font: .systemFont(ofSize: 12), color: .secondaryLabelColor)

        let newButton = button("New Document", #selector(newDocument))
        let openButton = button("Open…", #selector(openDocument))
        let sampleButton = button("New Sample Letter", #selector(newSample))

        let recentLabel = label("Recent Documents", font: .systemFont(ofSize: 11, weight: .semibold),
                                color: .secondaryLabelColor)
        recentLabel.alignment = .left

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("recent"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.rowHeight = 22
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.doubleAction = #selector(openSelectedRecent)
        let recentScroll = NSScrollView()
        recentScroll.documentView = tableView
        recentScroll.hasVerticalScroller = true
        recentScroll.borderType = .bezelBorder
        recentScroll.translatesAutoresizingMaskIntoConstraints = false
        recentScroll.heightAnchor.constraint(equalToConstant: 150).isActive = true

        let stack = NSStackView(views: [icon, title, subtitle, newButton, openButton, sampleButton,
                                        recentLabel, recentScroll])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 8
        stack.setCustomSpacing(14, after: icon)
        stack.setCustomSpacing(2, after: title)
        stack.setCustomSpacing(18, after: subtitle)
        stack.setCustomSpacing(18, after: sampleButton)
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 24),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -24),
            stack.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            stack.widthAnchor.constraint(equalToConstant: 300),
            newButton.widthAnchor.constraint(equalToConstant: 240),
            openButton.widthAnchor.constraint(equalToConstant: 240),
            sampleButton.widthAnchor.constraint(equalToConstant: 240),
            recentLabel.leadingAnchor.constraint(equalTo: stack.leadingAnchor),
            recentScroll.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])
        refreshRecents()
    }

    private func label(_ text: String, font: NSFont, color: NSColor) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = font
        field.textColor = color
        field.alignment = .center
        return field
    }

    private func button(_ title: String, _ action: Selector) -> NSButton {
        let b = NSButton(title: title, target: self, action: action)
        b.bezelStyle = .rounded
        b.translatesAutoresizingMaskIntoConstraints = false
        return b
    }

    @objc private func newDocument() { close(); onNew?() }
    @objc private func openDocument() { close(); onOpen?() }
    @objc private func newSample() { close(); onSample?() }

    @objc private func openSelectedRecent() {
        guard recents.indices.contains(tableView.clickedRow) else { return }
        let url = recents[tableView.clickedRow]
        close()
        onOpenRecent?(url)
    }

    func numberOfRows(in tableView: NSTableView) -> Int { recents.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let id = NSUserInterfaceItemIdentifier("cell")
        let field = (tableView.makeView(withIdentifier: id, owner: self) as? NSTextField) ?? {
            let f = NSTextField(labelWithString: "")
            f.identifier = id
            f.lineBreakMode = .byTruncatingMiddle
            return f
        }()
        field.stringValue = recents[row].deletingPathExtension().lastPathComponent
        field.toolTip = recents[row].path
        return field
    }
}
