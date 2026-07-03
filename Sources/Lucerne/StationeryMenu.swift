import AppKit
import LucerneKit

// Rebuilds File ▸ New from Stationery each time it opens: one item per `.luce`
// template in the Stationery folder (each opens as an untitled copy), a separator,
// and "Show Stationery Folder in Finder". An empty folder shows a single disabled
// hint. The templates themselves are ordinary documents — no model/format change;
// "stationery" is purely where the file lives and how it's opened.
final class StationeryMenuDelegate: NSObject, NSMenuDelegate {

    static let shared = StationeryMenuDelegate()

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let templates = LucerneDocument.stationeryTemplates()
        if templates.isEmpty {
            // action == nil ⇒ auto-disabled by NSMenu's item validation.
            menu.addItem(NSMenuItem(title: "No Stationery Yet", action: nil, keyEquivalent: ""))
        } else {
            for url in templates {
                let item = NSMenuItem(title: url.deletingPathExtension().lastPathComponent,
                                      action: #selector(openStationery(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = url
                menu.addItem(item)
            }
        }

        menu.addItem(.separator())
        let reveal = NSMenuItem(title: "Show Stationery Folder in Finder",
                                action: #selector(showStationeryFolder(_:)), keyEquivalent: "")
        reveal.target = self
        menu.addItem(reveal)
    }

    /// Open the chosen template as a brand-new untitled document, reusing the exact
    /// mechanism behind the welcome screen's "New Sample Letter" (makeUntitledDocument
    /// → load content → addDocument → make/show windows).
    @objc private func openStationery(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        let controller = NSDocumentController.shared
        guard let document = try? controller.makeUntitledDocument(ofType: LucerneUTI.document) as? LucerneDocument else {
            return
        }
        do {
            try document.loadStationery(from: url)
        } catch {
            _ = NSApp.presentError(error)
            return
        }
        controller.addDocument(document)
        document.makeWindowControllers()
        document.showWindows()
    }

    @objc private func showStationeryFolder(_ sender: Any?) {
        let url = (try? LucerneDocument.ensureStationeryDirectory())
            ?? LucerneDocument.stationeryDirectoryURL()
        _ = NSWorkspace.shared.open(url)
    }
}
