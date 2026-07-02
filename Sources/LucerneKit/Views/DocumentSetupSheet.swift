import AppKit

// A small modal sheet for the document's margins (and room for future
// document-level settings). The page *size* is chosen in File ▸ Page Setup, which
// drives both printing and the document page size. Calls `apply` with an updated
// PageConfig (same size, new margins) when confirmed.
//
// Margins are shown in the user's ruler unit (Settings…), matching the ruler and
// the style editor; they are stored as points.
public enum DocumentSetupSheet {

    public static func present(from window: NSWindow, config: PageConfig,
                               apply: @escaping (PageConfig) -> Void) {
        let unit = Preferences.rulerUnit
        let perUnit = Double(unit.pointsPerUnit)
        let suffix = unit == .centimeters ? "cm" : "in"

        let topField = numberField(config.margins.top, perUnit: perUnit)
        let leftField = numberField(config.margins.left, perUnit: perUnit)
        let bottomField = numberField(config.margins.bottom, perUnit: perUnit)
        let rightField = numberField(config.margins.right, perUnit: perUnit)

        let foldCheckbox = NSButton(checkboxWithTitle: "Fold marks for windowed envelopes",
                                    target: nil, action: nil)
        foldCheckbox.state = (config.foldMarks == true) ? .on : .off

        func labeled(_ title: String, _ field: NSView) -> [NSView] {
            [NSTextField(labelWithString: title), field]
        }
        let grid = NSGridView(views: [
            labeled("Margin top (\(suffix)):", topField),
            labeled("Margin left (\(suffix)):", leftField),
            labeled("Margin bottom (\(suffix)):", bottomField),
            labeled("Margin right (\(suffix)):", rightField),
            labeled("", foldCheckbox)
        ])
        grid.column(at: 0).xPlacement = .trailing
        grid.rowSpacing = 8
        grid.columnSpacing = 10
        grid.translatesAutoresizingMaskIntoConstraints = true
        grid.frame = NSRect(origin: .zero, size: grid.fittingSize)

        let alert = NSAlert()
        alert.messageText = "Document Setup"
        alert.informativeText = "Margins are in \(unit.displayName.lowercased()). "
            + "Choose the page size in File ▸ Page Setup."
        alert.addButton(withTitle: "Apply")
        alert.addButton(withTitle: "Cancel")
        alert.accessoryView = grid

        alert.beginSheetModal(for: window) { response in
            guard response == .alertFirstButtonReturn else { return }
            // Fields hold the user's unit; convert back to points. The formatter
            // keeps them non-negative and rejects non-numeric input.
            var top = max(0, topField.doubleValue) * perUnit
            var left = max(0, leftField.doubleValue) * perUnit
            var bottom = max(0, bottomField.doubleValue) * perUnit
            var right = max(0, rightField.doubleValue) * perUnit
            // Keep at least 72 pt (1 inch) of writable content in each axis: if a
            // facing pair would overrun the page, scale both down proportionally so
            // their sum leaves 72 pt (preserves their ratio, deterministic).
            (left, right) = fit(left, right, within: config.width)
            (top, bottom) = fit(top, bottom, within: config.height)
            let margins = EdgeInsetsModel(top: top, left: left, bottom: bottom, right: right)
            // Store nil when off so the encoder omits foldMarks from clean files.
            apply(PageConfig(size: config.size, width: config.width, height: config.height,
                             margins: margins,
                             foldMarks: foldCheckbox.state == .on ? true : nil))
        }
    }

    /// Scales `a`/`b` down proportionally if their sum would leave less than 72 pt
    /// of content within `extent`; otherwise returns them unchanged.
    private static func fit(_ a: Double, _ b: Double, within extent: Double) -> (Double, Double) {
        let maxSum = max(0, extent - 72)
        let sum = a + b
        guard sum > maxSum, sum > 0 else { return (a, b) }
        let scale = maxSum / sum
        return (a * scale, b * scale)
    }

    private static func numberField(_ pointsValue: Double, perUnit: Double) -> NSTextField {
        let field = NSTextField()
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimum = 0
        formatter.maximumFractionDigits = 2
        formatter.usesGroupingSeparator = false
        field.formatter = formatter
        field.alignment = .right
        field.doubleValue = pointsValue / perUnit
        field.widthAnchor.constraint(equalToConstant: 90).isActive = true
        return field
    }
}
