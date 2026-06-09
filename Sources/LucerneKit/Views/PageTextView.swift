import AppKit

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
}
