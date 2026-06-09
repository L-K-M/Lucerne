import AppKit

// A sheet for editing the running header and footer (three zones each) and where
// page numbering starts. Zones may contain the tokens {page}, {pages}, {date},
// {title}. Calls `apply` with the new header/footer (nil when a band is entirely
// empty) and the 1-based page on which numbering begins (nil when it's the default
// page 1).
public enum HeaderFooterSheet {

    public static func present(from window: NSWindow,
                               header: PageFurniture?, footer: PageFurniture?,
                               pageNumberStart: Int,
                               apply: @escaping (PageFurniture?, PageFurniture?, Int?) -> Void) {
        let h = header ?? PageFurniture()
        let f = footer ?? PageFurniture()
        let headerLeft = field(h.left), headerCenter = field(h.center), headerRight = field(h.right)
        let footerLeft = field(f.left), footerCenter = field(f.center), footerRight = field(f.right)

        let startField = NSTextField(string: "\(max(1, pageNumberStart))")
        startField.widthAnchor.constraint(equalToConstant: 56).isActive = true
        let startFormatter = NumberFormatter()
        startFormatter.minimum = 1
        startFormatter.allowsFloats = false
        startField.formatter = startFormatter
        startField.alignment = .right

        func label(_ s: String) -> NSTextField { NSTextField(labelWithString: s) }
        let grid = NSGridView(views: [
            [label(""), label("Left"), label("Center"), label("Right")],
            [label("Header:"), headerLeft, headerCenter, headerRight],
            [label("Footer:"), footerLeft, footerCenter, footerRight],
            [label("Numbered from page:"), startField]
        ])
        grid.column(at: 0).xPlacement = .trailing
        grid.rowSpacing = 8
        grid.columnSpacing = 8
        grid.translatesAutoresizingMaskIntoConstraints = true
        grid.frame = NSRect(origin: .zero, size: grid.fittingSize)

        let alert = NSAlert()
        alert.messageText = "Header & Footer"
        alert.informativeText = "Each zone may use the tokens {page}, {pages}, {date}, and {title} — "
            + "for example a centered footer of “Page {page} of {pages}”. "
            + "“Numbered from page” is the first page that counts as page 1 "
            + "(set 3 to skip a title page and a contents page); earlier pages are unnumbered."
        alert.addButton(withTitle: "Apply")
        alert.addButton(withTitle: "Cancel")
        alert.accessoryView = grid

        alert.beginSheetModal(for: window) { response in
            guard response == .alertFirstButtonReturn else { return }
            let newHeader = PageFurniture(left: headerLeft.stringValue,
                                          center: headerCenter.stringValue,
                                          right: headerRight.stringValue)
            let newFooter = PageFurniture(left: footerLeft.stringValue,
                                          center: footerCenter.stringValue,
                                          right: footerRight.stringValue)
            let start = max(1, Int(startField.stringValue) ?? 1)
            apply(newHeader.isEmpty ? nil : newHeader,
                  newFooter.isEmpty ? nil : newFooter,
                  start > 1 ? start : nil)
        }
    }

    private static func field(_ value: String) -> NSTextField {
        let field = NSTextField(string: value)
        field.widthAnchor.constraint(equalToConstant: 130).isActive = true
        field.placeholderString = "—"
        return field
    }
}
