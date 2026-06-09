import AppKit

// NSAttributedString → [Paragraph]. The inverse of AttributedStringBuilder, run on
// save to fold the live text storage back into the canonical model. It reads each
// paragraph's style *role* from `.lucerneStyleRole` (so structure is known, not
// guessed) and stores only the run/paragraph attributes that *differ* from that
// role's defaults — keeping document.json small and intent-revealing.
public enum AttributedStringReader {

    private static let eps = 0.01

    public static func paragraphs(from attr: NSAttributedString,
                                  styles: [String: ParagraphStyleDef]) -> [Paragraph] {
        let model = StyleLookup(styles: styles)
        let ns = attr.string as NSString
        let length = ns.length
        if length == 0 { return [emptyParagraph(role: defaultRole(in: styles))] }

        var paragraphs: [Paragraph] = []
        var location = 0
        while location < length {
            var start = 0, end = 0, contentsEnd = 0
            ns.getParagraphStart(&start, end: &end, contentsEnd: &contentsEnd,
                                 for: NSRange(location: location, length: 0))
            let contentRange = NSRange(location: start, length: contentsEnd - start)
            paragraphs.append(buildParagraph(from: attr, contentRange: contentRange, styles: model))
            if end == location { break }              // guard against non-advancing ranges
            location = end
        }

        // A text storage ending in a newline shows a trailing empty paragraph the
        // loop above stops short of; reconstruct it, inheriting the final newline's
        // role so "press return at the end" persists.
        let last = ns.character(at: length - 1)
        if last == 0x0A || last == 0x0D {
            let role = (attr.attribute(.lucerneStyleRole, at: length - 1, effectiveRange: nil) as? String)
                ?? defaultRole(in: styles)
            let ps = attr.attribute(.paragraphStyle, at: length - 1, effectiveRange: nil) as? NSParagraphStyle
            paragraphs.append(emptyParagraph(role: role, paragraphStyle: ps, styleDef: model.resolved(role)))
        }
        return paragraphs
    }

    // MARK: - Per-paragraph

    private static func buildParagraph(from attr: NSAttributedString,
                                       contentRange: NSRange,
                                       styles: StyleLookup) -> Paragraph {
        let length = (attr.string as NSString).length
        let probe = contentRange.length > 0 ? contentRange.location
                                            : min(contentRange.location, max(0, length - 1))

        let role = (attr.attribute(.lucerneStyleRole, at: probe, effectiveRange: nil) as? String)
            ?? styles.defaultRole
        let id = (attr.attribute(.lucerneParagraphID, at: probe, effectiveRange: nil) as? String)
            ?? IDGenerator.next("p")
        let styleDef = styles.resolved(role)
        let ps = attr.attribute(.paragraphStyle, at: probe, effectiveRange: nil) as? NSParagraphStyle

        var paragraph = emptyParagraph(role: role, paragraphStyle: ps, styleDef: styleDef)
        paragraph.id = id

        if contentRange.length > 0 {
            paragraph.runs = runs(from: attr, in: contentRange, styleDef: styleDef)
        }
        return paragraph
    }

    private static func emptyParagraph(role: String,
                                       paragraphStyle ps: NSParagraphStyle? = nil,
                                       styleDef: ParagraphStyleDef? = nil) -> Paragraph {
        var p = Paragraph(id: IDGenerator.next("p"), style: role, runs: [Run(text: "")])
        if let ps, let styleDef {
            applyParagraphOverrides(from: ps, styleDef: styleDef, into: &p)
        }
        return p
    }

    // MARK: - Runs

    private static func runs(from attr: NSAttributedString,
                             in range: NSRange,
                             styleDef: ParagraphStyleDef) -> [Run] {
        var runs: [Run] = []
        attr.enumerateAttributes(in: range, options: []) { attrs, runRange, _ in
            let text = (attr.string as NSString).substring(with: runRange)
            guard !text.isEmpty else { return }
            runs.append(makeRun(text: text, attrs: attrs, styleDef: styleDef))
        }
        return runs.isEmpty ? [Run(text: "")] : mergeAdjacent(runs)
    }

