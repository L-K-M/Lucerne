import LucerneCore
import AppKit

/// Converts rich pasteboard content to the subset the Lucerne model can save.
/// Normalizing before insertion keeps the page honest: formatting shown after a
/// paste is the same formatting that survives save and reopen.
enum PasteNormalizer {
    private enum RichTextKind {
        case rtf
        case rtfd
        case html
    }

    private static let legacyRTF = NSPasteboard.PasteboardType(
        "NeXT Rich Text Format v1.0 pasteboard type")
    private static let legacyRTFD = NSPasteboard.PasteboardType(
        "NeXT RTFD pasteboard type")
    private static let legacyHTML = NSPasteboard.PasteboardType(
        "Apple HTML pasteboard type")
    private static let flatRTFD = NSPasteboard.PasteboardType("com.apple.flat-rtfd")

    struct Replacement {
        let range: NSRange
        let content: NSAttributedString
        let caretLocation: Int
    }

    static func supports(_ type: NSPasteboard.PasteboardType) -> Bool {
        richTextKind(for: type) != nil
    }

    static func read(from pasteboard: NSPasteboard,
                     type: NSPasteboard.PasteboardType) -> NSAttributedString? {
        guard let kind = richTextKind(for: type) else { return nil }
        let candidates: [NSPasteboard.PasteboardType]
        let documentType: NSAttributedString.DocumentType
        switch kind {
        case .rtf:
            candidates = [type, .rtf, legacyRTF]
            documentType = .rtf
        case .html:
            candidates = [type, .html, legacyHTML]
            documentType = .html
        case .rtfd:
            candidates = [type, .rtfd, flatRTFD, legacyRTFD]
            documentType = .rtfd
        }
        guard let data = candidates.lazy.compactMap({ pasteboard.data(forType: $0) }).first else {
            return nil
        }
        return try? NSAttributedString(
            data: data, options: [.documentType: documentType],
            documentAttributes: nil)
    }

    private static func richTextKind(
        for type: NSPasteboard.PasteboardType
    ) -> RichTextKind? {
        switch type {
        case .rtf, legacyRTF:
            return .rtf
        case .rtfd, flatRTFD, legacyRTFD:
            return .rtfd
        case .html, legacyHTML:
            return .html
        default:
            return nil
        }
    }

    static func normalize(_ source: NSAttributedString,
                          destination: [NSAttributedString.Key: Any],
                          model: LucerneDocumentModel) -> NSAttributedString {
        let cleanedSource = source.mutableCopy() as? NSMutableAttributedString
            ?? NSMutableAttributedString(attributedString: source)
        removeAttachments(from: cleanedSource)
        canonicalizeNewlines(in: cleanedSource)
        guard cleanedSource.length > 0 else { return NSAttributedString() }

        let destinationParagraphStyle = destination[.paragraphStyle] as? NSParagraphStyle
        let list = ListItemCodec.decode(destination[.lucerneList])
        let result = NSMutableAttributedString(string: cleanedSource.string)
        cleanedSource.enumerateAttributes(
            in: NSRange(location: 0, length: cleanedSource.length), options: []
        ) { attributes, range, _ in
            result.setAttributes(
                representableAttributes(from: attributes,
                                        destinationParagraphStyle: destinationParagraphStyle,
                                        destinationList: list),
                range: range)
        }

        let role = (destination[.lucerneStyleRole] as? String)
            .flatMap { model.styles[$0] == nil ? nil : $0 }
            ?? LucerneDocumentModel.defaultStyleRole
        let firstID = (destination[.lucerneParagraphID] as? String)
            .flatMap { $0.isEmpty ? nil : $0 }
            ?? IDGenerator.next("p")
        let pageBreakBefore = (destination[.lucernePageBreakBefore] as? Bool) == true
        applyStructure(to: result, role: role, firstID: firstID, list: list,
                       pageBreakBefore: pageBreakBefore)
        return result
    }

