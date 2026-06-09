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
                            represented: Any? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: Selector(selector), keyEquivalent: key)
        if !key.isEmpty { item.keyEquivalentModifierMask = modifiers }
        item.representedObject = represented
        menu.addItem(item)
        return item
    }

    // MARK: - App

    private static func makeAppMenu() -> NSMenuItem {
        submenu("Lucerne") { menu in
            add(menu, "About Lucerne", "showAbout:", key: "")
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
            add(menu, "New", "newDocument:", key: "n")
            let open = add(menu, "Open…", "openDocument:", key: "o")
            let openRecent = NSMenuItem(title: "Open Recent", action: nil, keyEquivalent: "")
            let recentMenu = NSMenu(title: "Open Recent")
            recentMenu.addItem(withTitle: "Clear Menu", action: #selector(NSDocumentController.clearRecentDocuments(_:)), keyEquivalent: "")
            openRecent.submenu = recentMenu
            menu.addItem(openRecent)
            _ = open
            menu.addItem(.separator())
            add(menu, "Close", "performClose:", key: "w")
            add(menu, "Save…", "saveDocument:", key: "s")
            add(menu, "Save As…", "saveDocumentAs:", key: "s", modifiers: [.command, .shift])
            add(menu, "Revert to Saved", "revertDocumentToSaved:")
            menu.addItem(.separator())
            add(menu, "Export as PDF…", "exportPDF:")
            add(menu, "Export as RTF…  (lossy)", "exportRTF:")
            menu.addItem(.separator())
            add(menu, "Document Setup…", "lucerneDocumentSetup:")
            add(menu, "Page Setup…", "runPageLayout:", key: "p", modifiers: [.command, .shift])
            add(menu, "Print…", "printDocument:", key: "p")
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
            add(menu, "Delete", "delete:", key: "")
            add(menu, "Select All", "selectAll:", key: "a")
            menu.addItem(.separator())
            let find = NSMenuItem(title: "Find", action: nil, keyEquivalent: "")
            let findMenu = NSMenu(title: "Find")
            let findAction = #selector(NSTextView.performFindPanelAction(_:))
            let findItem = findMenu.addItem(withTitle: "Find…", action: findAction, keyEquivalent: "f")
            findItem.tag = 1   // NSFindPanelActionShowFindPanel
            findMenu.addItem(withTitle: "Find Next", action: findAction, keyEquivalent: "g").tag = 2
            findMenu.addItem(withTitle: "Find Previous", action: findAction, keyEquivalent: "G").tag = 3
            find.submenu = findMenu
            menu.addItem(find)
            let spelling = NSMenuItem(title: "Spelling and Grammar", action: nil, keyEquivalent: "")
            let spellingMenu = NSMenu(title: "Spelling and Grammar")
            spellingMenu.addItem(withTitle: "Show Spelling and Grammar", action: #selector(NSText.showGuessPanel(_:)), keyEquivalent: ":")
            spellingMenu.addItem(withTitle: "Check Document Now", action: #selector(NSText.checkSpelling(_:)), keyEquivalent: ";")
            spelling.submenu = spellingMenu
            menu.addItem(spelling)
        }
    }

    // MARK: - Format

    private static func makeFormatMenu() -> NSMenuItem {
        submenu("Format") { menu in
            let font = NSMenuItem(title: "Font", action: nil, keyEquivalent: "")
            let fontMenu = NSMenu(title: "Font")
            add(fontMenu, "Show Fonts", "orderFrontFontPanel:", key: "t")
            add(fontMenu, "Show Colors", "orderFrontColorPanel:", key: "C", modifiers: [.command, .shift])
            fontMenu.addItem(.separator())
            add(fontMenu, "Bold", "lucerneToggleBold:", key: "b")
            add(fontMenu, "Italic", "lucerneToggleItalic:", key: "i")
            add(fontMenu, "Underline", "lucerneToggleUnderline:", key: "u")
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
            let stylesMenu = NSMenu(title: "Paragraph Style")
            let defs = DefaultDocuments.defaultStyles()
            for (index, role) in DefaultDocuments.styleRoleOrder.enumerated() {
                let name = defs[role]?.name ?? role
                let key = index < 9 ? "\(index + 1)" : ""
                add(stylesMenu, name, "lucerneApplyStyle:", key: key,
                    modifiers: [.command, .control], represented: role)
            }
            styles.submenu = stylesMenu
            menu.addItem(styles)
        }
    }

    // MARK: - Insert

    private static func makeInsertMenu() -> NSMenuItem {
        submenu("Insert") { menu in
            add(menu, "Image…", "lucerneInsertImage:", key: "i", modifiers: [.command, .shift])
            add(menu, "Page Break", "lucerneInsertPageBreak:", key: "\r", modifiers: [.command, .shift])
            add(menu, "Page Number", "lucerneInsertPageNumber:")
            add(menu, "Header & Footer…", "lucerneHeaderFooter:")
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
            add(menu, "Zoom In", "lucerneZoomIn:", key: "+")
            add(menu, "Zoom Out", "lucerneZoomOut:", key: "-")
            add(menu, "Actual Size", "lucerneActualSize:", key: "0")
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
}
