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

        // Walk the flat paragraph list; a run of consecutive cell paragraphs
        // sharing a `table` id (spec §6.7) is emitted as one GFM pipe table
        // instead of degrading into disconnected one-line paragraphs.
        let body = model.body
        var i = 0
        while i < body.count {
            let paragraph = body[i]
            if let tableID = paragraph.cell?.table {
                var group: [Paragraph] = []
                while i < body.count, body[i].cell?.table == tableID {
                    group.append(body[i])
                    i += 1
                }
                blocks.append(tableBlock(for: group, model: model))
                continue
            }
            let style = model.resolvedStyle(for: paragraph.style)
            let inline = inlineMarkdown(for: paragraph)
            blocks.append(block(inline: inline, markdownRole: style.markdown))
            i += 1
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
        default:   return blockEscape(inline)    // "p" and anything unknown
        }
    }

    // MARK: - Tables

    /// Renders a run of cell paragraphs sharing a `table` id as a GFM pipe table.
    /// Cells are placed row-major by their `(row, column)`; the grid dimensions are
    /// *derived* from the cells (spec §6.7 — the table stores no explicit counts).
    private static func tableBlock(for cells: [Paragraph], model: LucerneDocumentModel) -> String {
        var columnCount = 0
        var rowCount = 0
        for paragraph in cells {
            guard let cell = paragraph.cell else { continue }
            columnCount = max(columnCount, cell.column + max(cell.columnSpan, 1))
            rowCount = max(rowCount, cell.row + max(cell.rowSpan, 1))
        }
        // Degenerate (no positive extent) — fall back to plain paragraph blocks.
        guard columnCount > 0, rowCount > 0 else {
            return cells.map {
                block(inline: inlineMarkdown(for: $0),
                      markdownRole: model.resolvedStyle(for: $0.style).markdown)
            }.joined(separator: "\n\n")
        }

        // Row-major grid; a spanning cell's text lands in its origin position and
        // the positions it covers stay empty (GFM can't express spans, so we pad).
        var grid = Array(repeating: Array(repeating: "", count: columnCount), count: rowCount)
        for paragraph in cells {
            guard let cell = paragraph.cell,
                  cell.row >= 0, cell.row < rowCount,
                  cell.column >= 0, cell.column < columnCount else { continue }
            grid[cell.row][cell.column] = tableCellText(for: paragraph)
        }

        // GFM requires a header row followed by a delimiter row. The model has no
        // header flag, so — by convention — row 0 is used as the header and a
        // matching `---` separator is emitted beneath it.
        var lines: [String] = []
        lines.append(rowLine(grid[0]))
        lines.append(rowLine(Array(repeating: "---", count: columnCount)))
        for row in grid.dropFirst() {
            lines.append(rowLine(row))
        }
        return lines.joined(separator: "\n")
    }

    private static func rowLine(_ cellsText: [String]) -> String {
        "| " + cellsText.joined(separator: " | ") + " |"
    }

    /// A cell's inline text (emphasis only — cells are an inline context, so block
    /// prefixes don't apply), with `|` escaped so it can't split the cell.
    private static func tableCellText(for paragraph: Paragraph) -> String {
        inlineMarkdown(for: paragraph).replacingOccurrences(of: "|", with: "\\|")
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

    /// Block-level escaping for the plain-paragraph path (1.27): the inline
    /// escaper handles emphasis/link characters, but a paragraph whose rendered
    /// text *starts* with a Markdown block marker (`# `, `>`, `- `, `+ `, `1. `,
    /// four leading spaces, or a lone `---`/`===`) would otherwise change
    /// structure in the recovery file. Neutralize just the leading marker with a
    /// backslash so the words survive as prose. (`*` is already inline-escaped.)
    private static func blockEscape(_ line: String) -> String {
        let chars = Array(line)

        // Indented code block: 4+ leading spaces. Trim to 3 (the most Markdown
        // tolerates before a block marker) and re-check the de-indented remainder.
        var start = 0
        while start < chars.count, chars[start] == " " { start += 1 }
        if start >= 4 {
            return "   " + blockEscape(String(chars[start...]))
        }

        let indent = String(chars[0..<start])
        let rest = Array(chars[start...])
        guard let first = rest.first else { return line }

        // Thematic break / setext underline: the whole line is only "-" (3+) or
        // "=" (any run). A lone "-" / "--" is left alone (not a construct).
        if (first == "-" || first == "="),
           rest.allSatisfy({ $0 == first }),
           (first == "=" || rest.count >= 3) {
            return indent + "\\" + String(rest)
        }

        // ATX heading: 1–6 "#" then a space.
        if first == "#" {
            var hashes = 0
            while hashes < rest.count, rest[hashes] == "#" { hashes += 1 }
            if hashes <= 6, hashes < rest.count, rest[hashes] == " " {
                return indent + "\\" + String(rest)
            }
        }

        // Blockquote.
        if first == ">" {
            return indent + "\\" + String(rest)
        }

        // Bullet list: "- " or "+ " ("*" is already escaped inline).
        if (first == "-" || first == "+"), rest.count >= 2, rest[1] == " " {
            return indent + "\\" + String(rest)
        }

        // Ordered list: digits then ". " or ") ". Escape the delimiter, keeping
        // the digits ("1. x" → "1\. x").
        if first.isNumber {
            var digits = 0
            while digits < rest.count, rest[digits].isNumber { digits += 1 }
            if digits + 1 < rest.count,
               rest[digits] == "." || rest[digits] == ")",
               rest[digits + 1] == " " {
                return indent + String(rest[0..<digits]) + "\\" + String(rest[digits...])
            }
        }

        return line
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
