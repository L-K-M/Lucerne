import AppKit

// Draws list markers (bullets and numbers) in the hanging-indent gutter to the left
// of each list item's text. The marker is NOT part of the text storage — it can't be
// selected, deleted, or land in the run model — so Lucerne's clean model↔storage
// correspondence is preserved. What a marker *shows* is derived from the run of items
// around it (an ordered item's number depends on its neighbours), recomputed here at
// draw time via `ListMarkers`, so numbering is always live: insert or delete an item
// and the rest renumber on the next redraw.
//
// Because one layout manager is shared by every page's text view, this draws through
// the normal on-screen and PDF/print paths alike, so markers appear wherever the body
// does. (RTF/DOCX interchange serialises attributes, not drawing, so list markers are
// dropped there — consistent with those exports already dropping images: they are the
// lossy lanes; the .luce package, Markdown, and PDF carry lists faithfully.)
final class ListMarkerLayoutManager: NSLayoutManager {

    override func drawGlyphs(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        super.drawGlyphs(forGlyphRange: glyphsToShow, at: origin)
        drawListMarkers(forGlyphRange: glyphsToShow, at: origin)
    }

    // MARK: - Marker drawing

    private func drawListMarkers(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        guard let storage = textStorage else { return }
        let ns = storage.string as NSString
        let container = drawingContainer(forGlyphRange: glyphsToShow)

        if ns.length > 0, glyphsToShow.length > 0, let container {
            let charRange = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
            let clampedStart = min(max(0, charRange.location), ns.length - 1)
            let firstParagraph = paragraphStartIndex(for: clampedStart, ns: ns)
            // Numbering an item needs the whole run before it, so scan from the list's
            // start (which may be above the visible area) through the drawn range.
            let groupStart = listGroupStart(fromParagraphStart: firstParagraph, storage: storage, ns: ns)
            let scanEnd = min(NSMaxRange(charRange), ns.length)

            var starts: [Int] = []
            var items: [ListItemModel?] = []
            var location = groupStart
            while location < ns.length {
                var start = 0, end = 0, contentsEnd = 0
                ns.getParagraphStart(&start, end: &end, contentsEnd: &contentsEnd,
                                     for: NSRange(location: location, length: 0))
                starts.append(start)
                items.append(listItem(atParagraphStart: start, storage: storage, ns: ns))
                if start >= scanEnd { break }        // covered the drawn range
                if end == location { break }          // guard against non-advancing ranges
                location = end
            }

            let resolved = ListMarkers.resolve(items)
            for (index, start) in starts.enumerated() {
                guard index < resolved.count, let marker = resolved[index], !marker.text.isEmpty,
                      let level = listItem(atParagraphStart: start, storage: storage, ns: ns)?.level
                else { continue }
                drawMarker(marker.text, level: level, paragraphStart: start,
                           storage: storage, container: container, origin: origin)
            }
        }

        drawTrailingListMarker(storage: storage, ns: ns, container: container, origin: origin)
    }

    /// Draws one marker for the paragraph beginning at `paragraphStart`, aligned to the
    /// baseline of its first line — but only when that first line is laid out in the
    /// container currently being drawn (a paragraph split across a page break has its
    /// first line, and thus its marker, on the earlier page).
    private func drawMarker(_ text: String, level: Int, paragraphStart: Int,
                            storage: NSTextStorage, container: NSTextContainer, origin: NSPoint) {
        guard paragraphStart < storage.length else { return }
        let glyphIndex = glyphIndexForCharacter(at: paragraphStart)
        guard glyphIndex < numberOfGlyphs else { return }
        guard textContainer(forGlyphAt: glyphIndex, effectiveRange: nil) === container else { return }

        let lineRect = lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
        let baselineY = origin.y + lineRect.minY + location(forGlyphAt: glyphIndex).y
        let probe = markerProbeIndex(paragraphStart, storage: storage)
        let font = (storage.attribute(.font, at: probe, effectiveRange: nil) as? NSFont)
            ?? NSFont.systemFont(ofSize: 12)
        let color = (storage.attribute(.foregroundColor, at: probe, effectiveRange: nil) as? NSColor)
            ?? .textColor
        drawMarkerText(text, font: font, color: color, level: level, baselineY: baselineY, origin: origin)
    }

    /// The trailing empty list item (a document ending in an empty bullet, e.g. right
    /// after Return) has no character of its own — its marker draws against the extra
    /// line fragment, using the membership stamped on the final newline.
    private func drawTrailingListMarker(storage: NSTextStorage, ns: NSString,
                                        container: NSTextContainer?, origin: NSPoint) {
        let length = ns.length
        guard length > 0 else { return }
        let last = ns.character(at: length - 1)
        guard last == 0x0A || last == 0x0D else { return }
        guard let item = ListItemCodec.decode(
            storage.attribute(.lucerneTrailingList, at: length - 1, effectiveRange: nil)) else { return }
        guard let extraContainer = extraLineFragmentTextContainer,
              container == nil || extraContainer === container else { return }
        let rect = extraLineFragmentRect
        guard rect.height > 0 else { return }
        guard let text = trailingMarkerText(item: item, storage: storage, ns: ns), !text.isEmpty else { return }

        let font = (storage.attribute(.font, at: length - 1, effectiveRange: nil) as? NSFont)
            ?? NSFont.systemFont(ofSize: 12)
        let color = (storage.attribute(.foregroundColor, at: length - 1, effectiveRange: nil) as? NSColor)
            ?? .textColor
        // No glyph to query for a baseline; approximate from the fragment top + ascent.
        let baselineY = origin.y + rect.minY + font.ascender
        drawMarkerText(text, font: font, color: color, level: item.level,
                       baselineY: baselineY, origin: origin)
    }

