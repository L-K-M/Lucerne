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

    // MARK: - About

    @objc func showAbout(_ sender: Any?) {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "0.1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.paragraphSpacing = 6
        let credits = NSAttributedString(
            string: "A ClarisWorks-style word editor for the Mac — letters with rulers, "
                + "tabs, and genuine free placement of images.\n"
                + "Documents are saved as “.luce”, a ZIP package you can always open.",
            attributes: [
                .font: NSFont.systemFont(ofSize: 11),
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: paragraph
            ])

        var options: [NSApplication.AboutPanelOptionKey: Any] = [
            .applicationName: "Lucerne",
            .applicationVersion: version,
            .version: build,
            .credits: credits
        ]
        if let icon = NSApp.applicationIconImage { options[.applicationIcon] = icon }

        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: options)
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
