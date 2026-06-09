import AppKit

// A small modal sheet for editing the document's page size and margins. Calls
// `apply` with the new PageConfig when the user confirms. Presented from the
// window controller; applies via EditorController.updatePageConfig.
public enum DocumentSetupSheet {

    public static func present(from window: NSWindow, config: PageConfig,
                               apply: @escaping (PageConfig) -> Void) {
        let sizePopup = NSPopUpButton(frame: .zero, pullsDown: false)
        sizePopup.addItems(withTitles: ["A4", "Letter", "Custom"])
        switch config.size.lowercased() {
        case "a4": sizePopup.selectItem(withTitle: "A4")
        case "letter": sizePopup.selectItem(withTitle: "Letter")
        default: sizePopup.selectItem(withTitle: "Custom")
        }

        let widthField = numberField(config.width)
        let heightField = numberField(config.height)
        let topField = numberField(config.margins.top)
        let leftField = numberField(config.margins.left)
        let bottomField = numberField(config.margins.bottom)
        let rightField = numberField(config.margins.right)

        func labeled(_ title: String, _ field: NSView) -> [NSView] {
            [NSTextField(labelWithString: title), field]
        }
        let grid = NSGridView(views: [
            labeled("Page size:", sizePopup),
            labeled("Width (pt):", widthField),
            labeled("Height (pt):", heightField),
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
        alert.informativeText = "Page size and margins are in points (72 pt = 1 inch). "
            + "Width and height apply when the size is Custom."
        alert.addButton(withTitle: "Apply")
        alert.addButton(withTitle: "Cancel")
        alert.accessoryView = grid

        alert.beginSheetModal(for: window) { response in
            guard response == .alertFirstButtonReturn else { return }
            let sizeTitle = sizePopup.titleOfSelectedItem ?? "A4"
            let width: Double, height: Double, sizeKey: String
            switch sizeTitle {
            case "Letter": sizeKey = "Letter"; width = 612; height = 792
            case "Custom": sizeKey = "custom"
                width = max(72, widthField.doubleValue)
                height = max(72, heightField.doubleValue)
            default: sizeKey = "A4"; width = 595.28; height = 841.89
            }
            let margins = EdgeInsetsModel(top: max(0, topField.doubleValue),
                                          left: max(0, leftField.doubleValue),
                                          bottom: max(0, bottomField.doubleValue),
                                          right: max(0, rightField.doubleValue))
            apply(PageConfig(size: sizeKey, width: width, height: height, margins: margins))
        }
    }

    private static func numberField(_ value: Double) -> NSTextField {
        let field = NSTextField(string: String(format: "%g", value))
        field.alignment = .right
        field.widthAnchor.constraint(equalToConstant: 90).isActive = true
        return field
    }
}