    /// Draws the marker string right-aligned in the gutter that ends `markerGap` points
    /// before the level's text indent, with its baseline on `baselineY`. In the text
    /// view's flipped coordinates a string draws from its top-left, so the top sits an
    /// ascent above the baseline.
    private func drawMarkerText(_ text: String, font: NSFont, color: NSColor,
                                level: Int, baselineY: CGFloat, origin: NSPoint) {
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let string = NSAttributedString(string: text, attributes: attrs)
        let size = string.size()
        let contentIndent = CGFloat(ListGeometry.contentIndent(level: level))
        let rightEdge = origin.x + contentIndent - CGFloat(ListGeometry.markerGap)
        let x = max(origin.x, rightEdge - size.width)   // never spill past the left margin
        string.draw(at: NSPoint(x: x, y: baselineY - font.ascender))
    }

    // MARK: - List traversal helpers

    private func drawingContainer(forGlyphRange glyphsToShow: NSRange) -> NSTextContainer? {
        if glyphsToShow.length > 0, glyphsToShow.location < numberOfGlyphs {
            return textContainer(forGlyphAt: glyphsToShow.location, effectiveRange: nil)
        }
        return extraLineFragmentTextContainer
    }

    /// The list membership of the paragraph starting at `paragraphStart`, probing its
    /// first character (or, for an empty paragraph, its terminating newline).
    private func listItem(atParagraphStart paragraphStart: Int,
                          storage: NSTextStorage, ns: NSString) -> ListItemModel? {
        let probe = markerProbeIndex(paragraphStart, storage: storage)
        guard probe < storage.length else { return nil }
        return ListItemCodec.decode(storage.attribute(.lucerneList, at: probe, effectiveRange: nil))
    }

    /// The index to read a paragraph's attributes at: its first character, or — for an
    /// empty paragraph, whose start already sits on the terminating newline — that
    /// newline, which carries the paragraph's own attributes.
    private func markerProbeIndex(_ paragraphStart: Int, storage: NSTextStorage) -> Int {
        min(max(0, paragraphStart), max(0, storage.length - 1))
    }

    private func paragraphStartIndex(for index: Int, ns: NSString) -> Int {
        var start = 0, end = 0, contentsEnd = 0
        ns.getParagraphStart(&start, end: &end, contentsEnd: &contentsEnd,
                             for: NSRange(location: index, length: 0))
        return start
    }

    /// Walks backward from a list paragraph to the first paragraph of its contiguous
    /// same-id run (numbering resets there). Returns `paragraphStart` unchanged when it
    /// isn't a list item.
    private func listGroupStart(fromParagraphStart paragraphStart: Int,
                                storage: NSTextStorage, ns: NSString) -> Int {
        guard let item = listItem(atParagraphStart: paragraphStart, storage: storage, ns: ns) else {
            return paragraphStart
        }
        var start = paragraphStart
        while start > 0 {
            var prevStart = 0, prevEnd = 0, prevContentsEnd = 0
            ns.getParagraphStart(&prevStart, end: &prevEnd, contentsEnd: &prevContentsEnd,
                                 for: NSRange(location: start - 1, length: 0))
            guard let prev = listItem(atParagraphStart: prevStart, storage: storage, ns: ns),
                  prev.list == item.list else { break }
            start = prevStart
        }
        return start
    }

    /// Resolves the marker for a trailing empty list item by numbering the run of real
    /// items that precede it plus the item itself.
    private func trailingMarkerText(item: ListItemModel, storage: NSTextStorage, ns: NSString) -> String? {
        let length = ns.length
        var lastStart = 0, lastEnd = 0, lastContentsEnd = 0
        ns.getParagraphStart(&lastStart, end: &lastEnd, contentsEnd: &lastContentsEnd,
                             for: NSRange(location: length - 1, length: 0))

        var items: [ListItemModel?] = []
        if let lastReal = listItem(atParagraphStart: lastStart, storage: storage, ns: ns),
           lastReal.list == item.list {
            let groupStart = listGroupStart(fromParagraphStart: lastStart, storage: storage, ns: ns)
            var location = groupStart
            while location <= lastStart, location < length {
                var start = 0, end = 0, contentsEnd = 0
                ns.getParagraphStart(&start, end: &end, contentsEnd: &contentsEnd,
                                     for: NSRange(location: location, length: 0))
                items.append(listItem(atParagraphStart: start, storage: storage, ns: ns))
                if start == lastStart || end == location { break }
                location = end
            }
        }
        items.append(item)   // the trailing empty item resolves last
        guard let resolved = ListMarkers.resolve(items).last, let marker = resolved else { return nil }
        return marker.text
    }
}
