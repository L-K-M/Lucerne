import AppKit
import UniformTypeIdentifiers

public enum LucerneUTI {
    /// Must match Scripts/Info.plist (UTExportedTypeDeclarations + CFBundleDocumentTypes).
    public static let document = "ch.lkmc.lucerne.document"
    public static let fileExtension = "luce"
}

// The NSDocument for a .luce file. Reads/writes the ZIP package via LuceArchive and
// hands its model to an EditorController. Exposed to the Objective-C runtime as
// "LucerneDocument" so Info.plist's NSDocumentClass can instantiate it by name.
@objc(LucerneDocument)
public final class LucerneDocument: NSDocument, EditorControllerDocument {

    private var pendingModel: LucerneDocumentModel = DefaultDocuments.empty()
    private var pendingImages: [String: Data] = [:]
    public private(set) var editor: EditorController?

    public override init() {
        super.init()
        hasUndoManager = true
    }

    /// Used for the first-launch demo document (see AppDelegate).
    public func loadSampleContent() {
        pendingModel = DefaultDocuments.sampleLetter()
    }

    public override class var autosavesInPlace: Bool { false }

    // MARK: - Window

    public override func makeWindowControllers() {
        let editor = EditorController(model: pendingModel)
        editor.document = self
        editor.setImageData(pendingImages)
        self.editor = editor
        addWindowController(DocumentWindowController(editor: editor))
    }

    // MARK: - Reading / writing the .luce package

    public override func data(ofType typeName: String) throws -> Data {
        let model = editor?.snapshotModel() ?? pendingModel
        let images = editor?.imageData ?? pendingImages
        return try LuceArchive.write(model: model, images: images)
    }

    public override func read(from data: Data, ofType typeName: String) throws {
        let contents = try LuceArchive.read(data)
        pendingModel = contents.model
        pendingImages = contents.images
        if let editor {
            editor.load(model: contents.model)
            editor.setImageData(contents.images)
        }
    }

    // Make save/open work even when run unbundled (no Info.plist type registration).
    public override func fileNameExtension(forType typeName: String,
                                           saveOperation: NSDocument.SaveOperationType) -> String? {
        LucerneUTI.fileExtension
    }
    public override class func isNativeType(_ type: String) -> Bool { true }
    public override func writableTypes(for saveOperation: NSDocument.SaveOperationType) -> [String] {
        [LucerneUTI.document]
    }

    // Force the .luce extension in the Save panel. When the app runs unbundled the
    // UTI isn't OS-registered, so NSDocument can't infer the extension on its own;
    // we set it here (and pin the allowed type to the "luce" extension) so saved
    // files are always named "…​.luce".
    public override func prepareSavePanel(_ savePanel: NSSavePanel) -> Bool {
        savePanel.canCreateDirectories = true
        savePanel.isExtensionHidden = false
        if let type = UTType(filenameExtension: LucerneUTI.fileExtension) {
            savePanel.allowedContentTypes = [type]
        }
        let current = savePanel.nameFieldStringValue
        let base = current.isEmpty ? (displayName ?? "Untitled") : current
        let stem = (base as NSString).deletingPathExtension
        savePanel.nameFieldStringValue = stem + "." + LucerneUTI.fileExtension
        return true
    }

    // MARK: - EditorControllerDocument

    public var editorUndoManager: UndoManager? { undoManager }
    public func editorDidChange() { updateChangeCount(.changeDone) }

    // MARK: - AppleScript (see Scripts/Lucerne.sdef)

    /// The document's plain text. Setting it replaces the body with one Body
    /// paragraph per line (coarse, by design — fine formatting isn't scriptable).
    @objc public var scriptingText: String {
        get {
            editor?.textStorage.string ?? pendingModel.body.map(\.plainText).joined(separator: "\n")
        }
        set {
            var model = editor?.snapshotModel() ?? pendingModel
            let lines = newValue.isEmpty ? [""] : newValue.components(separatedBy: "\n")
            model.body = lines.map {
                Paragraph(id: IDGenerator.next("p"), style: "body", runs: [Run(text: $0)])
            }
            pendingModel = model
            editor?.load(model: model)
            updateChangeCount(.changeDone)
        }
    }

    @objc public var scriptingPageCount: Int { editor?.pageCount ?? 1 }

    // MARK: - Printing

    public override func printOperation(withSettings settings: [NSPrintInfo.AttributeKey: Any]) throws -> NSPrintOperation {
        guard let editor else { throw CocoaError(.fileReadUnknown) }
        let info = (printInfo.copy() as? NSPrintInfo) ?? NSPrintInfo.shared
        info.paperSize = editor.pageMetrics.pageSize
        info.topMargin = 0; info.bottomMargin = 0
        info.leftMargin = 0; info.rightMargin = 0
        info.horizontalPagination = .fit
        info.verticalPagination = .automatic
        info.isHorizontallyCentered = false
        info.isVerticallyCentered = false
        let view = PaginatedPrintView(pagePDFs: editor.makePagePDFs(), pageSize: editor.pageMetrics.pageSize)
        return NSPrintOperation(view: view, printInfo: info)
    }

    // MARK: - PDF export

    @objc public func exportPDF(_ sender: Any?) {
        export(data: { $0.makePDFData() }, contentType: .pdf, fileExtension: "pdf")
    }

    @objc public func exportRTF(_ sender: Any?) {
        export(data: { $0.makeRTFData() }, contentType: .rtf, fileExtension: "rtf")
    }

    private func export(data make: @escaping (EditorController) -> Data,
                        contentType: UTType, fileExtension ext: String) {
        guard let editor, let window = windowControllers.first?.window else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [contentType]
        panel.nameFieldStringValue = (displayName as NSString).deletingPathExtension + "." + ext
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try make(editor).write(to: url)
            } catch {
                NSAlert(error: error).beginSheetModal(for: window, completionHandler: nil)
            }
        }
    }
}
