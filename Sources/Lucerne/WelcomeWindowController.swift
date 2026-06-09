import AppKit
import LucerneKit

// A simple start screen shown when the app launches (or is reopened) with no
// document window — offering New / Open / sample and a list of recent documents.
// Saved/recovered documents are restored by macOS before this appears, so it only
// shows when there's genuinely nothing open. Drawn in the app's classic chrome:
// a gradient panel, engraved lettering, bezel buttons, and a white inset well
// for the recents (see LucerneKit's ClassicControls).
final class WelcomeWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {

    var onNew: (() -> Void)?
    var onOpen: (() -> Void)?
    var onSample: (() -> Void)?
    var onOpenRecent: ((URL) -> Void)?

    private let tableView = NSTableView()
    private var recents: [URL] = []

    convenience init() {
        let window = ClassicWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 470),
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
        guard let window else { return }
        let content = ClassicPanelView()
        window.contentView = content

        let icon = NSImageView()
        icon.image = AppIcon.image
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.widthAnchor.constraint(equalToConstant: 84).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 84).isActive = true

        let title = ClassicText.engravedLabel("Lucerne", size: 24, weight: .bold, gray: 0.25)
        let subtitle = ClassicText.engravedLabel("Create a new letter or open a recent one",
                                                 size: 12, gray: 0.42)

        let newButton = classicButton("New Document", #selector(newDocument))
        let openButton = classicButton("Open…", #selector(openDocument))
        let sampleButton = classicButton("New Sample Letter", #selector(newSample))

        let recentLabel = ClassicText.engravedLabel("Recent Documents", size: 11,
                                                    weight: .semibold, gray: 0.40)
        recentLabel.alignment = .left

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("recent"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.rowHeight = 20
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.doubleAction = #selector(openSelectedRecent)
        tableView.backgroundColor = .white
        let recentScroll = NSScrollView()
        recentScroll.documentView = tableView
        recentScroll.hasVerticalScroller = true
        recentScroll.borderType = .noBorder
        recentScroll.drawsBackground = false
        let recentBox = ClassicInsetBox()
        recentBox.embed(recentScroll)
        recentBox.translatesAutoresizingMaskIntoConstraints = false
        recentBox.heightAnchor.constraint(equalToConstant: 150).isActive = true

        let stack = NSStackView(views: [icon, title, subtitle, newButton, openButton, sampleButton,
                                        recentLabel, recentBox])
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
            newButton.widthAnchor.constraint(equalToConstant: 220),
            openButton.widthAnchor.constraint(equalToConstant: 220),
            sampleButton.widthAnchor.constraint(equalToConstant: 220),
            recentLabel.leadingAnchor.constraint(equalTo: stack.leadingAnchor),
            recentBox.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])
        refreshRecents()
    }

    private func classicButton(_ title: String, _ action: Selector) -> ClassicButton {
        let button = ClassicButton(title: title, width: 220)
        button.target = self
        button.action = action
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
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
            f.font = NSFont.systemFont(ofSize: 11)
            f.lineBreakMode = .byTruncatingMiddle
            return f
        }()
        field.stringValue = recents[row].deletingPathExtension().lastPathComponent
        field.toolTip = recents[row].path
        return field
    }
}