    private static func makeRun(text: String,
                                attrs: [NSAttributedString.Key: Any],
                                styleDef: ParagraphStyleDef) -> Run {
        var run = Run(text: text)

        let font = (attrs[.font] as? NSFont) ?? NSFont.systemFont(ofSize: 12)
        let isBold = FontResolver.isBold(font)
        let isItalic = FontResolver.isItalic(font)
        if isBold != (styleDef.bold ?? false) { run.bold = isBold }
        if isItalic != (styleDef.italic ?? false) { run.italic = isItalic }

        let family = font.familyName ?? font.fontName
        if family != (styleDef.font ?? "Helvetica") { run.font = family }

        let size = Double(font.pointSize)
        if abs(size - (styleDef.size ?? 12)) > eps { run.size = size }

        if let underline = attrs[.underlineStyle] as? Int, underline != 0 {
            run.underline = true
        }

        if let color = attrs[.foregroundColor] as? NSColor {
            let hex = color.lucerneHexString
            let styleHex = styleDef.color.flatMap { NSColor(hexString: $0)?.lucerneHexString } ?? "#000000"
            if hex.caseInsensitiveCompare(styleHex) != .orderedSame { run.color = hex }
        }
        return run
    }

    /// Coalesce neighbouring runs whose overrides are identical (the text system
    /// can split runs on attributes we don't model).
    private static func mergeAdjacent(_ runs: [Run]) -> [Run] {
        var merged: [Run] = []
        for run in runs {
            if var last = merged.last, sameFormatting(last, run) {
                last.text += run.text
                merged[merged.count - 1] = last
            } else {
                merged.append(run)
            }
        }
        return merged
    }

    private static func sameFormatting(_ a: Run, _ b: Run) -> Bool {
        a.bold == b.bold && a.italic == b.italic && a.underline == b.underline
            && a.font == b.font && a.size == b.size && a.color == b.color
    }

    // MARK: - Paragraph attribute overrides

    private static func applyParagraphOverrides(from ps: NSParagraphStyle,
                                                styleDef: ParagraphStyleDef,
                                                into p: inout Paragraph) {
        // Alignment
        if let alignString = AttributedStringBuilder.alignmentString(from: ps.alignment),
           alignString != styleDef.alignment {
            p.align = alignString
        }

        // Indents
        let left = Double(ps.headIndent)
        let firstExtra = Double(ps.firstLineHeadIndent - ps.headIndent)
        let right = ps.tailIndent < 0 ? Double(-ps.tailIndent) : 0
        let leftOverride = differs(left, styleDef.leftIndent ?? 0) ? left : nil
        let firstOverride = differs(firstExtra, styleDef.firstLineIndent ?? 0) ? firstExtra : nil
        let rightOverride = differs(right, 0) ? right : nil
        if leftOverride != nil || firstOverride != nil || rightOverride != nil {
            p.indent = IndentModel(left: leftOverride, right: rightOverride, firstLine: firstOverride)
        }

        // Spacing
        if ps.lineHeightMultiple > 0,
           differs(Double(ps.lineHeightMultiple), styleDef.lineSpacing ?? 0) {
            p.lineSpacing = Double(ps.lineHeightMultiple)
        }
        if differs(Double(ps.paragraphSpacing), styleDef.spaceAfter ?? 0) {
            p.spaceAfter = Double(ps.paragraphSpacing)
        }
        if differs(Double(ps.paragraphSpacingBefore), styleDef.spaceBefore ?? 0) {
            p.spaceBefore = Double(ps.paragraphSpacingBefore)
        }

        // Tab stops (empty == none, by construction in the builder)
        let tabs = ps.tabStops.map(tabModel(from:))
        if !tabs.isEmpty { p.tabStops = tabs }
    }

    private static func tabModel(from tab: NSTextTab) -> TabStopModel {
        if tab.options[.columnTerminators] != nil {
            return TabStopModel(pos: Double(tab.location), type: "decimal")
        }
        switch tab.alignment {
        case .center: return TabStopModel(pos: Double(tab.location), type: "center")
        case .right:  return TabStopModel(pos: Double(tab.location), type: "right")
        default:      return TabStopModel(pos: Double(tab.location), type: "left")
        }
    }

    private static func differs(_ a: Double, _ b: Double) -> Bool { abs(a - b) > eps }

    private static func defaultRole(in styles: [String: ParagraphStyleDef]) -> String {
        styles[LucerneDocumentModel.defaultStyleRole] != nil
            ? LucerneDocumentModel.defaultStyleRole
            : (styles.keys.sorted().first ?? LucerneDocumentModel.defaultStyleRole)
    }

    // Small helper bundling the style table with its fallbacks.
    private struct StyleLookup {
        let styles: [String: ParagraphStyleDef]
        var defaultRole: String { AttributedStringReader.defaultRole(in: styles) }
        func resolved(_ role: String) -> ParagraphStyleDef {
            styles[role] ?? styles[LucerneDocumentModel.defaultStyleRole] ?? .fallbackBody
        }
    }
}
