import AppKit
import LucerneKit

// The programmatic menu bar. Most items target nil (First Responder) so they route
// through the responder chain to whatever handles them: NSDocumentController
// (New/Open), the document (Save/Print/Export PDF), the text view (Cut/Copy/Undo),
// or the DocumentWindowController (formatting + image commands).
enum MainMenu {

    static func build() -> NSMenu {
        let mainMenu = NSMenu()
        mainMenu.addItem(makeAppMenu())
        mainMenu.addItem(makeFileMenu())
        mainMenu.addItem(makeEditMenu())
        mainMenu.addItem(makeFormatMenu())
        mainMenu.addItem(makeInsertMenu())
        mainMenu.addItem(makeViewMenu())
        mainMenu.addItem(makeWindowMenu())
        mainMenu.addItem(makeHelpMenu())
        return mainMenu
    }

    // MARK: - Helpers

    private static func submenu(_ title: String, _ build: (NSMenu) -> Void) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let menu = NSMenu(title: title)
        build(menu)
        item.submenu = menu
        return item
    }

    @discardableResult
    private static func add(_ menu: NSMenu, _ title: String, _ selector: String,
                            key: String = "", modifiers: NSEvent.ModifierFlags = .command,
                            symbol: String? = nil, represented: Any? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: Selector(selector), keyEquivalent: key)
        if !key.isEmpty { item.keyEquivalentModifierMask = modifiers }
        if let symbol { item.image = symbolImage(symbol) }
        item.representedObject = represented
        menu.addItem(item)
        return item
    }

    /// A small, template SF Symbol for a menu item's leading image. Used sparingly
    /// — only on the handful of high-traffic commands — so the menus stay legible
    /// rather than turning into icon soup. Template images take on the menu's own
    /// text color, so they read correctly in both light and dark menus.
    private static func symbolImage(_ name: String) -> NSImage? {
        let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
        let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(config)
        image?.isTemplate = true
        return image
    }

    // MARK: - App

    private static func makeAppMenu() -> NSMenuItem {
        submenu("Lucerne") { menu in
            add(menu, "About Lucerne", "showAbout:", key: "")
            add(menu, "Check for Updates…", "checkForUpdates:", key: "")
            menu.addItem(.separator())
            add(menu, "Settings…", "showSettings:", key: ",")
            menu.addItem(.separator())
            let services = NSMenuItem(title: "Services", action: nil, keyEquivalent: "")
            let servicesMenu = NSMenu(title: "Services")
            services.submenu = servicesMenu
            NSApp.servicesMenu = servicesMenu
            menu.addItem(services)
            menu.addItem(.separator())
            add(menu, "Hide Lucerne", "hide:", key: "h")
            add(menu, "Hide Others", "hideOtherApplications:", key: "h", modifiers: [.command, .option])
            add(menu, "Show All", "unhideAllApplications:")
            menu.addItem(.separator())
            add(menu, "Quit Lucerne", "terminate:", key: "q")
        }
    }

    // MARK: - File

    private static func makeFileMenu() -> NSMenuItem {
        submenu("File") { menu in
            add(menu, "New", "newDocument:", key: "n", symbol: "doc.badge.plus")
            add(menu, "Open…", "openDocument:", key: "o", symbol: "folder")
            let openRecent = NSMenuItem(title: "Open Recent", action: nil, keyEquivalent: "")
            let recentMenu = NSMenu(title: "Open Recent")
            recentMenu.addItem(withTitle: "Clear Menu", action: #selector(NSDocumentController.clearRecentDocuments(_:)), keyEquivalent: "")
            openRecent.submenu = recentMenu
            menu.addItem(openRecent)
            menu.addItem(.separator())
            add(menu, "Close", "performClose:", key: "w")
            add(menu, "Save…", "saveDocument:", key: "s", symbol: "square.and.arrow.down")
            add(menu, "Save As…", "saveDocumentAs:", key: "s", modifiers: [.command, .shift])
            add(menu, "Revert to Saved", "revertDocumentToSaved:")
            menu.addItem(.separator())
            add(menu, "Export as PDF…", "exportPDF:", symbol: "arrow.up.doc")
            add(menu, "Export as RTF… (lossy)", "exportRTF:")
            menu.addItem(.separator())
            add(menu, "Import Stylesheet…", "lucerneImportStylesheet:")
            add(menu, "Export Stylesheet…", "lucerneExportStylesheet:")
            menu.addItem(.separator())
            add(menu, "Document Setup…", "lucerneDocumentSetup:")
            add(menu, "Page Setup…", "runPageLayout:", key: "p", modifiers: [.command, .shift])
            add(menu, "Print…", "printDocument:", key: "p", symbol: "printer")
        }
    }

    // MARK: - Edit

    private static func makeEditMenu() -> NSMenuItem {
        submenu("Edit") { menu in
            add(menu, "Undo", "undo:", key: "z")
            add(menu, "Redo", "redo:", key: "z", modifiers: [.command, .shift])
            menu.addItem(.separator())
            add(menu, "Cut", "cut:", key: "x")
            add(menu, "Copy", "copy:", key: "c")
            add(menu, "Paste", "paste:", key: "v")
            add(menu, "Paste and Match Style", "pasteAsPlainText:", key: "v",
                modifiers: [.command, .option, .shift])
            add(menu, "Delete", "delete:", key: "")
            add(menu, "Select All", "selectAll:", key: "a")

            // Standard text transformations (nil-targeted → the first-responder text view).
            let transformations = NSMenuItem(title: "Transformations", action: nil, keyEquivalent: "")
            let transformationsMenu = NSMenu(title: "Transformations")
            add(transformationsMenu, "Make Upper Case", "uppercaseWord:")
            add(transformationsMenu, "Make Lower Case", "lowercaseWord:")
            add(transformationsMenu, "Capitalize", "capitalizeWord:")
            transformations.submenu = transformationsMenu
            menu.addItem(transformations)

            // Smart quotes/dashes, off by default (period-correct opt-in). These route to
            // DocumentWindowController, which flips the pref and re-applies it to every page.
            let substitutions = NSMenuItem(title: "Substitutions", action: nil, keyEquivalent: "")
            let substitutionsMenu = NSMenu(title: "Substitutions")
            add(substitutionsMenu, "Smart Quotes", "lucerneToggleSmartQuotes:")
            add(substitutionsMenu, "Smart Dashes", "lucerneToggleSmartDashes:")
            substitutions.submenu = substitutionsMenu
            menu.addItem(substitutions)

            menu.addItem(.separator())
            // Lucerne's own Find panel: the legacy NSTextView find panel was never
            // enabled on the page text views, and it can't navigate the one-text-
            // view-per-page layout anyway (a match may lie in another page's
            // container). These route to DocumentWindowController.
            let find = NSMenuItem(title: "Find", action: nil, keyEquivalent: "")
            let findMenu = NSMenu(title: "Find")
            add(findMenu, "Find…", "lucerneShowFindPanel:", key: "f", symbol: "magnifyingglass")
            add(findMenu, "Find Next", "lucerneFindNext:", key: "g")
            add(findMenu, "Find Previous", "lucerneFindPrevious:", key: "G")
            add(findMenu, "Use Selection for Find", "lucerneUseSelectionForFind:", key: "e")
            find.submenu = findMenu
            menu.addItem(find)
            let spelling = NSMenuItem(title: "Spelling and Grammar", action: nil, keyEquivalent: "")
            let spellingMenu = NSMenu(title: "Spelling and Grammar")
            spellingMenu.addItem(withTitle: "Show Spelling and Grammar", action: #selector(NSText.showGuessPanel(_:)), keyEquivalent: ":")
            spellingMenu.addItem(withTitle: "Check Document Now", action: #selector(NSText.checkSpelling(_:)), keyEquivalent: ";")
            spellingMenu.addItem(.separator())
            spellingMenu.addItem(withTitle: "Check Spelling While Typing",
                                 action: #selector(NSTextView.toggleContinuousSpellChecking(_:)),
                                 keyEquivalent: "")
            spelling.submenu = spellingMenu
            menu.addItem(spelling)
        }
    }

    // MARK: - Format

    private static func makeFormatMenu() -> NSMenuItem {
        submenu("Format") { menu in
            let font = NSMenuItem(title: "Font", action: nil, keyEquivalent: "")
            let fontMenu = NSMenu(title: "Font")
            // orderFrontFontPanel: lives on NSFontManager, which is not in the responder
            // chain — target it directly or the item stays permanently disabled (1.19).
            let showFonts = add(fontMenu, "Show Fonts", "orderFrontFontPanel:", key: "t")
            showFonts.target = NSFontManager.shared
            add(fontMenu, "Show Colors", "orderFrontColorPanel:", key: "C", modifiers: [.command, .shift])
            fontMenu.addItem(.separator())
            add(fontMenu, "Bold", "lucerneToggleBold:", key: "b", symbol: "bold")
            add(fontMenu, "Italic", "lucerneToggleItalic:", key: "i", symbol: "italic")
            add(fontMenu, "Underline", "lucerneToggleUnderline:", key: "u", symbol: "underline")
            font.submenu = fontMenu
            menu.addItem(font)

            let text = NSMenuItem(title: "Text", action: nil, keyEquivalent: "")
            let textMenu = NSMenu(title: "Text")
            add(textMenu, "Align Left", "lucerneAlignLeft:", key: "{")
            add(textMenu, "Center", "lucerneAlignCenter:", key: "|")
            add(textMenu, "Align Right", "lucerneAlignRight:", key: "}")
            add(textMenu, "Justify", "lucerneAlignJustify:")
            text.submenu = textMenu
            menu.addItem(text)

            let styles = NSMenuItem(title: "Paragraph Style", action: nil, keyEquivalent: "")
            // Rebuilt from the FRONT DOCUMENT's stylesheet on every open (and on
            // key-equivalent resolution) — documents define their own styles now.
            let stylesMenu = NSMenu(title: "Paragraph Style")
            stylesMenu.delegate = StyleMenuDelegate.shared
            styles.submenu = stylesMenu
            menu.addItem(styles)
            add(menu, "Style Library…", "lucerneShowStyleLibrary:", symbol: "paintpalette")

            let table = NSMenuItem(title: "Table", action: nil, keyEquivalent: "")
            let tableMenu = NSMenu(title: "Table")
            add(tableMenu, "Select Table", "lucerneSelectTable:")
            tableMenu.addItem(.separator())
            add(tableMenu, "Insert Row Above", "lucerneInsertRowAbove:")
            add(tableMenu, "Insert Row Below", "lucerneInsertRowBelow:")
            add(tableMenu, "Insert Column Before", "lucerneInsertColumnBefore:")
            add(tableMenu, "Insert Column After", "lucerneInsertColumnAfter:")
            tableMenu.addItem(.separator())
            add(tableMenu, "Merge Cells", "lucerneMergeCells:")
            add(tableMenu, "Delete Row", "lucerneDeleteRow:")
            add(tableMenu, "Delete Column", "lucerneDeleteColumn:")
            tableMenu.addItem(.separator())
            add(tableMenu, "Distribute Columns Evenly", "lucerneDistributeColumns:")
            table.submenu = tableMenu
            menu.addItem(table)
        }
    }

    // MARK: - Insert

    private static func makeInsertMenu() -> NSMenuItem {
        submenu("Insert") { menu in
            add(menu, "Image…", "lucerneInsertImage:", key: "i", modifiers: [.command, .shift], symbol: "photo")
            add(menu, "Page Break", "lucerneInsertPageBreak:", key: "\r", modifiers: [.command, .shift])
            add(menu, "Header & Footer…", "lucerneHeaderFooter:")
            add(menu, "Table…", "lucerneInsertTable:", symbol: "tablecells")
            add(menu, "Table of Contents", "lucerneTableOfContents:")
            add(menu, "Date", "lucerneInsertDate:")
            menu.addItem(.separator())
            let wrap = NSMenuItem(title: "Image Text Wrap", action: nil, keyEquivalent: "")
            let wrapMenu = NSMenu(title: "Image Text Wrap")
            add(wrapMenu, "None (Overlay)", "lucerneWrapNone:")
            add(wrapMenu, "Rectangular", "lucerneWrapRectangular:")
            wrap.submenu = wrapMenu
            menu.addItem(wrap)
            add(menu, "Increase Standoff", "lucerneStandoffIncrease:", key: "]", modifiers: [.command, .option])
            add(menu, "Decrease Standoff", "lucerneStandoffDecrease:", key: "[", modifiers: [.command, .option])
            menu.addItem(.separator())
            add(menu, "Delete Image", "lucerneDeleteImage:")
        }
    }

    // MARK: - View

    private static func makeViewMenu() -> NSMenuItem {
        submenu("View") { menu in
            add(menu, "Show Navigator", "lucerneToggleNavigator:", key: "0", modifiers: [.command, .option])
            menu.addItem(.separator())
            // "=" so plain ⌘= works on US layouts (macOS still renders it as ⌘+).
            add(menu, "Zoom In", "lucerneZoomIn:", key: "=")
            add(menu, "Zoom Out", "lucerneZoomOut:", key: "-")
            add(menu, "Actual Size", "lucerneActualSize:", key: "0")
            add(menu, "Fit Page", "lucerneZoomToFitPage:", key: "0", modifiers: [.command, .shift])
            add(menu, "Fit Width", "lucerneZoomToFitWidth:")
        }
    }

    // MARK: - Window

    private static func makeWindowMenu() -> NSMenuItem {
        let item = submenu("Window") { menu in
            add(menu, "Minimize", "performMiniaturize:", key: "m")
            add(menu, "Zoom", "performZoom:")
            menu.addItem(.separator())
            add(menu, "Bring All to Front", "arrangeInFront:")
        }
        NSApp.windowsMenu = item.submenu
        return item
    }

    // MARK: - Help

    private static func makeHelpMenu() -> NSMenuItem {
        let item = submenu("Help") { menu in
            add(menu, "Lucerne Help", "showLucerneHelp:", key: "?")
        }
        // Assigning helpMenu gives us macOS's built-in menu-item search field.
        NSApp.helpMenu = item.submenu
        return item
    }
}
