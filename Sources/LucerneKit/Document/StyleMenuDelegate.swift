import AppKit

// Rebuilds Format ▸ Paragraph Style from the FRONT DOCUMENT's stylesheet each
// time the menu opens (or AppKit resolves a key equivalent), retiring the old
// hardcoded role list (STYLES.md Phase 1). ⌃⌘1…⌃⌘9 follow the first nine styles
// in list order, so reordering promotes a style onto a shortcut.
public final class StyleMenuDelegate: NSObject, NSMenuDelegate {

    public static let shared = StyleMenuDelegate()

    public func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let wc = FloatingPalette.activeDocumentWindowController()
        let styles = wc?.editor.model.styles ?? DefaultDocuments.defaultStyles()

        for (index, role) in LucerneDocumentModel.orderedStyleRoles(in: styles).enumerated() {
            let item = NSMenuItem(title: styles[role]?.name ?? role,
                                  action: #selector(DocumentWindowController.lucerneApplyStyle(_:)),
                                  keyEquivalent: index < 9 ? "\(index + 1)" : "")
            if index < 9 { item.keyEquivalentModifierMask = [.command, .control] }
            item.representedObject = role
            menu.addItem(item)
        }

        menu.addItem(.separator())
        let currentName = wc?.editor.currentStyleRole().flatMap { styles[$0]?.name }
        add(menu, "New Style from Selection…",
            #selector(DocumentWindowController.lucerneNewStyleFromSelection(_:)))
        add(menu, currentName.map { "Redefine “\($0)” from Selection" } ?? "Redefine Style from Selection",
            #selector(DocumentWindowController.lucerneRedefineStyleFromSelection(_:)))
        add(menu, currentName.map { "Save “\($0)” to Library" } ?? "Save Style to Library",
            #selector(DocumentWindowController.lucerneSaveStyleToLibrary(_:)))
        menu.addItem(.separator())
        add(menu, "Style Settings…",
            #selector(DocumentWindowController.lucerneStyleSettings(_:)))
    }

    private func add(_ menu: NSMenu, _ title: String, _ action: Selector) {
        menu.addItem(NSMenuItem(title: title, action: action, keyEquivalent: ""))
    }
}
