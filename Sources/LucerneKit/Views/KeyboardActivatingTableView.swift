import AppKit

/// A table view that gives keyboard users the same activation affordance as a
/// click or double-click action while preserving the table's navigation keys.
///
/// Return, Space, and keypad Enter activate the selected row. Space is consumed
/// here instead of scrolling an enclosing scroll view.
///
/// Auto-repeat is intentionally ignored so holding Return or Space cannot open
/// the same document repeatedly.
public final class KeyboardActivatingTableView: NSTableView {

    private static let returnKeyCode: UInt16 = 36
    private static let spaceKeyCode: UInt16 = 49
    private static let keypadEnterKeyCode: UInt16 = 76

    public var onActivateSelection: ((Int) -> Void)?

    /// Mouse actions prefer the clicked row. Accessibility and programmatic
    /// actions have no clicked row, so they fall back to the current selection.
    public var rowForAction: Int {
        clickedRow >= 0 && clickedRow < numberOfRows ? clickedRow : selectedRow
    }

    public override func keyDown(with event: NSEvent) {
        let shortcutModifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
        let isActivationKey = event.keyCode == Self.returnKeyCode
            || event.keyCode == Self.spaceKeyCode
            || event.keyCode == Self.keypadEnterKeyCode

        guard shortcutModifiers.isEmpty,
              isActivationKey,
              !event.isARepeat,
              selectedRow >= 0 && selectedRow < numberOfRows,
              let onActivateSelection else {
            super.keyDown(with: event)
            return
        }

        onActivateSelection(selectedRow)
    }
}
