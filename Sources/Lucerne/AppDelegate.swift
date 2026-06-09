import AppKit
import LucerneKit

final class AppDelegate: NSObject, NSApplicationDelegate {

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = MainMenu.build()
    }

    private var welcomeWindowController: WelcomeWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.activate(ignoringOtherApps: true)
        // Let macOS restore/recover documents first; if nothing opened, show the
        // welcome screen (recent documents + New/Open/Sample). The small delay lets
        // window/draft restoration settle so we don't show it alongside a restored doc.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            self?.showWelcomeIfNoDocuments()
        }
    }

    // We manage the start experience ourselves, so suppress the auto blank untitled doc.
    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool { false }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    // Clicking the Dock icon with no windows open → show the welcome screen.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag, NSDocumentController.shared.documents.isEmpty { showWelcome() }
        return true
    }

    // MARK: - Welcome

    private func showWelcomeIfNoDocuments() {
        guard NSDocumentController.shared.documents.isEmpty else { return }
        showWelcome()
    }

    private func showWelcome() {
        if welcomeWindowController == nil {
            let controller = WelcomeWindowController()
            controller.onNew = { NSDocumentController.shared.newDocument(nil) }
            controller.onOpen = { NSDocumentController.shared.openDocument(nil) }
            controller.onSample = { [weak self] in self?.openSampleDocument() }
            controller.onOpenRecent = { url in
                NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, _ in }
            }
            welcomeWindowController = controller
        }
        welcomeWindowController?.refreshRecents()
        NSApp.activate(ignoringOtherApps: true)
        welcomeWindowController?.showWindow(nil)
        welcomeWindowController?.window?.makeKeyAndOrderFront(nil)
    }

    // MARK: - About

    private var aboutWindowController: AboutWindowController?

    @objc func showAbout(_ sender: Any?) {
        if aboutWindowController == nil { aboutWindowController = AboutWindowController() }
        NSApp.activate(ignoringOtherApps: true)
        aboutWindowController?.showWindow(nil)
        aboutWindowController?.window?.makeKeyAndOrderFront(nil)
    }

    private func openSampleDocument() {
        let controller = NSDocumentController.shared
        guard let document = try? controller.makeUntitledDocument(ofType: LucerneUTI.document) as? LucerneDocument else {
            return
        }
        document.loadSampleContent()
        controller.addDocument(document)
        document.makeWindowControllers()
        document.showWindows()
    }
}
