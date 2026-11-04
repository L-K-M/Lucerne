import XCTest
import AppKit
@testable import LucerneKit

final class PageBreakPersistenceTests: XCTestCase {

    private func model(breakText: String = "Break me",
                       trailing: Bool = false) -> LucerneDocumentModel {
        var body = [
            Paragraph(id: "before", style: "body", runs: [Run(text: "Before")]),
            Paragraph(id: "break", style: "body", pageBreakBefore: true,
                      runs: [Run(text: breakText)]),
        ]
        if !trailing {
            body.append(Paragraph(id: "after", style: "body", runs: [Run(text: "After")]))
        }
        return LucerneDocumentModel(
            page: .a4,
            styles: DefaultDocuments.defaultStyles(),
            body: body,
            objects: [])
    }

    private func breakRange(in attributed: NSAttributedString) -> NSRange {
        (attributed.string as NSString).range(of: "Break me")
    }

    private func unmarkedAttributes(_ attributed: NSAttributedString,
                                    at location: Int) -> [NSAttributedString.Key: Any] {
        var attributes = attributed.attributes(at: location, effectiveRange: nil)
        attributes.removeValue(forKey: .lucernePageBreakBefore)
        attributes.removeValue(forKey: .lucernePageBreakMarker)
        return attributes
    }

    private func assertBreakSurvives(_ attributed: NSAttributedString,
                                     file: StaticString = #filePath,
                                     line: UInt = #line) {
        let paragraphs = AttributedStringReader.paragraphs(
            from: attributed, styles: DefaultDocuments.defaultStyles())
        XCTAssertEqual(paragraphs.first { $0.id == "break" }?.pageBreakBefore, true,
                       file: file, line: line)
    }

    func testDeletingFirstCharacterKeepsPageBreak() {
        let attributed = NSMutableAttributedString(
            attributedString: AttributedStringBuilder.attributedString(for: model()))
        let range = breakRange(in: attributed)

        attributed.deleteCharacters(in: NSRange(location: range.location, length: 1))

        assertBreakSurvives(attributed)
    }

    // A break belongs to the paragraph whose first character carries it. Real
    // insertions at a paragraph start adopt the attributes of the character at the
    // caret, so they keep the break; these drive the text view, not raw storage.

    func testTypingBeforeFirstCharacterKeepsPageBreak() throws {
        let (editor, textView, start) = try markedEditor()
        textView.setSelectedRange(NSRange(location: start, length: 0))

        textView.insertText("X", replacementRange: NSRange(location: NSNotFound, length: 0))

        let paragraphs = editor.snapshotModel().body
        XCTAssertEqual(paragraphs.first { $0.plainText == "XBreak me" }?.pageBreakBefore, true)
        XCTAssertEqual(paragraphs.filter { $0.pageBreakBefore == true }.count, 1)
    }

    func testReplacingParagraphTextKeepsPageBreak() throws {
        let (editor, textView, start) = try markedEditor()
        textView.setSelectedRange(NSRange(location: start, length: ("Break me" as NSString).length))

        textView.insertText("New", replacementRange: NSRange(location: NSNotFound, length: 0))

        let paragraphs = editor.snapshotModel().body
        XCTAssertEqual(paragraphs.first { $0.plainText == "New" }?.pageBreakBefore, true)
    }

