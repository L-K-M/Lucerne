import AppKit
import LucerneKit

final class AppDelegate: NSObject, NSApplicationDelegate {

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = MainMenu.build()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.activate(ignoringOtherApps: true)
        // First launch with nothing open → show the sample letter so the defining
        // feature (live text reflow around a placed image) is visible immediately
        // (plan §6). File ▸ New creates a blank letter instead.
        DispatchQueue.main.async {
            if NSDocumentController.shared.documents.isEmpty {
                self.openSampleDocument()
            }
        }
    }

    // We open the sample ourselves, so suppress the automatic blank untitled doc.
    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool { false }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

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
