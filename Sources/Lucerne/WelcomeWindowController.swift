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

    // A rotating letter-writing epigraph, indexed by day of year (idea 13). All
    // public-domain and kept short so the line reads as a single engraved italic
    // row, matching the tagline's look.
    private static let epigraphs = [
        "“A letter does not blush.” — Cicero",
        "“Letters mingle souls.” — John Donne",
        "“Write while the heat is in you.” — Thoreau",
        "“Writing maketh an exact man.” — Bacon",
        "“While we teach, we learn.” — Seneca",
        "“Brevity is the soul of wit.” — Shakespeare",
        "“Style is the dress of thoughts.” — Chesterfield",
        "“Well done is better than well said.” — Franklin"
    ]

    private static func epigraphOfTheDay() -> String {
        let day = Calendar.current.ordinality(of: .day, in: .year, for: Date()) ?? 1
        return epigraphs[(day - 1) % epigraphs.count]
    }

    convenience init() {
        let window = ClassicWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 690),
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
        icon.widthAnchor.constraint(equalToConstant: 112).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 112).isActive = true

        let title = ClassicText.engravedLabel("Lucerne", size: 30, weight: .bold, gray: 0.20)
        let tagline = ClassicText.engravedLabel("A small, pleasant tool for writing letters.",
                                                size: 13, italic: true, gray: 0.42)

        let rule = ClassicRuleView()
        rule.translatesAutoresizingMaskIntoConstraints = false
        rule.widthAnchor.constraint(equalToConstant: 150).isActive = true
        rule.heightAnchor.constraint(equalToConstant: 2).isActive = true

        let newButton = classicButton("New Letter", #selector(newDocument))
        let openButton = classicButton("Open…", #selector(openDocument))
        let sampleButton = classicButton("New Sample Letter", #selector(newSample))

        let recentLabel = ClassicText.engravedLabel("Recent Documents", size: 11,
                                                    weight: .semibold, gray: 0.40)
        recentLabel.alignment = .left

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("recent"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.rowHeight = 22
        tableView.usesAlternatingRowBackgroundColors = true
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
        recentBox.heightAnchor.constraint(equalToConstant: 190).isActive = true

        // A quiet rotating epigraph between the recents well and the version line,
        // styled exactly like the tagline (idea 13).
        let epigraph = ClassicText.engravedLabel(Self.epigraphOfTheDay(), size: 13,
                                                 italic: true, gray: 0.42)

        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        let versionLabel = ClassicText.engravedLabel("Version \(version ?? "—")", size: 10, gray: 0.5)

        let stack = NSStackView(views: [icon, title, tagline, rule,
                                        newButton, openButton, sampleButton,
                                        recentLabel, recentBox, epigraph, versionLabel])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 9
        stack.setCustomSpacing(14, after: icon)
        stack.setCustomSpacing(6, after: title)
        stack.setCustomSpacing(18, after: tagline)
        stack.setCustomSpacing(22, after: rule)
        stack.setCustomSpacing(24, after: sampleButton)
        stack.setCustomSpacing(16, after: recentBox)
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 30),
            // A `<=` bottom keeps the column from overflowing the panel without
            // forcing it to stretch when the content is naturally shorter — the
            // window is sized with a little headroom, so it normally floats free.
            stack.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -22),
            stack.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            stack.widthAnchor.constraint(equalToConstant: 348),
            newButton.widthAnchor.constraint(equalToConstant: 248),
            openButton.widthAnchor.constraint(equalToConstant: 248),
            sampleButton.widthAnchor.constraint(equalToConstant: 248),
            newButton.heightAnchor.constraint(equalToConstant: 24),
            openButton.heightAnchor.constraint(equalToConstant: 24),
            sampleButton.heightAnchor.constraint(equalToConstant: 24),
            recentLabel.leadingAnchor.constraint(equalTo: stack.leadingAnchor),
            recentBox.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])
        refreshRecents()
    }

    private func classicButton(_ title: String, _ action: Selector) -> ClassicButton {
        let button = ClassicButton(title: title, width: 248)
        button.target = self
        button.action = action
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }

    // These no longer close the window themselves: it is dismissed when a document
    // window actually becomes main (AppDelegate observes it), so a cancelled Open
    // panel or a failed recent leaves the welcome screen in place, not zero windows
    // (5.6). onOpenRecent surfaces its own error and keeps the welcome up (1.20).
    @objc private func newDocument() { onNew?() }
    @objc private func openDocument() { onOpen?() }
    @objc private func newSample() { onSample?() }

    @objc private func openSelectedRecent() {
        guard recents.indices.contains(tableView.clickedRow) else { return }
        onOpenRecent?(recents[tableView.clickedRow])
    }

    func numberOfRows(in tableView: NSTableView) -> Int { recents.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let id = NSUserInterfaceItemIdentifier("cell")
        let field = (tableView.makeView(withIdentifier: id, owner: self) as? NSTextField) ?? {
            let f = NSTextField(labelWithString: "")
            f.identifier = id
            f.font = NSFont.systemFont(ofSize: 12)
            f.lineBreakMode = .byTruncatingMiddle
            return f
        }()
        field.stringValue = recents[row].deletingPathExtension().lastPathComponent
        field.toolTip = recents[row].path
        return field
    }
}