    func testPastingPlainTextAtParagraphStartKeepsPageBreak() throws {
        let (editor, textView, start) = try markedEditor()
        textView.setSelectedRange(NSRange(location: start, length: 0))
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("lucerne-test-\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        pasteboard.setString("Pasted ", forType: .string)

        XCTAssertTrue(textView.readSelection(from: pasteboard, type: .string))

        let paragraphs = editor.snapshotModel().body
        XCTAssertEqual(paragraphs.first { $0.plainText == "Pasted Break me" }?.pageBreakBefore, true)
    }

    func testSplittingMarkedParagraphDoesNotDuplicatePageBreak() {
        let attributed = NSMutableAttributedString(
            attributedString: AttributedStringBuilder.attributedString(for: model()))
        let range = breakRange(in: attributed)
        let attributes = attributed.attributes(at: range.location + 3, effectiveRange: nil)

        attributed.insert(NSAttributedString(string: "\n", attributes: attributes),
                          at: range.location + 3)

        let paragraphs = AttributedStringReader.paragraphs(
            from: attributed, styles: DefaultDocuments.defaultStyles())
        XCTAssertEqual(paragraphs.filter { $0.pageBreakBefore == true }.count, 1)
    }

    func testTrailingEmptyParagraphKeepsPageBreak() {
        let source = model(breakText: "", trailing: true)
        let attributed = AttributedStringBuilder.attributedString(for: source)
        let paragraphs = AttributedStringReader.paragraphs(
            from: attributed, styles: source.styles)

        XCTAssertEqual(paragraphs.last?.id, "break")
        XCTAssertEqual(paragraphs.last?.pageBreakBefore, true)
    }

    func testTrailingEmptyPageBreakCreatesANewPage() {
        let editor = EditorController(model: model(breakText: "", trailing: true))

        XCTAssertEqual(editor.pageCount, 2)
        XCTAssertEqual(editor.pageNumber(forCharacterAt: 0), 1)
    }

    func testTypingIntoTrailingEmptyPageBreakKeepsStructure() throws {
        let editor = EditorController(model: model(breakText: "", trailing: true))
        let textView = try XCTUnwrap(
            editor.layoutManager.textContainers.last?.textView as? PageTextView)
        textView.setSelectedRange(NSRange(location: editor.textStorage.length, length: 0))
        textView.typingAttributes[.font] = NSFont.boldSystemFont(ofSize: 17)
        textView.typingAttributes[.foregroundColor] = NSColor.systemRed

        textView.insertText("Typed", replacementRange: textView.selectedRange())

        let paragraph = try XCTUnwrap(editor.snapshotModel().body.last)
        let attributes = editor.textStorage.attributes(
            at: editor.textStorage.length - 1, effectiveRange: nil)
        let font = try XCTUnwrap(attributes[.font] as? NSFont)
        let color = try XCTUnwrap(attributes[.foregroundColor] as? NSColor)
        XCTAssertFalse(editor.textStorage.string.contains(AttributedStringBuilder.pageBreakSentinel))
        XCTAssertTrue(NSFontManager.shared.traits(of: font).contains(.boldFontMask))
        XCTAssertEqual(font.pointSize, 17, accuracy: 0.01)
        XCTAssertEqual(color.usingColorSpace(.sRGB), NSColor.systemRed.usingColorSpace(.sRGB))
        XCTAssertEqual(paragraph.plainText, "Typed")
        XCTAssertEqual(paragraph.pageBreakBefore, true)
        XCTAssertFalse(paragraph.plainText.contains(AttributedStringBuilder.pageBreakSentinel))
    }

    func testRestylingTrailingEmptyPageBreakKeepsStructure() throws {
        let source = model(breakText: "", trailing: true)
        let attributed = AttributedStringBuilder.attributedString(for: source)
        let range = (attributed.string as NSString).paragraphRange(
            for: NSRange(location: attributed.length - 1, length: 0))
        let paragraph = attributed.attributedSubstring(from: range)

        let restyled = try XCTUnwrap(
            EditorController.restyledParagraph(paragraph, role: "heading1", in: source))
        let restored = try XCTUnwrap(
            AttributedStringReader.paragraphs(from: restyled, styles: source.styles).first)

        XCTAssertEqual(restored.style, "heading1")
        XCTAssertEqual(restored.plainText, "")
        XCTAssertEqual(restored.pageBreakBefore, true)
    }

    func testAttributedInsertionKeepsDestinationStructureAndSourceFormatting() throws {
        let editor = EditorController(model: model(breakText: "", trailing: true))
        let textView = try XCTUnwrap(
            editor.layoutManager.textContainers.last?.textView as? PageTextView)
        textView.setSelectedRange(NSRange(location: editor.textStorage.length, length: 0))
        let inserted = NSAttributedString(
            string: "Styled",
            attributes: [
                .font: NSFont(name: "Courier", size: 19) ?? NSFont.monospacedSystemFont(ofSize: 19, weight: .regular),
                .foregroundColor: NSColor.systemBlue,
            ])

        textView.insertText(inserted, replacementRange: textView.selectedRange())

        let paragraph = try XCTUnwrap(editor.snapshotModel().body.last)
        let attributes = editor.textStorage.attributes(
            at: editor.textStorage.length - 1, effectiveRange: nil)
        let font = try XCTUnwrap(attributes[.font] as? NSFont)
        XCTAssertEqual(paragraph.id, "break")
        XCTAssertEqual(paragraph.style, "body")
        XCTAssertEqual(paragraph.pageBreakBefore, true)
        XCTAssertEqual(font.pointSize, 19, accuracy: 0.01)
        XCTAssertEqual((attributes[.foregroundColor] as? NSColor)?.usingColorSpace(.sRGB),
                       NSColor.systemBlue.usingColorSpace(.sRGB))
    }

    func testMultiParagraphInsertionKeepsOneBreakAndUniqueIdentities() throws {
        let editor = EditorController(model: model(breakText: "", trailing: true))
        let textView = try XCTUnwrap(
            editor.layoutManager.textContainers.last?.textView as? PageTextView)
        textView.setSelectedRange(NSRange(location: editor.textStorage.length, length: 0))
        let inserted = NSMutableAttributedString(
            string: "One\n", attributes: [.foregroundColor: NSColor.systemRed])
        let secondStyle = NSMutableParagraphStyle()
        secondStyle.alignment = .right
        inserted.append(NSAttributedString(
            string: "Two",
            attributes: [.foregroundColor: NSColor.systemBlue, .paragraphStyle: secondStyle]))

        textView.insertText(inserted, replacementRange: textView.selectedRange())

        let paragraphs = editor.snapshotModel().body
        let insertedParagraphs = Array(paragraphs.suffix(2))
        XCTAssertEqual(insertedParagraphs.map(\.plainText), ["One", "Two"])
        XCTAssertEqual(insertedParagraphs.first?.pageBreakBefore, true)
        XCTAssertNil(insertedParagraphs.last?.pageBreakBefore)
        XCTAssertEqual(Set(paragraphs.map(\.id)).count, paragraphs.count)
        XCTAssertEqual(insertedParagraphs.last?.align, "right")
        XCTAssertEqual(insertedParagraphs.first?.runs.first?.color?.lowercased(),
                       NSColor.systemRed.lucerneHexString.lowercased())
        XCTAssertEqual(insertedParagraphs.last?.runs.first?.color?.lowercased(),
                       NSColor.systemBlue.lucerneHexString.lowercased())
    }

    func testInsertionEndingInNewlineSeedsCleanTrailingParagraph() throws {
        let list = ListItemModel(list: "list-1", ordered: false, marker: "disc", level: 0)
        var source = model(breakText: "", trailing: true)
        source.body[source.body.count - 1].list = list
        let editor = EditorController(model: source)
        let textView = try XCTUnwrap(
            editor.layoutManager.textContainers.last?.textView as? PageTextView)
        textView.setSelectedRange(NSRange(location: editor.textStorage.length, length: 0))

        textView.insertText("One\n", replacementRange: textView.selectedRange())

        let firstTrailing = try XCTUnwrap(editor.snapshotModel().body.last)
        let secondTrailing = try XCTUnwrap(editor.snapshotModel().body.last)
        XCTAssertEqual(firstTrailing.id, secondTrailing.id)
        XCTAssertEqual(firstTrailing.list, list)

        textView.insertText("Two", replacementRange: textView.selectedRange())

        let paragraphs = editor.snapshotModel().body
        let inserted = Array(paragraphs.suffix(2))
        XCTAssertEqual(inserted.map(\.plainText), ["One", "Two"])
        XCTAssertEqual(inserted.first?.pageBreakBefore, true)
        XCTAssertNil(inserted.last?.pageBreakBefore)
        XCTAssertEqual(inserted.last?.id, firstTrailing.id)
        XCTAssertEqual(inserted.last?.list, list)
        XCTAssertEqual(Set(paragraphs.map(\.id)).count, paragraphs.count)
    }

    func testInterchangeExportsOmitPageBreakSentinel() throws {
        let editor = EditorController(model: model(breakText: "", trailing: true))

        let rtf = try editor.makeRTFData()
        let rtfText = try NSAttributedString(
            data: rtf,
            options: [.documentType: NSAttributedString.DocumentType.rtf],
            documentAttributes: nil)
        let docx = try editor.makeDOCXData()
        let docxText = try NSAttributedString(
            data: docx,
            options: [.documentType: NSAttributedString.DocumentType.officeOpenXML],
            documentAttributes: nil)

        XCTAssertFalse(rtfText.string.contains(AttributedStringBuilder.pageBreakSentinel))
        XCTAssertFalse(docxText.string.contains(AttributedStringBuilder.pageBreakSentinel))
    }

    func testCopiedTextOmitsPageBreakSentinel() throws {
        let editor = EditorController(model: model(breakText: "", trailing: true))
        let textView = try XCTUnwrap(
            editor.layoutManager.textContainers.last?.textView as? PageTextView)
        textView.setSelectedRange(NSRange(location: editor.textStorage.length - 1, length: 1))

        NSPasteboard.general.clearContents()
        textView.copy(nil)

        let copied = try XCTUnwrap(NSPasteboard.general.string(forType: .string))
        XCTAssertFalse(copied.contains(AttributedStringBuilder.pageBreakSentinel))
        XCTAssertEqual(copied, "")
    }

    func testScriptingTextOmitsPageBreakSentinel() {
        let document = LucerneDocument()
        defer { document.close() }
        document.makeWindowControllers()
        document.editor?.load(model: model(breakText: "", trailing: true))

        XCTAssertFalse(document.scriptingText.contains(AttributedStringBuilder.pageBreakSentinel))
        XCTAssertEqual(document.scriptingText, "Before\n")
    }

    // MARK: - Marker dedup scope

    /// A page-break paragraph duplicated elsewhere in the document is a copy with
    /// its own break, not a split: dedup applies only to the immediately preceding
    /// paragraph, where a Return-inherited range can land.
    func testNonAdjacentDuplicateBreakParagraphKeepsBothBreaks() throws {
        var source = model()
        source.body.insert(Paragraph(id: "middle", style: "body",
                                     runs: [Run(text: "Middle")]), at: 2)
        let editor = EditorController(model: source)
        let textView = try XCTUnwrap(
            editor.layoutManager.textContainers.first?.textView as? PageTextView)
        let ns = editor.textStorage.string as NSString
        let target = editor.textStorage.attributedSubstring(
            from: ns.paragraphRange(for: ns.range(of: "Break me")))

        textView.setSelectedRange(NSRange(location: ns.range(of: "After").location,
                                          length: 0))
        textView.insertText(target, replacementRange: textView.selectedRange())
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.3))

