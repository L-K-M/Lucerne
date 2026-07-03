import AppKit
import UniformTypeIdentifiers

// The Style Library window (STYLES.md §7): the explicit, deliberately-opened
// home of the global library — NOT a state the styles palette slips into. One
// instance, opened from Format ▸ Style Library…, independent of any document.
//
// Content: the same specimen-book list the palette uses, with per-row edit wells
// (opening the one style editor, library-targeted), drag-to-reorder (persisted
// into each definition's `order`, which seeding carries into future documents),
// a New… / Duplicate / Delete / Import… / Export… footer, and Add to Letter.
// Deleting here is always safe for existing letters: every document embeds its
// own copies (S2), so removal only changes what future documents are seeded with.
public final class StyleLibraryWindowController: NSWindowController, NSWindowDelegate {

    public static let shared = StyleLibraryWindowController()

    /// Whether the singleton has ever been created — so callers (the style
    /// editor's first-open placement) can ask about the window without
    /// instantiating it as a side effect.
    private static var hasBeenCreated = false

    /// The Library window, if it is currently on screen.
    static func visibleWindow() -> NSWindow? {
        guard hasBeenCreated, let window = shared.window, window.isVisible else { return nil }
        return window
    }

    private let list = PickerListView(hint: "Drag to reorder — new letters start with these styles")
    private let emptyLabel = NSTextField(wrappingLabelWithString:
        "Your Library is empty.\nSave a style from a letter (Save to Library), or create one here (New…).")
    private let addToLetterButton = ClassicButton(title: "Add to Letter")
    private var observers: [NSObjectProtocol] = []