    /// Include the untouched end of a joined paragraph in the replacement. That
    /// keeps its paragraph identity and style consistent with the last pasted
    /// paragraph, and makes undo restore both text and structural attributes.
    static func replacement(_ normalized: NSAttributedString,
                            for selection: NSRange,
                            in storage: NSAttributedString) -> Replacement {
        let caretLocation = selection.location + normalized.length
        let selectionEnd = NSMaxRange(selection)
        let hasFollowingContent = selectionEnd < storage.length
        let normalizedEndsInNewline = normalized.length > 0
            && (normalized.string as NSString).character(at: normalized.length - 1) == 0x0A
        let followingStartsParagraph = hasFollowingContent
            && paragraphStart(at: selectionEnd, in: storage.string) == selectionEnd
        let content = NSMutableAttributedString(attributedString: normalized)

        // Trailing keys describe an empty paragraph at the end of the document.
        // They are temporary when existing text follows the paste.
        if normalizedEndsInNewline, hasFollowingContent {
            removeTrailingStructure(fromTerminatorIn: content)
        }
        // Inserting complete paragraphs at the start of an existing paragraph must
        // not borrow that untouched paragraph's identity or page-break marker.
        if normalizedEndsInNewline, followingStartsParagraph, selection.length == 0 {
            detachFirstParagraph(in: content)
        }

        let selectionContainsBreak = (storage.string as NSString).range(
            of: "\n", options: [], range: selection).location != NSNotFound
        let pasteContainsBreak = normalized.string.contains("\n")
        guard selectionContainsBreak || pasteContainsBreak,
              !(normalizedEndsInNewline && followingStartsParagraph),
              let continuationRange = continuationRange(after: selection, in: storage) else {
            return Replacement(range: selection, content: content,
                               caretLocation: caretLocation)
        }

        let continuation = NSMutableAttributedString(
            attributedString: storage.attributedSubstring(from: continuationRange))
        let structure = finalParagraphAttributes(in: normalized)
        let wholeContinuation = NSRange(location: 0, length: continuation.length)
        for key in [NSAttributedString.Key.lucerneParagraphID,
                    .lucerneStyleRole, .lucerneList, .lucernePageBreakBefore,
                    .paragraphStyle] {
            continuation.removeAttribute(key, range: wholeContinuation)
        }
        continuation.addAttributes(structure, range: wholeContinuation)

        content.append(continuation)

        return Replacement(
            range: NSRange(location: selection.location,
                           length: selection.length + continuationRange.length),
            content: content,
            caretLocation: caretLocation)
    }