        let body = editor.snapshotModel().body
        XCTAssertEqual(body.filter { $0.pageBreakBefore == true }.count, 2,
                       "a duplicated break paragraph must keep its own break")
        XCTAssertEqual(editor.pageCount, 3)
    }

    /// A marker pasted mid-paragraph still forces the break at the paragraph's
    /// start: the whole paragraph moves to the new page, not just the line that
    /// happens to carry the marker.
    func testMidParagraphBreakMarkerDoesNotBreakThePage() throws {
        let wrapping = String(repeating: "lorem ipsum dolor sit amet ", count: 12)
        let source = LucerneDocumentModel(
            page: .a4, styles: DefaultDocuments.defaultStyles(),
            body: [
                Paragraph(id: "intro", style: "body", runs: [Run(text: "Intro")]),
                Paragraph(id: "long", style: "body", runs: [Run(text: wrapping)]),
            ], objects: [])
        let editor = EditorController(model: source)
        let ns = editor.textStorage.string as NSString
        let paragraphStart = ns.range(of: wrapping).location
        let mid = paragraphStart + 200
        let marked = NSRange(location: mid, length: 20)

        editor.textStorage.addAttribute(.lucernePageBreakBefore, value: true,
                                        range: marked)
        editor.textStorage.addAttribute(.lucernePageBreakMarker, value: "mid-para",
                                        range: marked)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.3))

        // A break belongs to the paragraph whose first character carries it, so a
        // marker run that starts mid-paragraph (joined or pasted text) neither
        // breaks inside the paragraph nor moves the whole paragraph.
        XCTAssertEqual(editor.pageNumber(forCharacterAt: paragraphStart), 1)
        XCTAssertEqual(editor.pageNumber(forCharacterAt: mid), 1)
        XCTAssertNil(editor.snapshotModel().body.first { $0.id == "long" }?.pageBreakBefore)
    }

    // MARK: - Insert Page Break targeting

    private func singleParagraphDocument(_ text: String) -> LucerneDocumentModel {
        LucerneDocumentModel(
            page: .a4, styles: DefaultDocuments.defaultStyles(),
            body: [Paragraph(id: "only", style: "body", runs: [Run(text: text)])],
            objects: [])
    }

    /// A caret at the visible end of a paragraph flags the following paragraph;
    /// it must not wedge an extra blank paragraph in between.
    func testEditorBreakAtParagraphEndMarksFollowingParagraphWithoutAddingBlank() throws {
        var initial = model()
        initial.body[1].pageBreakBefore = nil
        let editor = EditorController(model: initial)
        let textView = try XCTUnwrap(
            editor.layoutManager.textContainers.first?.textView as? PageTextView)
        let newline = (editor.textStorage.string as NSString).range(of: "\n").location
        textView.setSelectedRange(NSRange(location: newline, length: 0))
        editor.textViewBecameActive(textView)

        editor.insertPageBreak()

        let paragraphs = editor.snapshotModel().body
        XCTAssertEqual(paragraphs.map(\.plainText), ["Before", "Break me", "After"])
        XCTAssertEqual(paragraphs[1].pageBreakBefore, true)
    }

    /// At the end of a non-empty document exactly one trailing empty break
    /// paragraph is created — no extra blank line.
    func testEditorBreakAtDocumentEndCreatesOneTrailingBreakParagraph() throws {
        let editor = EditorController(model: singleParagraphDocument("Only"))
        let textView = try XCTUnwrap(
            editor.layoutManager.textContainers.first?.textView as? PageTextView)
        textView.setSelectedRange(NSRange(location: editor.textStorage.length, length: 0))
        editor.textViewBecameActive(textView)

        editor.insertPageBreak()

        let paragraphs = editor.snapshotModel().body
        XCTAssertEqual(paragraphs.map(\.plainText), ["Only", ""])
        XCTAssertEqual(paragraphs.last?.pageBreakBefore, true)
        XCTAssertEqual(editor.layoutManager.textContainers.count, 2)
    }

    /// An existing trailing empty paragraph carries the break itself instead of
    /// gaining another empty paragraph after it.
    func testEditorBreakUsesExistingTrailingEmptyParagraph() throws {
        let initial = LucerneDocumentModel(
            page: .a4, styles: DefaultDocuments.defaultStyles(),
            body: [
                Paragraph(id: "only", style: "body", runs: [Run(text: "Only")]),
                Paragraph(id: "empty", style: "body", runs: [Run(text: "")]),
            ], objects: [])
        let editor = EditorController(model: initial)
        let textView = try XCTUnwrap(
            editor.layoutManager.textContainers.first?.textView as? PageTextView)
        textView.setSelectedRange(NSRange(location: editor.textStorage.length, length: 0))
        editor.textViewBecameActive(textView)

        editor.insertPageBreak()

        let paragraphs = editor.snapshotModel().body
        XCTAssertEqual(paragraphs.map(\.plainText), ["Only", ""])
        XCTAssertEqual(paragraphs.last?.id, "empty")
        XCTAssertEqual(paragraphs.last?.pageBreakBefore, true)
        XCTAssertEqual(editor.layoutManager.textContainers.count, 2)
    }

    /// An empty middle paragraph is marked in place rather than skipped.
    func testEditorBreakMarksEmptyMiddleParagraphInPlace() throws {
        let initial = LucerneDocumentModel(
            page: .a4, styles: DefaultDocuments.defaultStyles(),
            body: [
                Paragraph(id: "a", style: "body", runs: [Run(text: "A")]),
                Paragraph(id: "gap", style: "body", runs: [Run(text: "")]),
                Paragraph(id: "b", style: "body", runs: [Run(text: "B")]),
            ], objects: [])
        let editor = EditorController(model: initial)
        let textView = try XCTUnwrap(
            editor.layoutManager.textContainers.first?.textView as? PageTextView)
        // The empty middle paragraph occupies only its separator, index 2.
        textView.setSelectedRange(NSRange(location: 2, length: 0))
        editor.textViewBecameActive(textView)

        editor.insertPageBreak()

        let paragraphs = editor.snapshotModel().body
        XCTAssertEqual(paragraphs.map(\.plainText), ["A", "", "B"])
        XCTAssertEqual(paragraphs[1].pageBreakBefore, true)
    }

    // MARK: - Return splits of a marked paragraph

    private func markedEditor() throws -> (EditorController, PageTextView, Int) {
        let editor = EditorController(model: model())
        let textView = try XCTUnwrap(
            editor.layoutManager.textContainers.first?.textView as? PageTextView)
        editor.textViewBecameActive(textView)
        let start = (editor.textStorage.string as NSString).range(of: "Break me").location
        return (editor, textView, start)
    }

    func testReturnAtMarkedParagraphStartMovesBreakWithContent() throws {
        let (editor, textView, start) = try markedEditor()
        textView.setSelectedRange(NSRange(location: start, length: 0))

        textView.insertNewline(nil)

        let paragraphs = editor.snapshotModel().body
        let blank = try XCTUnwrap(paragraphs.first { $0.plainText.isEmpty })
        let target = try XCTUnwrap(paragraphs.first { $0.plainText == "Break me" })
        XCTAssertNil(blank.pageBreakBefore)
        XCTAssertEqual(target.pageBreakBefore, true)
    }

    func testReturnInsideMarkedParagraphLeavesBreakOnFirstHalfOnly() throws {
        let (editor, textView, start) = try markedEditor()
        textView.setSelectedRange(NSRange(location: start + 3, length: 0))

        textView.insertNewline(nil)

        let paragraphs = editor.snapshotModel().body
        XCTAssertEqual(paragraphs.first { $0.plainText == "Bre" }?.pageBreakBefore, true)
        XCTAssertNil(paragraphs.first { $0.plainText == "ak me" }?.pageBreakBefore)
        XCTAssertEqual(paragraphs.filter { $0.pageBreakBefore == true }.count, 1)
    }

    func testReturnAfterMarkedParagraphDoesNotMarkNewTypedParagraph() throws {
        let (editor, textView, start) = try markedEditor()
        textView.setSelectedRange(
            NSRange(location: start + "Break me".utf16.count, length: 0))

        textView.insertNewline(nil)
        textView.insertText("New", replacementRange: textView.selectedRange())

        let paragraphs = editor.snapshotModel().body
        XCTAssertEqual(paragraphs.first { $0.plainText == "Break me" }?.pageBreakBefore,
                       true)
        XCTAssertNil(paragraphs.first { $0.plainText == "New" }?.pageBreakBefore)
        XCTAssertEqual(paragraphs.filter { $0.pageBreakBefore == true }.count, 1)
    }

    func testReturnInTrailingEmptyBreakKeepsOneMarkedEmptyParagraph() throws {
        let editor = EditorController(model: singleParagraphDocument("Only"))
        let first = try XCTUnwrap(
            editor.layoutManager.textContainers.first?.textView as? PageTextView)
        editor.textViewBecameActive(first)
        first.setSelectedRange(NSRange(location: editor.textStorage.length, length: 0))
        editor.insertPageBreak()
        let textView = try XCTUnwrap(
            editor.layoutManager.textContainers.last?.textView as? PageTextView)
        textView.setSelectedRange(NSRange(location: editor.textStorage.length, length: 0))
        editor.textViewBecameActive(textView)

        textView.insertNewline(nil)

        let paragraphs = editor.snapshotModel().body
        XCTAssertEqual(paragraphs.map(\.plainText), ["Only", "", ""])
        XCTAssertEqual(paragraphs.filter { $0.pageBreakBefore == true }.count, 1)
        XCTAssertEqual(paragraphs[1].pageBreakBefore, true)
        XCTAssertNil(paragraphs[2].pageBreakBefore)
    }

    func testUndoRedoAfterReturnInsideMarkedParagraphKeepsOneBreak() throws {
        let (editor, textView, start) = try markedEditor()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = editor.canvasView
        XCTAssertTrue(window.makeFirstResponder(textView))
        textView.setSelectedRange(NSRange(location: start + 3, length: 0))

        textView.insertNewline(nil)
        let undoManager = try XCTUnwrap(textView.undoManager)

        undoManager.undo()
        XCTAssertEqual(
            editor.snapshotModel().body.filter { $0.pageBreakBefore == true }.count, 1)
        undoManager.redo()

        let paragraphs = editor.snapshotModel().body
        XCTAssertEqual(paragraphs.filter { $0.pageBreakBefore == true }.count, 1)
        XCTAssertEqual(paragraphs.first { $0.plainText == "Bre" }?.pageBreakBefore, true)
        XCTAssertNil(paragraphs.first { $0.plainText == "ak me" }?.pageBreakBefore)
    }

    // MARK: - Deletion keeps the break

    /// Deleting the only character of a marked middle paragraph leaves the break
    /// on its (still marked) terminator.
    func testDeletingOnlyCharacterOfMiddleParagraphKeepsBreak() throws {
        let editor = EditorController(model: model(breakText: "X"))
        let textView = try XCTUnwrap(
            editor.layoutManager.textContainers.first?.textView as? PageTextView)
        let start = (editor.textStorage.string as NSString).range(of: "X").location
        textView.setSelectedRange(NSRange(location: start, length: 1))

        textView.deleteBackward(nil)

        let paragraphs = editor.snapshotModel().body
        XCTAssertEqual(paragraphs[1].plainText, "")
        XCTAssertEqual(paragraphs[1].pageBreakBefore, true)
    }

    /// Deleting the only character of a marked final paragraph restores the
    /// sentinel carrier so the now-empty paragraph keeps its break.
    func testDeletingOnlyCharacterOfFinalParagraphKeepsBreak() throws {
        let editor = EditorController(model: model(breakText: "X", trailing: true))
        let textView = try XCTUnwrap(
            editor.layoutManager.textContainers.last?.textView as? PageTextView)
        textView.setSelectedRange(NSRange(location: editor.textStorage.length, length: 0))

        textView.deleteBackward(nil)

        let last = editor.snapshotModel().body.last
        XCTAssertEqual(last?.plainText, "")
        XCTAssertEqual(last?.pageBreakBefore, true)
    }

    /// Backspacing over the invisible carrier likewise keeps the trailing break:
    /// the carrier is restored and the caret lands before it, so the next
    /// Backspace removes the paragraph's separator instead.
    func testBackspaceOverTrailingBreakSentinelRemovesBreak() throws {
        let editor = EditorController(model: model(breakText: "", trailing: true))
        let textView = try XCTUnwrap(
            editor.layoutManager.textContainers.last?.textView as? PageTextView)
        textView.setSelectedRange(NSRange(location: editor.textStorage.length, length: 0))

        textView.deleteBackward(nil)

        XCTAssertFalse(editor.textStorage.string
            .contains(AttributedStringBuilder.pageBreakSentinel))
        let paragraphs = editor.snapshotModel().body
        XCTAssertEqual(paragraphs.last?.plainText, "",
                       "Backspace removes the break, not yet the empty paragraph")
        XCTAssertNil(paragraphs.last?.pageBreakBefore)
    }

    // MARK: - Typing after a trailing break

    /// Insert Page Break at the end of a one-paragraph document, then insert
    /// `text` into the trailing break paragraph through the real insertText path.
    private func typeAfterTrailingBreak(_ text: String, perCharacter: Bool) throws
        -> EditorController {
        let editor = EditorController(model: singleParagraphDocument("Only"))
        let first = try XCTUnwrap(
            editor.layoutManager.textContainers.first?.textView as? PageTextView)
        first.setSelectedRange(NSRange(location: editor.textStorage.length, length: 0))
        editor.textViewBecameActive(first)
        editor.insertPageBreak()

        let textView = try XCTUnwrap(
            editor.layoutManager.textContainers.last?.textView as? PageTextView)
        textView.setSelectedRange(first.selectedRange())
        editor.textViewBecameActive(textView)
        if perCharacter {
            for character in text {
                textView.insertText(String(character),
                                    replacementRange: NSRange(location: NSNotFound, length: 0))
            }
        } else {
            textView.insertText(text,
                                replacementRange: NSRange(location: NSNotFound, length: 0))
        }
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.3))
        return editor
    }

    func testTypingCharactersIntoTrailingBreakParagraph() throws {
        let editor = try typeAfterTrailingBreak("Next", perCharacter: true)

        let body = editor.snapshotModel().body
        XCTAssertEqual(body.map(\.plainText), ["Only", "Next"])
        XCTAssertEqual(body.last?.pageBreakBefore, true)
        XCTAssertEqual(editor.layoutManager.textContainers.count, 2)
    }

    func testInsertingMultiParagraphTextIntoTrailingBreakParagraph() throws {
        let editor = try typeAfterTrailingBreak("Next\nMore", perCharacter: false)

        let body = editor.snapshotModel().body
        XCTAssertEqual(body.map(\.plainText), ["Only", "Next", "More"])
        XCTAssertEqual(body.first { $0.plainText == "Next" }?.pageBreakBefore, true)
        XCTAssertNil(body.first { $0.plainText == "More" }?.pageBreakBefore)
        XCTAssertEqual(editor.layoutManager.textContainers.count, 2)
    }

    /// Consecutive forced breaks still paginate onto distinct pages.
    func testAdjacentForcedBreaksCreateDistinctPages() {
        let adjacent = LucerneDocumentModel(
            page: .a4, styles: DefaultDocuments.defaultStyles(),
            body: [
                Paragraph(id: "p1", style: "body", runs: [Run(text: "One")]),
                Paragraph(id: "p2", style: "body", pageBreakBefore: true,
                          runs: [Run(text: "Two")]),
                Paragraph(id: "p3", style: "body", pageBreakBefore: true,
                          runs: [Run(text: "Three")]),
            ], objects: [])
        let editor = EditorController(model: adjacent)

        XCTAssertEqual(editor.layoutManager.textContainers.count, 3)
    }

    // MARK: - Removing a trailing break

    /// Insert Page Break at the end of "Only" with the editor hosted in a window,
    /// so text-view edits register undo. The caret ends after the break carrier.
    private func trailingBreakInWindow() throws -> (EditorController, PageTextView, NSWindow) {
        let editor = EditorController(model: singleParagraphDocument("Only"))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = editor.canvasView
        let first = try XCTUnwrap(
            editor.layoutManager.textContainers.first?.textView as? PageTextView)
        first.setSelectedRange(NSRange(location: editor.textStorage.length, length: 0))
        editor.textViewBecameActive(first)
        editor.insertPageBreak()
        // Every page view shares one storage and selection; editing through the
        // first view keeps it the window's first responder, which owns undo.
        XCTAssertTrue(window.makeFirstResponder(first))
        first.setSelectedRange(NSRange(location: editor.textStorage.length, length: 0))
        return (editor, first, window)
    }

    private func breakSummary(_ editor: EditorController) -> [String] {
        editor.snapshotModel().body.map { "\($0.plainText)|\($0.pageBreakBefore == true)" }
    }

    private func containsSentinel(_ editor: EditorController) -> Bool {
        editor.textStorage.string.contains(AttributedStringBuilder.pageBreakSentinel)
    }

    func testBackspaceAfterTrailingBreakRemovesBreakThenParagraph() throws {
        let (editor, textView, window) = try trailingBreakInWindow()
        defer { withExtendedLifetime(window) {} }
        XCTAssertEqual(breakSummary(editor), ["Only|false", "|true"])

        textView.deleteBackward(nil)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.3))

        XCTAssertEqual(breakSummary(editor), ["Only|false", "|false"])
        XCTAssertFalse(containsSentinel(editor))
        XCTAssertEqual(editor.layoutManager.textContainers.count, 1)

        let undoManager = try XCTUnwrap(textView.undoManager)
        undoManager.undo()
        XCTAssertEqual(breakSummary(editor), ["Only|false", "|true"])
        undoManager.redo()
        XCTAssertEqual(breakSummary(editor), ["Only|false", "|false"])

        textView.deleteBackward(nil)
        XCTAssertEqual(breakSummary(editor), ["Only|false"])
        XCTAssertEqual(editor.textStorage.string, "Only")
    }

    func testBackspaceJoiningBreakParagraphDropsTheBreak() throws {
        let editor = EditorController(model: LucerneDocumentModel(
            page: .a4, styles: DefaultDocuments.defaultStyles(),
            body: [
                Paragraph(id: "only", style: "body", runs: [Run(text: "Only")]),
                Paragraph(id: "next", style: "body", pageBreakBefore: true,
                          runs: [Run(text: "Next")]),
            ], objects: []))
        let textView = try XCTUnwrap(
            editor.layoutManager.textContainers.last?.textView as? PageTextView)
        textView.setSelectedRange(NSRange(location: 5, length: 0))

        textView.deleteBackward(nil)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.3))

        XCTAssertEqual(breakSummary(editor), ["OnlyNext|false"],
                       "joining must not move the previous paragraph to a new page")
        XCTAssertEqual(editor.layoutManager.textContainers.count, 1)
    }

    func testForwardDeleteJoiningTrailingBreakParagraphDropsTheCarrier() throws {
        let (editor, textView, _) = try trailingBreakInWindow()
        textView.setSelectedRange(NSRange(location: 4, length: 0))

        textView.deleteForward(nil)

        XCTAssertEqual(breakSummary(editor), ["Only|false"])
        XCTAssertFalse(containsSentinel(editor),
                       "the invisible carrier must not end up inside \"Only\"")
    }

    func testBackspacingTypedTextKeepsBreakUntilTheCarrierIsDeleted() throws {
        let (editor, textView, _) = try trailingBreakInWindow()
        textView.insertText("X", replacementRange: NSRange(location: NSNotFound, length: 0))
        XCTAssertEqual(breakSummary(editor), ["Only|false", "X|true"])

        textView.deleteBackward(nil)
        XCTAssertEqual(breakSummary(editor), ["Only|false", "|true"])
        XCTAssertEqual(editor.layoutManager.textContainers.count, 2)

        textView.deleteBackward(nil)
        XCTAssertEqual(breakSummary(editor), ["Only|false", "|false"])
        XCTAssertFalse(containsSentinel(editor))

        textView.deleteBackward(nil)
        XCTAssertEqual(breakSummary(editor), ["Only|false"])
    }
}
