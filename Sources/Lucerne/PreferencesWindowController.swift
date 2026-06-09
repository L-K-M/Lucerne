import AppKit
import LucerneKit

// The Settings window. Small for now: the ruler unit. Writes through to
// `Preferences`, which posts a change notification so open rulers refresh live.
final class PreferencesWindowController: NSWindowController {

    private let unitPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let updatesCheckbox = NSButton(checkboxWithTitle: "Automatically check for updates",
                                           target: nil, action: nil)
    private var updateChecker: UpdateChecker?

    convenience init(updateChecker: UpdateChecker) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 180),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Settings"
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .aqua)
        self.init(window: window)
        self.updateChecker = updateChecker
        buildContent()
        window.center()
    }

    private func buildContent() {
        guard let content = window?.contentView else { return }

        let label = NSTextField(labelWithString: "Ruler units:")
        label.alignment = .right

        for unit in RulerUnit.allCases { unitPopup.addItem(withTitle: unit.displayName) }
        if let index = RulerUnit.allCases.firstIndex(of: Preferences.rulerUnit) {
            unitPopup.selectItem(at: index)
        }
        unitPopup.target = self
        unitPopup.action = #selector(unitChanged)

        let row = NSStackView(views: [label, unitPopup])
        row.orientation = .horizontal
        row.spacing = 8
        label.widthAnchor.constraint(equalToConstant: 90).isActive = true

        let note = NSTextField(labelWithString: "Affects the document ruler. New documents default to centimeters.")
        note.font = .systemFont(ofSize: 11)
        note.textColor = .secondaryLabelColor

        updatesCheckbox.state = (updateChecker?.automaticChecksEnabled ?? true) ? .on : .off
        updatesCheckbox.target = self
        updatesCheckbox.action = #selector(toggleAutoUpdate)

        let stack = NSStackView(views: [row, note, updatesCheckbox])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerYAnchor.constraint(equalTo: content.centerYAnchor),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -24)
        ])
    }

    @objc private func unitChanged() {
        let index = unitPopup.indexOfSelectedItem
        guard RulerUnit.allCases.indices.contains(index) else { return }
        Preferences.rulerUnit = RulerUnit.allCases[index]
    }

    @objc private func toggleAutoUpdate(_ sender: NSButton) {
        updateChecker?.automaticChecksEnabled = (sender.state == .on)
    }
}
