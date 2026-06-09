import AppKit

// A small modal sheet for the document's margins (and room for future
// document-level settings). The page *size* is chosen in File ▸ Page Setup, which
// drives both printing and the document page size. Calls `apply` with an updated
// PageConfig (same size, new margins) when confirmed.
public enum DocumentSetupSheet {

    public static func present(from window: NSWindow, config: PageConfig,
                               apply: @escaping (PageConfig) -> Void) {
        let topField = numberField(config.margins.top)
        let leftField = numberField(config.margins.left)
        let bottomField = numberField(config.margins.bottom)
        let rightField = numberField(config.margins.right)

        func labeled(_ title: String, _ field: NSView) -> [NSView] {
            [NSTextField(labelWithString: title), field]
        }
        let grid = NSGridView(views: [
            labeled("Margin top:", topField),
            labeled("Margin left:", leftField),
            labeled("Margin bottom:", bottomField),
            labeled("Margin right:", rightField)
        ])
        grid.column(at: 0).xPlacement = .trailing
        grid.rowSpacing = 8
        grid.columnSpacing = 10
        grid.translatesAutoresizingMaskIntoConstraints = true
        grid.frame = NSRect(origin: .zero, size: grid.fittingSize)

        let alert = NSAlert()
        alert.messageText = "Document Setup"
        alert.informativeText = "Margins are in points (72 pt = 1 inch). "
            + "Choose the page size in File ▸ Page Setup."
        alert.addButton(withTitle: "Apply")
        alert.addButton(withTitle: "Cancel")
        alert.accessoryView = grid

        alert.beginSheetModal(for: window) { response in
            guard response == .alertFirstButtonReturn else { return }
            let margins = EdgeInsetsModel(top: max(0, topField.doubleValue),
                                          left: max(0, leftField.doubleValue),
                                          bottom: max(0, bottomField.doubleValue),
                                          right: max(0, rightField.doubleValue))
            apply(PageConfig(size: config.size, width: config.width, height: config.height, margins: margins))
        }
    }

    private static func numberField(_ value: Double) -> NSTextField {
        let field = NSTextField(string: String(format: "%g", value))
        field.alignment = .right
        field.widthAnchor.constraint(equalToConstant: 90).isActive = true
        return field
    }
}
