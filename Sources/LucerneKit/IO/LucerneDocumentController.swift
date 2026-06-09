import AppKit
import UniformTypeIdentifiers

// A document controller that knows Lucerne's single document type even when the
// app is run unbundled (no Info.plist). The first NSDocumentController created in
// a process becomes the shared one, so AppDelegate instantiates this early.
public final class LucerneDocumentController: NSDocumentController {

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
