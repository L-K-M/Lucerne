import AppKit
import UniformTypeIdentifiers

// One NSTextView per page. All page text views share a single NSLayoutManager and
// NSTextStorage (constructed by EditorController), which is what makes text flow
// from one page into the next. Constructing the view with an explicit container
// keeps it on the TextKit 1 path (see AGENTS.md ▸ "Why TextKit 1").
public final class PageTextView: NSTextView {

    public weak var editor: EditorController?

    public override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        if ok { editor?.textViewBecameActive(self) }
        return ok
    }

    // A click in the text deselects any selected floating image so the two
    // selection models don't fight.
    public override func mouseDown(with event: NSEvent) {
        editor?.deselectAllImages()
        super.mouseDown(with: event)
    }

    // MARK: - Image drag & drop

    // Dropping an image (a file or image data) creates a free-placed floating image
    // at the drop point, instead of NSTextView inserting the path/attachment into
    // the text. Non-image drags fall through to the normal text behavior.

    public override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        Self.hasImage(sender.draggingPasteboard) ? .copy : super.draggingEntered(sender)
    }

    public override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        Self.hasImage(sender.draggingPasteboard) ? .copy : super.draggingUpdated(sender)
    }

    public override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        Self.hasImage(sender.draggingPasteboard) ? true : super.prepareForDragOperation(sender)
    }

    public override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let (data, name) = Self.imagePayload(from: sender.draggingPasteboard) else {
            return super.performDragOperation(sender)
        }
        let pageView = superview as? PageContainerView
        let pagePoint = (pageView ?? self).convert(sender.draggingLocation, from: nil)
        editor?.insertImage(data: data, suggestedName: name,
                            onPage: pageView?.pageIndex ?? 0, centeredAt: pagePoint)
        return true
    }

    private static func hasImage(_ pasteboard: NSPasteboard) -> Bool {
        let urlOptions: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true,
            .urlReadingContentsConformToTypes: [UTType.image.identifier]
        ]
        if pasteboard.canReadObject(forClasses: [NSURL.self], options: urlOptions) { return true }
        return pasteboard.canReadObject(forClasses: [NSImage.self], options: nil)
    }

    /// Returns (original bytes, suggested filename) for a dropped image, preferring
    /// the original file bytes (lossless) over a re-encode.
    private static func imagePayload(from pasteboard: NSPasteboard) -> (Data, String)? {
        let urlOptions: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true,
            .urlReadingContentsConformToTypes: [UTType.image.identifier]
        ]
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: urlOptions) as? [URL],
           let url = urls.first, let data = try? Data(contentsOf: url) {
            return (data, url.lastPathComponent)
        }
        if let image = NSImage(pasteboard: pasteboard), let data = image.pngData() {
            return (data, "image.png")
        }
        return nil
    }
}