    private static func representableAttributes(
        from source: [NSAttributedString.Key: Any],
        destinationParagraphStyle: NSParagraphStyle?,
        destinationList: ListItemModel?
    ) -> [NSAttributedString.Key: Any] {
        let sourceFont = source[.font] as? NSFont ?? NSFont.systemFont(ofSize: 12)
        let size = min(max(sourceFont.pointSize.isFinite ? sourceFont.pointSize : 12, 1), 512)
        let font = NSFontManager.shared.convert(sourceFont, toSize: size)

        let sourceColor = source[.foregroundColor] as? NSColor ?? .black
        let converted = sourceColor.usingColorSpace(.sRGB) ?? .black
        let color = NSColor(srgbRed: converted.redComponent,
                            green: converted.greenComponent,
                            blue: converted.blueComponent, alpha: 1)

        let sourceStyle = source[.paragraphStyle] as? NSParagraphStyle
            ?? destinationParagraphStyle ?? NSParagraphStyle.default
        let paragraphStyle = cleanParagraphStyle(sourceStyle,
                                                 fallback: destinationParagraphStyle)
        if let destinationList {
            AttributedStringBuilder.applyListIndent(to: paragraphStyle,
                                                     level: destinationList.level)
        }
        var result: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraphStyle
        ]
        let underline = (source[.underlineStyle] as? NSNumber)?.intValue
            ?? (source[.underlineStyle] as? Int) ?? 0
        if underline != 0 {
            result[.underlineStyle] = NSUnderlineStyle.single.rawValue
        }
        if FontIntent.decode(source[.lucerneIntendedFont]) != nil {
            result[.lucerneIntendedFont] = source[.lucerneIntendedFont]
        }
        return result
    }

    private static func cleanParagraphStyle(_ source: NSParagraphStyle,
                                            fallback: NSParagraphStyle?) -> NSMutableParagraphStyle {
        let clean = NSMutableParagraphStyle()
        switch source.alignment {
        case .left, .center, .right, .justified:
            clean.alignment = source.alignment
        default:
            clean.alignment = fallback?.alignment ?? .natural
        }
        let lineHeight = finite(source.lineHeightMultiple, fallback: 0,
                                range: 0...100)
        clean.lineHeightMultiple = lineHeight > 0 ? lineHeight
            : finite(fallback?.lineHeightMultiple ?? 0, fallback: 0, range: 0...100)
        clean.paragraphSpacing = finite(source.paragraphSpacing, fallback: 0,
                                        range: 0...10_000)
        clean.paragraphSpacingBefore = finite(source.paragraphSpacingBefore, fallback: 0,
                                              range: 0...10_000)

        let geometry = (!source.textLists.isEmpty || !source.textBlocks.isEmpty)
            ? (fallback ?? NSParagraphStyle.default) : source
        clean.headIndent = finite(geometry.headIndent, fallback: 0,
                                  range: -10_000...10_000)
        clean.firstLineHeadIndent = finite(geometry.firstLineHeadIndent, fallback: 0,
                                           range: -10_000...10_000)
        clean.tailIndent = finite(geometry.tailIndent, fallback: 0,
                                  range: -10_000...10_000)
        let tabs = geometry.tabStops == NSParagraphStyle.default.tabStops
            ? [] : geometry.tabStops.compactMap(cleanTab)
        clean.defaultTabInterval = 36
        clean.tabStops = tabs
        clean.textLists = []
        clean.textBlocks = fallback?.textBlocks ?? []
        return clean
    }

    private static func cleanTab(_ tab: NSTextTab) -> NSTextTab? {
        guard tab.location.isFinite, (0...10_000).contains(tab.location) else { return nil }
        let alignment: NSTextAlignment
        switch tab.alignment {
        case .center, .right, .left:
            alignment = tab.alignment
        default:
            alignment = .left
        }
        var options: [NSTextTab.OptionKey: Any] = [:]
        if tab.options[.columnTerminators] != nil {
            let separator = Locale.current.decimalSeparator ?? "."
            options[.columnTerminators] = CharacterSet(charactersIn: separator)
        }
        return NSTextTab(textAlignment: alignment, location: tab.location,
                         options: options)
    }

    private static func finite(_ value: CGFloat, fallback: CGFloat,
                               range: ClosedRange<CGFloat>) -> CGFloat {
        guard value.isFinite else { return fallback }
        return min(max(value, range.lowerBound), range.upperBound)
    }

    private static func applyStructure(to text: NSMutableAttributedString,
                                       role: String, firstID: String,
                                       list: ListItemModel?,
                                       pageBreakBefore: Bool) {
        let ns = text.string as NSString
        var location = 0
        var paragraphIndex = 0
        while location < ns.length {
            var start = 0, end = 0, contentsEnd = 0
            ns.getParagraphStart(&start, end: &end, contentsEnd: &contentsEnd,
                                 for: NSRange(location: location, length: 0))
            let range = NSRange(location: start, length: end - start)
            text.addAttribute(.lucerneStyleRole, value: role, range: range)
            text.addAttribute(.lucerneParagraphID,
                              value: paragraphIndex == 0 ? firstID : IDGenerator.next("p"),
                              range: range)
            if let list, let encoded = ListItemCodec.encode(list) {
                text.addAttribute(.lucerneList, value: encoded, range: range)
            }
            if paragraphIndex == 0, pageBreakBefore {
                text.addAttribute(.lucernePageBreakBefore, value: true, range: range)
            }
            paragraphIndex += 1
            if end == location { break }
            location = end
        }

        guard ns.length > 0, ns.character(at: ns.length - 1) == 0x0A else { return }
        let terminator = NSRange(location: ns.length - 1, length: 1)
        text.addAttribute(.lucerneTrailingStyleRole, value: role, range: terminator)
        text.addAttribute(.lucerneTrailingParagraphID, value: IDGenerator.next("p"),
                          range: terminator)
        if let list, let encoded = ListItemCodec.encode(list) {
            text.addAttribute(.lucerneTrailingList, value: encoded, range: terminator)
        }
    }

    private static func continuationRange(after selection: NSRange,
                                          in storage: NSAttributedString) -> NSRange? {
        let location = NSMaxRange(selection)
        guard location < storage.length else { return nil }
        let ns = storage.string as NSString
        var paragraphEnd = 0
        ns.getParagraphStart(nil, end: &paragraphEnd, contentsEnd: nil,
                             for: NSRange(location: location, length: 0))
        guard paragraphEnd > location else { return nil }
        return NSRange(location: location, length: paragraphEnd - location)
    }

    private static func paragraphStart(at location: Int, in string: String) -> Int {
        var start = 0
        (string as NSString).getParagraphStart(&start, end: nil, contentsEnd: nil,
                                               for: NSRange(location: location, length: 0))
        return start
    }

    private static func detachFirstParagraph(in text: NSMutableAttributedString) {
        guard text.length > 0 else { return }
        var end = 0
        (text.string as NSString).getParagraphStart(nil, end: &end, contentsEnd: nil,
                                                    for: NSRange(location: 0, length: 0))
        let range = NSRange(location: 0, length: end)
        text.addAttribute(.lucerneParagraphID, value: IDGenerator.next("p"), range: range)
        text.removeAttribute(.lucernePageBreakBefore, range: range)
    }

    private static func removeTrailingStructure(
        fromTerminatorIn text: NSMutableAttributedString
    ) {
        guard text.length > 0 else { return }
        let terminator = NSRange(location: text.length - 1, length: 1)
        text.removeAttribute(.lucerneTrailingParagraphID, range: terminator)
        text.removeAttribute(.lucerneTrailingStyleRole, range: terminator)
        text.removeAttribute(.lucerneTrailingList, range: terminator)
    }

    private static func finalParagraphAttributes(
        in text: NSAttributedString
    ) -> [NSAttributedString.Key: Any] {
        guard text.length > 0 else { return [:] }
        let last = text.length - 1
        let endsInNewline = (text.string as NSString).character(at: last) == 0x0A
        let source = text.attributes(at: last, effectiveRange: nil)
        var result: [NSAttributedString.Key: Any] = [:]

        let idKey: NSAttributedString.Key = endsInNewline
            ? .lucerneTrailingParagraphID : .lucerneParagraphID
        let roleKey: NSAttributedString.Key = endsInNewline
            ? .lucerneTrailingStyleRole : .lucerneStyleRole
        let listKey: NSAttributedString.Key = endsInNewline
            ? .lucerneTrailingList : .lucerneList
        if let id = source[idKey] { result[.lucerneParagraphID] = id }
        if let role = source[roleKey] { result[.lucerneStyleRole] = role }
        if let list = source[listKey] { result[.lucerneList] = list }
        if !endsInNewline,
           (source[.lucernePageBreakBefore] as? Bool) == true {
            result[.lucernePageBreakBefore] = true
        }
        if let paragraphStyle = source[.paragraphStyle] {
            result[.paragraphStyle] = paragraphStyle
        }
        return result
    }

    private static func removeAttachments(from text: NSMutableAttributedString) {
        var ranges: [NSRange] = []
        text.enumerateAttribute(.attachment,
                                in: NSRange(location: 0, length: text.length), options: []) {
            value, range, _ in
            if value != nil { ranges.append(range) }
        }
        for range in ranges.reversed() { text.deleteCharacters(in: range) }

        let replacement = "\u{FFFC}"
        while true {
            let range = (text.string as NSString).range(of: replacement)
            guard range.location != NSNotFound else { break }
            text.deleteCharacters(in: range)
        }
    }

    private static func canonicalizeNewlines(in text: NSMutableAttributedString) {
        let whole = NSRange(location: 0, length: text.length)
        text.mutableString.replaceOccurrences(of: "\r\n", with: "\n", options: [],
                                              range: whole)
        text.mutableString.replaceOccurrences(
            of: "\r", with: "\n", options: [],
            range: NSRange(location: 0, length: text.length))
    }
}
