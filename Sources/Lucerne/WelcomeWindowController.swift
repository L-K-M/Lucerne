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
    private let emptyRecentsLabel = ClassicText.engravedLabel("No recent letters yet", size: 11, gray: 0.55)

    convenience init() {
        let window = ClassicWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 516),
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
        emptyRecentsLabel.isHidden = !recents.isEmpty
    }

    private func buildContent() {
        guard let window else { return }
        let content = ClassicPanelView()
        window.contentView = content

        // The icon, with a soft drop shadow so it sits "on" the gradient panel.
        let icon = NSImageView()
        icon.image = AppIcon.image
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.wantsLayer = true
        let glow = NSShadow()
        glow.shadowColor = NSColor(calibratedWhite: 0, alpha: 0.28)
        glow.shadowOffset = NSSize(width: 0, height: -2)
        glow.shadowBlurRadius = 6
        icon.shadow = glow
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.widthAnchor.constraint(equalToConstant: 88).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 88).isActive = true

        let title = ClassicText.engravedLabel("Lucerne", size: 26, weight: .bold, gray: 0.22)
        let tagline = ClassicText.engravedLabel("A small, pleasant tool for writing letters.",
                                                size: 12, italic: true, gray: 0.42)

        let rule = ClassicRuleView()
        rule.translatesAutoresizingMaskIntoConstraints = false
        rule.widthAnchor.constraint(equalToConstant: 132).isActive = true
        rule.heightAnchor.constraint(equalToConstant: 2).isActive = true

        let newButton = classicButton("New Letter", #selector(newDocument))
        let sampleButton = classicButton("New Sample Letter", #selector(newSample))
        let openButton = classicButton("Open…", #selector(openDocument))

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
        // Empty-state, centered in the well (chiefly seen under `swift run`, where
        // the unbundled binary has no recent-documents list — the real .app does).
        emptyRecentsLabel.translatesAutoresizingMaskIntoConstraints = false
        recentBox.addSubview(emptyRecentsLabel)
        NSLayoutConstraint.activate([
            emptyRecentsLabel.centerXAnchor.constraint(equalTo: recentBox.centerXAnchor),
            emptyRecentsLabel.centerYAnchor.constraint(equalTo: recentBox.centerYAnchor)
        ])
        recentBox.translatesAutoresizingMaskIntoConstraints = false
        recentBox.heightAnchor.constraint(equalToConstant: 150).isActive = true

        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        let versionLabel = ClassicText.engravedLabel("Version \(version ?? "—")", size: 10, gray: 0.5)

        let stack = NSStackView(views: [icon, title, tagline, rule,
                                        newButton, sampleButton, openButton,
                                        recentLabel, recentBox, versionLabel])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 8
        stack.setCustomSpacing(12, after: icon)
        stack.setCustomSpacing(6, after: title)
        stack.setCustomSpacing(14, after: tagline)
        stack.setCustomSpacing(18, after: rule)
        stack.setCustomSpacing(18, after: openButton)
        stack.setCustomSpacing(14, after: recentBox)
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 24),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -18),
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