    private init() {
        let window = ClassicWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 460),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Style Library"
        window.appearance = NSAppearance(named: .aqua)
        window.isReleasedWhenClosed = false
        super.init(window: window)
        Self.hasBeenCreated = true
        window.delegate = self
        buildContent()
        window.center()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    public func show() {
        installObservers()
        reload()
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    // MARK: - Content

    private func buildContent() {
        guard let content = window?.contentView else { return }
        let backdrop = ClassicPanelView()
        backdrop.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(backdrop)

        list.allowsReordering = true
        list.onReorder = { [weak self] items in self?.persistOrder(items) }
        list.onEdit = { item in
            StyleEditorPanel.shared.open(key: item.id, library: true)
        }
        list.onCommit = {}
        list.onCancel = { [weak self] in self?.window?.performClose(nil) }
        list.specimenFont = { item in
            FloatingPalette.styleSpecimenFont(role: item.id, styles: StyleLibrary.shared.load())
        }

        let box = ClassicInsetBox()
        box.embed(list)
        box.translatesAutoresizingMaskIntoConstraints = false

        emptyLabel.font = .systemFont(ofSize: 11)
        emptyLabel.textColor = NSColor(calibratedWhite: 0.45, alpha: 1)
        emptyLabel.alignment = .center
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyLabel.isHidden = true

        let newButton = ClassicButton(title: "New…")
        newButton.target = self
        newButton.action = #selector(newPressed)
        let duplicateButton = ClassicButton(title: "Duplicate")
        duplicateButton.target = self
        duplicateButton.action = #selector(duplicatePressed)
        let deleteButton = ClassicButton(title: "Delete")
        deleteButton.target = self
        deleteButton.action = #selector(deletePressed)
        let importButton = ClassicButton(title: "Import…")
        importButton.target = self
        importButton.action = #selector(importPressed)
        let exportButton = ClassicButton(title: "Export…")
        exportButton.target = self
        exportButton.action = #selector(exportPressed)
        addToLetterButton.target = self
        addToLetterButton.action = #selector(addToLetterPressed)

        let editRow = NSStackView(views: [newButton, duplicateButton, deleteButton])
        editRow.orientation = .horizontal
        editRow.spacing = 6
        let ioRow = NSStackView(views: [importButton, exportButton, addToLetterButton])
        ioRow.orientation = .horizontal
        ioRow.spacing = 6
        let footer = NSStackView(views: [editRow, ioRow])
        footer.orientation = .vertical
        footer.alignment = .leading
        footer.spacing = 7
        footer.translatesAutoresizingMaskIntoConstraints = false

        content.addSubview(box)
        content.addSubview(emptyLabel)
        content.addSubview(footer)
        NSLayoutConstraint.activate([
            backdrop.topAnchor.constraint(equalTo: content.topAnchor),
            backdrop.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            backdrop.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            backdrop.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            box.topAnchor.constraint(equalTo: content.topAnchor, constant: 12),
            box.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            box.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            footer.topAnchor.constraint(equalTo: box.bottomAnchor, constant: 10),
            footer.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            footer.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -12),
            footer.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -12),
            emptyLabel.centerXAnchor.constraint(equalTo: box.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: box.centerYAnchor),
            emptyLabel.widthAnchor.constraint(lessThanOrEqualTo: box.widthAnchor, constant: -32)
        ])
    }

    // MARK: - Data

    private func reload() {
        let library = StyleLibrary.shared.load()
        let keep = list.selectedItem?.id
        list.setItems(LucerneDocumentModel.orderedStyleRoles(in: library).map {
            PickerItem(id: $0, title: library[$0]?.name ?? $0)
        })
        list.select(id: keep)
        emptyLabel.isHidden = !library.isEmpty
        addToLetterButton.isEnabled = FloatingPalette.activeDocumentWindowController() != nil
    }

    /// Drag-to-reorder landed: renumber `order` 0…n in the new order and save —
    /// seeding (S6) carries this order into future documents.
    private func persistOrder(_ items: [PickerItem]) {
        var library = StyleLibrary.shared.load()
        for (index, item) in items.enumerated() {
            library[item.id]?.order = Double(index)
        }
        StyleLibrary.shared.save(library)
    }

    // MARK: - Footer actions

    @objc private func newPressed() {
        var def = ParagraphStyleDef.fallbackBody
        def.name = uniqueName(from: "Untitled Style")
        def.markdown = "p"
        let key = IDGenerator.next("style")
        StyleLibrary.shared.saveStyle(def, forKey: key)
        reload()
        list.select(id: key)
        StyleEditorPanel.shared.open(key: key, library: true, focusName: true)
    }

    @objc private func duplicatePressed() {
        guard let item = list.selectedItem,
              var def = StyleLibrary.shared.load()[item.id] else { return }
        def.name = uniqueName(from: def.name)
        def.order = nil   // saveStyle appends it
        let key = IDGenerator.next("style")
        StyleLibrary.shared.saveStyle(def, forKey: key)
        reload()
        list.select(id: key)
        StyleEditorPanel.shared.open(key: key, library: true, focusName: true)
    }

    @objc private func deletePressed() {
        guard let item = list.selectedItem,
              let def = StyleLibrary.shared.load()[item.id] else { return }
        // Always safe for existing letters (they embed their own copies, S2) —
        // even `body`: a library body is only an override of the built-in default.
        let alert = NSAlert()
        alert.messageText = "Remove “\(def.name)” from your Library?"
        alert.informativeText = "Letters that already use it keep their own copy; "
            + "only what future letters start with changes."
        alert.addButton(withTitle: "Remove")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        StyleLibrary.shared.removeStyle(forKey: item.id)
        reload()
    }

    @objc private func addToLetterPressed() {
        guard let item = list.selectedItem,
              let def = StyleLibrary.shared.load()[item.id],
              let wc = FloatingPalette.activeDocumentWindowController() else { return }
        wc.editor.addOrReplaceStyle(def, forKey: item.id, actionName: "Add Library Style")
        wc.paletteDidApplyFormatting()
    }

    @objc private func importPressed() {
        guard let window else { return }
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.json]
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            do {
                let imported = try StyleLibrary.decode(try Data(contentsOf: url))
                var library = StyleLibrary.shared.load()
                for (key, def) in imported { library[key] = def }   // S7: by key, import wins
                StyleLibrary.shared.save(library)
                self?.reload()
            } catch {
                NSAlert(error: error).beginSheetModal(for: window, completionHandler: nil)
            }
        }
    }

    @objc private func exportPressed() {
        guard let window else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "Lucerne Styles.json"
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try StyleLibrary.encode(StyleLibrary.shared.load()).write(to: url)
            } catch {
                NSAlert(error: error).beginSheetModal(for: window, completionHandler: nil)
            }
        }
    }

    private func uniqueName(from base: String) -> String {
        let names = Set(StyleLibrary.shared.load().values.map(\.name))
        if !names.contains(base) { return base }
        var counter = 2
        while names.contains("\(base) \(counter)") { counter += 1 }
        return "\(base) \(counter)"
    }

    // MARK: - Refresh triggers (§8: read on demand; refresh when it activates)

    private func installObservers() {
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: StyleLibrary.didChange, object: nil, queue: .main) { [weak self] _ in
                self?.reload()
            })
        observers.append(center.addObserver(
            forName: NSWindow.didBecomeMainNotification, object: nil, queue: .main) { [weak self] _ in
                self?.reload()   // Add to Letter enables/disables with the front document
            })
    }

    private func removeObservers() {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers = []
    }

    public func windowDidBecomeKey(_ notification: Notification) {
        reload()
    }

    /// A closed Library window must stop reloading (with disk I/O) on every
    /// window-main change and every library save; `show()` re-installs (2.10).
    public func windowWillClose(_ notification: Notification) {
        removeObservers()
    }
}
