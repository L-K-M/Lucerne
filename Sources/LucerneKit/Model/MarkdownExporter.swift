import Foundation

// Derives `content.md` from the canonical model (D3). This is the write-only
// escape hatch: it is regenerated on every save and NEVER read back as authority.
// Its job is to preserve the *words and the pictures* so a future human can
// recover them with any text editor — precise placement, color, font, and exact
// size are intentionally dropped (that fidelity lives in the PDF/JSON lanes).
//
// The mapping is driven by each style's explicit `markdown` hint (never guessed
// from font size — see the plan's D3 rationale).
public enum MarkdownExporter {

    public static func export(_ model: LucerneDocumentModel) -> String {
        var blocks: [String] = []

        for paragraph in model.body {
            let style = model.resolvedStyle(for: paragraph.style)
            let inline = inlineMarkdown(for: paragraph)
            blocks.append(block(inline: inline, markdownRole: style.markdown))
        }

        // Pictures: appended after the prose. We lose their (x, y) placement here
        // by design; the loose files under images/ plus these links are enough to
        // recover the content. Ordered by (page, z) for page-anchored objects.
        let images = model.objects
            .filter { $0.type == "image" }
            .sorted { lhs, rhs in
                let lp = lhs.page ?? Int.max, rp = rhs.page ?? Int.max
                return lp != rp ? lp < rp : lhs.z < rhs.z
            }
        for object in images {
            guard let src = object.src else { continue }
            let alt = altText(for: object)
            blocks.append("![\(alt)](\(src))")
        }

        // Blocks separated by a blank line; trailing newline for a tidy file.
        return blocks.joined(separator: "\n\n") + "\n"
    }

    // MARK: - Blocks

    private static func block(inline: String, markdownRole: String) -> String {
        switch markdownRole {
        case "h1": return "# " + inline
        case "h2": return "## " + inline
        case "h3": return "### " + inline
        case "h4": return "#### " + inline
        case "li": return "- " + inline
        case "blockquote": return "> " + inline
        case "code": return "    " + inline      // indented code block
        default:   return inline                 // "p" and anything unknown
        }
    }

    // MARK: - Inline runs

    private static func inlineMarkdown(for paragraph: Paragraph) -> String {
        paragraph.runs.map(inlineMarkdown(for:)).joined()
    }

    private static func inlineMarkdown(for run: Run) -> String {
        let bold = run.bold ?? false
        let italic = run.italic ?? false
        let escaped = escape(run.text)

        guard bold || italic else { return escaped }

        // Emphasis markers can't hug whitespace ("** x **" doesn't render), so the
        // surrounding whitespace is moved outside the markers.
        let (lead, core, trail) = splitSurroundingWhitespace(escaped)
        guard !core.isEmpty else { return escaped }

        let marker = bold && italic ? "***" : (bold ? "**" : "*")
        return lead + marker + core + marker + trail
    }

    /// Splits a string into (leadingWhitespace, core, trailingWhitespace).
    private static func splitSurroundingWhitespace(_ s: String) -> (String, String, String) {
        let chars = Array(s)
        var start = 0
        var end = chars.count
        while start < end, chars[start].isWhitespace { start += 1 }
        while end > start, chars[end - 1].isWhitespace { end -= 1 }
        let lead = String(chars[0..<start])
        let core = String(chars[start..<end])
        let trail = String(chars[end..<chars.count])
        return (lead, core, trail)
    }

    /// Light, targeted escaping — enough to keep the recovery file from
    /// accidentally forming emphasis/code/links, without over-escaping prose.
    private static func escape(_ text: String) -> String {
        var out = ""
        out.reserveCapacity(text.count)
        for ch in text {
            switch ch {
            case "\\", "*", "_", "`", "[", "]":
                out.append("\\")
                out.append(ch)
            default:
                out.append(ch)
            }
        }
        return out
    }

    private static func altText(for object: PlacedObject) -> String {
        if let src = object.src {
            let name = (src as NSString).lastPathComponent
            let stem = (name as NSString).deletingPathExtension
            if !stem.isEmpty { return stem }
        }
        return object.id
    }
}
