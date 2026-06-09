import AppKit

// A small sheet asking for the number of rows and columns, then calls `apply`.
public enum TableInsertSheet {

    public static func present(from window: NSWindow, apply: @escaping (Int, Int) -> Void) {
        let rows = numberField(3)
        let columns = numberField(3)

        func label(_ s: String) -> NSTextField { NSTextField(labelWithString: s) }
        let grid = NSGridView(views: [
            [label("Rows:"), rows],
            [label("Columns:"), columns]
        ])
        grid.column(at: 0).xPlacement = .trailing
        grid.rowSpacing = 8
        grid.columnSpacing = 8
        grid.translatesAutoresizingMaskIntoConstraints = true
        grid.frame = NSRect(origin: .zero, size: grid.fittingSize)

        let alert = NSAlert()
        alert.messageText = "Insert Table"
        alert.informativeText = "Choose the table size. Click a cell to type; the table reflows "
            + "with the text and breaks across pages as needed."
        alert.addButton(withTitle: "Insert")
        alert.addButton(withTitle: "Cancel")
        alert.accessoryView = grid

        alert.beginSheetModal(for: window) { response in
            guard response == .alertFirstButtonReturn else { return }
            let r = max(1, min(50, Int(rows.stringValue) ?? 3))
            let c = max(1, min(20, Int(columns.stringValue) ?? 3))
            apply(r, c)
        }
    }

    private static func numberField(_ value: Int) -> NSTextField {
        let field = NSTextField(string: "\(value)")
        field.widthAnchor.constraint(equalToConstant: 56).isActive = true
        field.alignment = .right
        let formatter = NumberFormatter()
        formatter.minimum = 1
        formatter.allowsFloats = false
        field.formatter = formatter
        return field
    }
}
