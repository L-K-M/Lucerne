import AppKit

// Custom attributed-string keys. The crucial one is `.lucerneStyleRole`: it pins a
// paragraph's named style role ("body", "heading1", …) onto its characters so the
// role survives the round-trip through NSTextStorage and back into the model. We
// therefore *know* a paragraph is a heading on save instead of guessing from
// "18pt bold" (see plan D3).
public extension NSAttributedString.Key {
    static let lucerneStyleRole = NSAttributedString.Key("ch.lkmc.lucerne.styleRole")
    static let lucerneParagraphID = NSAttributedString.Key("ch.lkmc.lucerne.paragraphID")
    /// Marks the first character of a paragraph that must start on a new page.
    static let lucernePageBreakBefore = NSAttributedString.Key("ch.lkmc.lucerne.pageBreakBefore")
}
