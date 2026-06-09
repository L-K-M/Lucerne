import AppKit

// Model → NSAttributedString. Produces the text storage contents for the layout
// engine. Paragraphs are joined by "\n" (the separator carries the preceding
// paragraph's attributes). Each character carries:
//   • font / foregroundColor / underline   — from the run, over the style
//   • paragraphStyle                        — alignment, indents, spacing, tabs
//   • .lucerneStyleRole / .lucerneParagraphID — so structure survives round-trips
public enum AttributedStringBuilder {

    public static func attributedString(for model: LucerneDocumentModel) -> NSAttributedString {
        let out = NSMutableAttributedString()
        var pageBreakStarts: [Int] = []
        for (index, paragraph) in model.body.enumerated() {
            let style = model.resolvedStyle(for: paragraph.style)
            let paragraphStyle = makeParagraphStyle(paragraph, style: style)
            let start = out.length
            appendRuns(of: paragraph, style: style, paragraphStyle: paragraphStyle, into: out)
            if index < model.body.count - 1 {
                let sep = runAttributes(Run(text: "\n"), style: style,
                                        paragraphStyle: paragraphStyle,
                                        role: paragraph.style, paragraphID: paragraph.id)
                out.append(NSAttributedString(string: "\n", attributes: sep))
            }
            if paragraph.pageBreakBefore == true, start < out.length { pageBreakStarts.append(start) }
        }
        // Flag the first character of each page-break paragraph (a one-char run
        // split that AttributedStringReader.mergeAdjacent re-coalesces on read).
        for location in pageBreakStarts where location < out.length {
            out.addAttribute(.lucernePageBreakBefore, value: true,
                             range: NSRange(location: location, length: 1))
        }
        return out
    }

    /// Attributes a brand-new typed character should inherit for a given role —
    /// used as the text view's typing attributes so new text picks up the style.
    public static func typingAttributes(role: String, in model: LucerneDocumentModel,
                                        paragraphID: String) -> [NSAttributedString.Key: Any] {
        let style = model.resolvedStyle(for: role)
        let ps = makeParagraphStyle(Paragraph(id: paragraphID, style: role, runs: []), style: style)
        return runAttributes(Run(text: ""), style: style, paragraphStyle: ps,
                             role: role, paragraphID: paragraphID)
    }

    // MARK: - Runs

    private static func appendRuns(of paragraph: Paragraph,
                                   style: ParagraphStyleDef,
                                   paragraphStyle: NSParagraphStyle,
                                   into out: NSMutableAttributedString) {
        // An empty paragraph contributes no characters; its formatting still lives
        // on the separator "\n" (or, for the last paragraph, on the typing
        // attributes once the user starts typing).
        for run in paragraph.runs where !run.text.isEmpty {
            let attrs = runAttributes(run, style: style, paragraphStyle: paragraphStyle,
                                      role: paragraph.style, paragraphID: paragraph.id)
            out.append(NSAttributedString(string: run.text, attributes: attrs))
        }
    }

    private static func runAttributes(_ run: Run,
                                      style: ParagraphStyleDef,
                                      paragraphStyle: NSParagraphStyle,
                                      role: String,
                                      paragraphID: String) -> [NSAttributedString.Key: Any] {
        let bold = run.bold ?? style.bold ?? false
        let italic = run.italic ?? style.italic ?? false
        let family = run.font ?? style.font ?? "Helvetica"
        let size = CGFloat(run.size ?? style.size ?? 12)
        let font = FontResolver.font(family: family, size: size, bold: bold, italic: italic)

        let colorHex = run.color ?? style.color
        let color = colorHex.flatMap { NSColor(hexString: $0) } ?? .black

        var attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraphStyle,
            .lucerneStyleRole: role,
            .lucerneParagraphID: paragraphID
        ]
        if run.underline ?? false {
            attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue
        }
        return attrs
    }

    // MARK: - Paragraph style

    static func makeParagraphStyle(_ paragraph: Paragraph, style: ParagraphStyleDef) -> NSParagraphStyle {
        let ps = NSMutableParagraphStyle()
        ps.alignment = alignment(from: paragraph.align ?? style.alignment)

        if let mult = paragraph.lineSpacing ?? style.lineSpacing { ps.lineHeightMultiple = CGFloat(mult) }
        ps.paragraphSpacing = CGFloat(paragraph.spaceAfter ?? style.spaceAfter ?? 0)
        ps.paragraphSpacingBefore = CGFloat(paragraph.spaceBefore ?? style.spaceBefore ?? 0)

        let left = CGFloat(paragraph.indent?.left ?? style.leftIndent ?? 0)
        let firstExtra = CGFloat(paragraph.indent?.firstLine ?? style.firstLineIndent ?? 0)
        let right = CGFloat(paragraph.indent?.right ?? 0)
        ps.headIndent = left
        ps.firstLineHeadIndent = left + firstExtra
        ps.tailIndent = right > 0 ? -right : 0      // negative == inset from the right edge

        // Always set the tab array explicitly (empty when the paragraph has no
        // custom tabs) so the reader can treat "empty" as "no custom tabs" instead
        // of inheriting NSParagraphStyle's built-in default stops.
        ps.tabStops = (paragraph.tabStops?.map(makeTab)) ?? []
        ps.defaultTabInterval = 36
        return ps
    }

    static func alignment(from string: String?) -> NSTextAlignment {
        switch string {
        case "center": return .center
        case "right": return .right
        case "justified": return .justified
        case "left": return .left
        default: return .natural
        }
    }

    static func alignmentString(from alignment: NSTextAlignment) -> String? {
        switch alignment {
        case .center: return "center"
        case .right: return "right"
        case .justified: return "justified"
        case .left: return "left"
        default: return nil               // .natural → omit (use the style default)
        }
    }

    private static func makeTab(_ tab: TabStopModel) -> NSTextTab {
        let loc = CGFloat(tab.pos)
        switch tab.kind {
        case .left:   return NSTextTab(textAlignment: .left, location: loc)
        case .center: return NSTextTab(textAlignment: .center, location: loc)
        case .right:  return NSTextTab(textAlignment: .right, location: loc)
        case .decimal:
            let sep = Locale.current.decimalSeparator ?? "."
            let terminators = CharacterSet(charactersIn: sep)
            return NSTextTab(textAlignment: .right, location: loc,
                             options: [.columnTerminators: terminators])
        }
    }
}
