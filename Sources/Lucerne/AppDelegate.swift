import AppKit
import LucerneKit

final class AppDelegate: NSObject, NSApplicationDelegate {

    private let updateChecker = UpdateChecker(
        configuration: .init(owner: "L-K-M", repo: "Lucerne", appName: "Lucerne")
    )

    func applicationWillFinishLaunching(_ notification: Notification) {
        // A brand-new style library starts with the curated starter collection
        // (STYLES.md S6). Before the menu and before any document exists, so
        // the very first letter already seeds from it.
        StyleLibrary.shared.seedStarterLibraryIfNeeded()
        // Pin the whole app to the light (aqua) appearance so alerts, the font/color
        // panels, and open/save panels match the aqua-pinned document windows even in
        // Dark Mode (4.5). The per-window pins stay as belt-and-braces.
        NSApp.appearance = NSAppearance(named: .aqua)
        NSApp.mainMenu = MainMenu.build()
    }

    private var welcomeWindowController: WelcomeWindowController?
    private var isTerminating = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.activate(ignoringOtherApps: true)
        updateChecker.start()   // check GitHub for a newer release on launch + daily
        observeDocumentWindowClose()
        observeDocumentWindowArrival()
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

    // Set the guard without overriding applicationShouldTerminate, so NSDocumentController
    // still reviews unsaved changes on quit. This fires late — after the save-review sheet
    // on a ⌘Q — so the deferred welcome check below also re-reads isTerminating to avoid
    // popping the welcome window mid-quit. (The review-sheet path can still race in theory;
    // we accept that rather than override applicationShouldTerminate, which would take over
    // the unsaved-changes review.)
    func applicationWillTerminate(_ notification: Notification) {
        isTerminating = true
    }

    /// When the last document window closes (and we're not quitting), bring the
    /// start screen back — the natural "home" to return to, like the welcome shown
    /// at launch.
    private func observeDocumentWindowClose() {
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: nil, queue: .main) { [weak self] note in
                guard let self, !self.isTerminating,
                      let window = note.object as? NSWindow,
                      window.delegate is DocumentWindowController else { return }
                // Defer so the document has deregistered before we check the count, and
                // re-check isTerminating — termination can begin between this notification
                // and the deferred block running (1.33).
                DispatchQueue.main.async { [weak self] in
                    guard let self, !self.isTerminating else { return }
                    self.showWelcomeIfNoDocuments()
                }
            }
    }

    /// A document window became main (⌘N, Open, Open Recent, sample, or a Finder
    /// double-click all land here) — the welcome screen has done its job, so dismiss
    /// it. The controller is kept for reuse when the last window closes again (5.7).
    private func observeDocumentWindowArrival() {
        NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeMainNotification, object: nil, queue: .main) { [weak self] note in
                guard let self,
                      let window = note.object as? NSWindow,
                      window.delegate is DocumentWindowController else { return }
                self.welcomeWindowController?.close()
            }
    }

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
            controller.onOpenRecent = { [weak self] url in
                NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, error in
                    // A moved/renamed recent otherwise fails silently, leaving no
                    // windows; surface the error and keep the welcome screen (1.20).
                    if let error {
                        _ = NSApp.presentError(error)
                        self?.showWelcome()
                    }
                }
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

    // MARK: - Settings

    private var preferencesWindowController: PreferencesWindowController?

    @objc func showSettings(_ sender: Any?) {
        if preferencesWindowController == nil {
            preferencesWindowController = PreferencesWindowController(updateChecker: updateChecker)
        }
        NSApp.activate(ignoringOtherApps: true)
        preferencesWindowController?.showWindow(nil)
        preferencesWindowController?.window?.makeKeyAndOrderFront(nil)
    }

    // MARK: - Style Library

    // On the app delegate (the responder chain's end) so Format ▸ Style Library…
    // works with no documents open — the library is app-level, not per-document.
    @objc func lucerneShowStyleLibrary(_ sender: Any?) {
        StyleLibraryWindowController.shared.show()
    }

    // MARK: - Updates

    @objc func checkForUpdates(_ sender: Any?) {
        updateChecker.checkNow()
    }

    // MARK: - Help

    @objc func showLucerneHelp(_ sender: Any?) {
        guard let url = URL(string: "https://github.com/L-K-M/Lucerne#readme") else { return }
        _ = NSWorkspace.shared.open(url)
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
