import AppKit

// A small Find & Replace panel that operates on the editor's shared text storage.
// The stock NSTextView find machinery can't navigate Lucerne's one-text-view-per-
// page layout (a match may be laid out in another page's container), so this
// searches the storage directly and reveals matches through the editor, which
// focuses and scrolls the right page.
public final class FindPanelController: NSWindowController {

    private weak var editor: EditorController?
    private let findField = NSTextField(string: "")
    private let replaceField = NSTextField(string: "")
    private let statusLabel = NSTextField(labelWithString: "")
    private let matchCaseButton = NSButton(checkboxWithTitle: "Match Case", target: nil, action: nil)

    // Match Case ON means exact matching (also drop diacritic-insensitivity); OFF
    // keeps the classic forgiving search (case- and diacritic-insensitive).
    private var searchOptions: NSString.CompareOptions {
        matchCaseButton.state == .on ? [] : [.caseInsensitive, .diacriticInsensitive]
    }

    public init(editor: EditorController) {
        self.editor = editor
        let panel = FindPanel(contentRect: NSRect(x: 0, y: 0, width: 420, height: 172),
                              styleMask: [.titled, .closable, .utilityWindow],
                              backing: .buffered, defer: false)
        panel.title = "Find"
        panel.isReleasedWhenClosed = false
        panel.appearance = NSAppearance(named: .aqua)
        super.init(window: panel)
        buildContent()
        panel.center()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    // MARK: - UI

    private func buildContent() {
        guard let content = window?.contentView else { return }

        findField.placeholderString = "Text to find"
        replaceField.placeholderString = "Replacement"

        let grid = NSGridView(views: [
            [NSTextField(labelWithString: "Find:"), findField],
            [NSTextField(labelWithString: "Replace:"), replaceField]
        ])
        grid.rowSpacing = 8
        grid.columnSpacing = 8
        grid.column(at: 0).xPlacement = .trailing
        findField.widthAnchor.constraint(greaterThanOrEqualToConstant: 280).isActive = true

        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.alignment = .center
        statusLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let replaceAllButton = NSButton(title: "Replace All", target: self, action: #selector(replaceAllPressed))
        let replaceButton = NSButton(title: "Replace", target: self, action: #selector(replacePressed))
        let previousButton = NSButton(title: "Previous", target: self, action: #selector(findPreviousPressed))
        let nextButton = NSButton(title: "Next", target: self, action: #selector(findNextPressed))
        nextButton.keyEquivalent = "\r"     // Return finds the next match

        let buttonRow = NSStackView(views: [replaceAllButton, replaceButton, statusLabel,
                                            previousButton, nextButton])
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 8

        let optionsRow = NSStackView(views: [matchCaseButton])
        optionsRow.orientation = .horizontal
        optionsRow.spacing = 8

        let stack = NSStackView(views: [grid, optionsRow, buttonRow])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 16),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -16),
            buttonRow.trailingAnchor.constraint(equalTo: stack.trailingAnchor)
        ])
    }

    // MARK: - Public entry points (menu commands route here via the window controller)

    /// Shows the panel, seeding the search field from a short text selection.
    public func showPanel() {
        if let tv = editor?.activeTextView {
            let sel = tv.selectedRange()
            let ns = tv.string as NSString
            if sel.length > 0, sel.length < 200, NSMaxRange(sel) <= ns.length {
                findField.stringValue = ns.substring(with: sel)
            }
        }
        if findField.stringValue.isEmpty { seedQueryFromFindPasteboard() }
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(findField)
        status("")
    }

    @discardableResult
    public func findNext() -> Bool { find(forward: true) }

    @discardableResult
    public func findPrevious() -> Bool { find(forward: false) }

    /// Fills the search field from an external source (⌘E Use Selection for Find)
    /// and publishes it to the system find pasteboard, without opening the panel.
    public func setQuery(_ text: String) {
        findField.stringValue = text
        writeToFindPasteboard()
    }

    // MARK: - Find

    private var query: String { findField.stringValue }
    private var replacement: String { replaceField.stringValue }

    /// The text view search/replace acts through; focuses the first page if the
    /// caret hasn't landed anywhere yet (so undo and notifications work).
    private func targetTextView() -> PageTextView? {
        guard let editor else { return nil }
        if editor.activeTextView == nil { editor.focusInitialResponder() }
        return editor.activeTextView
    }

    private func find(forward: Bool) -> Bool {
        if query.isEmpty { seedQueryFromFindPasteboard() }
        guard let editor, !query.isEmpty else { NSSound.beep(); return false }
        writeToFindPasteboard()
        let ns = editor.textStorage.string as NSString
        guard ns.length > 0 else { notFound(); return false }
        let sel = editor.activeTextView?.selectedRange() ?? NSRange(location: 0, length: 0)
        let start = min(NSMaxRange(sel), ns.length)

        var match = NSRange(location: NSNotFound, length: 0)
        if forward {
            match = ns.range(of: query, options: searchOptions,
                             range: NSRange(location: start, length: ns.length - start))
            if match.location == NSNotFound {   // wrap to the top
                match = ns.range(of: query, options: searchOptions,
                                 range: NSRange(location: 0, length: ns.length))
            }
        } else {
            let head = min(sel.location, ns.length)
            match = ns.range(of: query, options: searchOptions.union(.backwards),
                             range: NSRange(location: 0, length: head))
            if match.location == NSNotFound {   // wrap to the bottom
                match = ns.range(of: query, options: searchOptions.union(.backwards),
                                 range: NSRange(location: 0, length: ns.length))
            }
        }

        guard match.location != NSNotFound else { notFound(); return false }
        reveal(match)
        return true
    }

    /// Scrolls to a match (focusing whichever page it laid out on) and selects it.
    private func reveal(_ range: NSRange) {
        guard let editor else { return }
        editor.revealHeading(atCharacterIndex: range.location)
        if let tv = editor.activeTextView {
            tv.setSelectedRange(range)
            tv.showFindIndicator(for: range)
        }
        let counts = matchCounts(revealed: range)
        status(counts.index > 0 ? "\(counts.index) of \(counts.total)" : "")
    }

    /// Counts every match of the current query and reports the 1-based position of
    /// the revealed one, ordered by location (index 0 if it isn't among them).
    private func matchCounts(revealed: NSRange) -> (index: Int, total: Int) {
        guard let editor else { return (0, 0) }
        let ns = editor.textStorage.string as NSString
        var total = 0, index = 0, cursor = 0
        while cursor < ns.length {
            let found = ns.range(of: query, options: searchOptions,
                                 range: NSRange(location: cursor, length: ns.length - cursor))
            guard found.location != NSNotFound else { break }
            total += 1
            if found.location == revealed.location { index = total }
            cursor = NSMaxRange(found) > cursor ? NSMaxRange(found) : cursor + 1
        }
        return (index, total)
    }

    // MARK: - Replace

    @objc private func replacePressed() {
        guard let editor, !query.isEmpty, let tv = targetTextView() else { NSSound.beep(); return }
        let sel = tv.selectedRange()
        let ns = editor.textStorage.string as NSString
        // Replace the current selection only when it is a match; then advance.
        if sel.length > 0, NSMaxRange(sel) <= ns.length,
           ns.substring(with: sel).compare(query, options: searchOptions) == .orderedSame,
           tv.shouldChangeText(in: sel, replacementString: replacement) {
            editor.textStorage.replaceCharacters(in: sel, with: replacement)
            tv.didChangeText()
            tv.undoManager?.setActionName("Replace")
            tv.setSelectedRange(NSRange(location: sel.location,
                                        length: (replacement as NSString).length))
        }
        findNext()
    }

    @objc private func replaceAllPressed() {
        guard let editor, !query.isEmpty, let tv = targetTextView() else { NSSound.beep(); return }
        let ns = editor.textStorage.string as NSString
        var matches: [NSRange] = []
        var cursor = 0
        while cursor < ns.length {
            let found = ns.range(of: query, options: searchOptions,
                                 range: NSRange(location: cursor, length: ns.length - cursor))
            guard found.location != NSNotFound else { break }
            matches.append(found)
            cursor = NSMaxRange(found) > cursor ? NSMaxRange(found) : cursor + 1
        }
        guard !matches.isEmpty else { notFound(); return }

        // One undo record for the whole sweep: the multi-range shouldChangeText
        // form registers a single change. Batch the mutations between begin/end
        // Editing and fire didChangeText once. Replace back-to-front so earlier
        // ranges stay valid as the storage length shifts under us.
        let replacements = Array(repeating: replacement, count: matches.count)
        guard tv.shouldChangeText(inRanges: matches.map { NSValue(range: $0) },
                                  replacementStrings: replacements) else { return }
        editor.textStorage.beginEditing()
        for range in matches.reversed() {
            editor.textStorage.replaceCharacters(in: range, with: replacement)
        }
        editor.textStorage.endEditing()
        tv.didChangeText()
        tv.undoManager?.setActionName("Replace All")
        let replaced = matches.count
        status(replaced == 1 ? "Replaced 1 match" : "Replaced \(replaced) matches")
    }

    // MARK: - Status

    @objc private func findNextPressed() { findNext() }
    @objc private func findPreviousPressed() { findPrevious() }

    private func notFound() {
        NSSound.beep()
        status("Not found")
    }

    private func status(_ text: String) {
        statusLabel.stringValue = text
    }

    // MARK: - System find pasteboard

    // Publish the current query to the shared find pasteboard so ⌘G and other apps
    // (Safari, TextEdit) see the same term; seeding pulls one in when empty.
    private func writeToFindPasteboard() {
        let pb = NSPasteboard(name: .find)
        pb.clearContents()
        pb.setString(query, forType: .string)
    }

    private func seedQueryFromFindPasteboard() {
        if let shared = NSPasteboard(name: .find).string(forType: .string), !shared.isEmpty {
            findField.stringValue = shared
        }
    }
}

// An NSPanel that treats Esc (cancelOperation) as "close the panel" — the classic
// Find-panel dismissal the stock utility window doesn't provide on its own.
private final class FindPanel: NSPanel {
    override func cancelOperation(_ sender: Any?) {
        performClose(sender)
    }
}
