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

    func testInsertingBeforeFirstCharacterKeepsPageBreak() {
        let attributed = NSMutableAttributedString(
            attributedString: AttributedStringBuilder.attributedString(for: model()))
        let range = breakRange(in: attributed)
        let attributes = unmarkedAttributes(attributed, at: range.location)

        attributed.insert(NSAttributedString(string: "X", attributes: attributes),
                          at: range.location)

        assertBreakSurvives(attributed)
    }

    func testReplacingParagraphTextKeepsPageBreak() {
        let attributed = NSMutableAttributedString(
            attributedString: AttributedStringBuilder.attributedString(for: model()))
        let range = breakRange(in: attributed)
        let attributes = unmarkedAttributes(attributed, at: range.location)

        attributed.replaceCharacters(in: range,
                                     with: NSAttributedString(string: "New", attributes: attributes))

        assertBreakSurvives(attributed)
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

        textView.copy(nil)

        let copied = try XCTUnwrap(NSPasteboard.general.string(forType: .string))
        XCTAssertFalse(copied.contains(AttributedStringBuilder.pageBreakSentinel))
        XCTAssertEqual(copied, "")
    }

    func testScriptingTextOmitsPageBreakSentinel() {
        let document = LucerneDocument()
        document.makeWindowControllers()
        document.editor?.load(model: model(breakText: "", trailing: true))

        XCTAssertFalse(document.scriptingText.contains(AttributedStringBuilder.pageBreakSentinel))
        XCTAssertEqual(document.scriptingText, "Before\n")
    }
}
