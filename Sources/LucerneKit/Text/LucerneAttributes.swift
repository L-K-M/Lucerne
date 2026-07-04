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
    /// The *requested* font identity (family + bold/italic), stashed when the font
    /// system had to substitute (a missing family, or a trait it couldn't add).
    /// Encoded by `FontIntent`. Inert for display; the reader persists it in place
    /// of the resolved substitute so a save on a Mac lacking the font doesn't
    /// rewrite the document's font names (review 1.3).
    static let lucerneIntendedFont = NSAttributedString.Key("ch.lkmc.lucerne.intendedFont")
    /// On a document whose final paragraph is empty, these stamp the terminating
    /// newline (which otherwise carries only the *preceding* paragraph's role) with
    /// the trailing paragraph's own id and role, so the reader reconstructs it
    /// faithfully instead of inheriting the previous paragraph's style and minting a
    /// fresh id every save (review 1.8).
    static let lucerneTrailingParagraphID = NSAttributedString.Key("ch.lkmc.lucerne.trailingParagraphID")
    static let lucerneTrailingStyleRole = NSAttributedString.Key("ch.lkmc.lucerne.trailingStyleRole")
    /// A list item's membership (its `ListItemModel`, JSON-encoded by `ListItemCodec`),
    /// stamped on every character of the paragraph — including its terminating newline
    /// — so the reader reconstructs the list and the layout manager knows where to draw
    /// a marker. The visible marker itself is derived at draw time, never stored.
    static let lucerneList = NSAttributedString.Key("ch.lkmc.lucerne.list")
    /// The list membership of a trailing *empty* list item, stamped on the document's
    /// final newline (which otherwise carries only the preceding paragraph's data) —
    /// the list counterpart to `.lucerneTrailingStyleRole`.
    static let lucerneTrailingList = NSAttributedString.Key("ch.lkmc.lucerne.trailingList")
}

/// Codec for the `.lucerneIntendedFont` value: the requested family plus its
/// bold/italic intent, in one string so the builder (write) and reader (read) agree
/// on the format. The two flags lead, so a family name that itself contains "|"
/// still parses (the family is everything after the second separator).
enum FontIntent {
    static func encode(family: String, bold: Bool, italic: Bool) -> String {
        "\(bold ? 1 : 0)|\(italic ? 1 : 0)|\(family)"
    }

    static func decode(_ value: Any?) -> (family: String, bold: Bool, italic: Bool)? {
        guard let string = value as? String else { return nil }
        let parts = string.components(separatedBy: "|")
        guard parts.count >= 3 else { return nil }
        let family = parts[2...].joined(separator: "|")
        guard !family.isEmpty else { return nil }
        return (family, parts[0] == "1", parts[1] == "1")
    }
}
