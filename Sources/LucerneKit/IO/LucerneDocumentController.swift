import AppKit
import UniformTypeIdentifiers

// A document controller that knows Lucerne's single document type even when the
// app is run unbundled (no Info.plist). The first NSDocumentController created in
// a process becomes the shared one, so AppDelegate instantiates this early.
public final class LucerneDocumentController: NSDocumentController {

    public override init() {
        super.init()
        // With autosavesInPlace=false (the classic dot-and-prompt model), AppKit's
        // only crash safety for a *titled* document with unsaved edits is periodic
        // autosave-elsewhere, driven by this delay (default 0 = off). 30s enables
        // autosave to ~/Library/Autosave Information WITHOUT changing the save-prompt
        // or unsaved-changes-dot behaviour at all (1.4).
        autosavingDelay = 30
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        autosavingDelay = 30
    }

    public override var defaultType: String? { LucerneUTI.document }

    public override func documentClass(forType typeName: String) -> AnyClass? {
        LucerneDocument.self
    }

    public override func runModalOpenPanel(_ openPanel: NSOpenPanel, forTypes types: [String]?) -> Int {
        if let type = UTType(filenameExtension: LucerneUTI.fileExtension) {
            openPanel.allowedContentTypes = [type]
        }
        return super.runModalOpenPanel(openPanel, forTypes: [LucerneUTI.document])
    }
}
