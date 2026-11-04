import XCTest
import AppKit
@testable import LucerneKit

final class ParagraphIdentityTests: XCTestCase {

    private func editor(for paragraph: Paragraph) throws -> (EditorController, PageTextView) {
        let model = LucerneDocumentModel(
            page: .a4,
            styles: DefaultDocuments.defaultStyles(),
            body: [paragraph],
            objects: [])
        let editor = EditorController(model: model)
        let textView = try XCTUnwrap(
            editor.layoutManager.textContainers.first?.textView as? PageTextView)
        editor.textViewBecameActive(textView)
        return (editor, textView)
    }

    private func assertUniqueIDs(_ editor: EditorController,
                                 file: StaticString = #filePath,
                                 line: UInt = #line) {
        let paragraphs = AttributedStringReader.paragraphs(
            from: editor.textStorage, styles: editor.model.styles)
        XCTAssertEqual(Set(paragraphs.map(\.id)).count, paragraphs.count,
                       "each paragraph must have its own identity", file: file, line: line)
    }

    func testOrdinaryReturnMintsIdentityForBothHalves() throws {
        let (editor, textView) = try editor(for: Paragraph(
            id: "original", style: "body", runs: [Run(text: "Hello world")]))
        textView.setSelectedRange(NSRange(location: 5, length: 0))

        textView.insertNewline(nil)

        let paragraphs = editor.snapshotModel().body
        XCTAssertEqual(paragraphs.map(\.plainText), ["Hello", " world"])
        XCTAssertEqual(paragraphs.first?.id, "original")
        assertUniqueIDs(editor)
    }

    func testListAndHeadingSplitsMintIdentity() throws {
        let list = ListItemModel(list: "list-1", ordered: false, marker: "disc", level: 0)
        let (listEditor, listView) = try editor(for: Paragraph(
            id: "list-item", style: "body", list: list, runs: [Run(text: "Item text")]))
        listView.setSelectedRange(NSRange(location: 4, length: 0))
        listView.insertNewline(nil)

        let listParagraphs = listEditor.snapshotModel().body
        XCTAssertEqual(listParagraphs.map(\.list), [list, list])
        XCTAssertEqual(listParagraphs.first?.id, "list-item")
        assertUniqueIDs(listEditor)

        let (headingEditor, headingView) = try editor(for: Paragraph(
            id: "heading", style: "heading1", runs: [Run(text: "Title")]))
        headingView.setSelectedRange(NSRange(location: 2, length: 0))
        headingView.insertNewline(nil)

        XCTAssertEqual(headingEditor.snapshotModel().body.last?.style, "heading1")
        assertUniqueIDs(headingEditor)
    }

    func testPageBreakSplitMintsIdentity() throws {
        let (editor, textView) = try editor(for: Paragraph(
            id: "original", style: "body", runs: [Run(text: "Hello world")]))
        textView.setSelectedRange(NSRange(location: 5, length: 0))

        editor.insertPageBreak()

        let paragraphs = editor.snapshotModel().body
        XCTAssertEqual(paragraphs.first?.id, "original")
        XCTAssertEqual(paragraphs.last?.pageBreakBefore, true)
        assertUniqueIDs(editor)
    }

    func testReturnAtEndPreservesTrailingListMetadata() throws {
        let list = ListItemModel(list: "list-1", ordered: true, marker: "decimal", level: 1)
        let (editor, textView) = try editor(for: Paragraph(
            id: "list-item", style: "body", list: list, runs: [Run(text: "Item")]))
        textView.setSelectedRange(NSRange(location: 4, length: 0))

        textView.insertNewline(nil)

        let paragraphs = editor.snapshotModel().body
        XCTAssertEqual(paragraphs.map(\.plainText), ["Item", ""])
        XCTAssertEqual(paragraphs.map(\.list), [list, list])
        XCTAssertEqual(ListItemCodec.decode(textView.typingAttributes[.lucerneList]), list)
        assertUniqueIDs(editor)

        textView.insertText("Next", replacementRange: textView.selectedRange())

        let typedParagraphs = editor.snapshotModel().body
        XCTAssertEqual(typedParagraphs.map(\.plainText), ["Item", "Next"])
        XCTAssertEqual(typedParagraphs.map(\.list), [list, list])
        assertUniqueIDs(editor)
    }

    func testReturnInEmptyMiddleParagraphMintsIdentity() throws {
        let model = LucerneDocumentModel(
            page: .a4,
            styles: DefaultDocuments.defaultStyles(),
            body: [
                Paragraph(id: "first", style: "body", runs: [Run(text: "One")]),
                Paragraph(id: "empty", style: "body", runs: [Run(text: "")]),
                Paragraph(id: "last", style: "body", runs: [Run(text: "Three")]),
            ],
            objects: [])
        let editor = EditorController(model: model)
        let textView = try XCTUnwrap(
            editor.layoutManager.textContainers.first?.textView as? PageTextView)
        editor.textViewBecameActive(textView)
        textView.setSelectedRange(NSRange(location: 4, length: 0))

        textView.insertNewline(nil)

        let paragraphs = AttributedStringReader.paragraphs(
            from: editor.textStorage, styles: editor.model.styles)
        XCTAssertEqual(paragraphs.map(\.plainText), ["One", "", "", "Three"])
        XCTAssertTrue(Set(["first", "empty", "last"]).isSubset(of: Set(paragraphs.map(\.id))))
        assertUniqueIDs(editor)
    }

    func testDeletingParagraphBoundaryLeavesOneIdentity() throws {
        let model = LucerneDocumentModel(
            page: .a4,
            styles: DefaultDocuments.defaultStyles(),
            body: [
                Paragraph(id: "first", style: "body", runs: [Run(text: "One")]),
                Paragraph(id: "second", style: "body", runs: [Run(text: "Two")]),
            ],
            objects: [])
        let editor = EditorController(model: model)
        let textView = try XCTUnwrap(
            editor.layoutManager.textContainers.first?.textView as? PageTextView)
        editor.textViewBecameActive(textView)
        textView.setSelectedRange(NSRange(location: 4, length: 0))

        textView.deleteBackward(nil)

        let paragraphs = AttributedStringReader.paragraphs(
            from: editor.textStorage, styles: editor.model.styles)
        XCTAssertEqual(paragraphs.map(\.plainText), ["OneTwo"])
        XCTAssertEqual(paragraphs.first?.id, "first")
        assertUniqueIDs(editor)
    }

    func testTableInsertionMintsIdentityForEveryParagraph() throws {
        let (editor, textView) = try editor(for: Paragraph(
            id: "empty", style: "body", runs: [Run(text: "")]))
        textView.setSelectedRange(NSRange(location: 0, length: 0))

        editor.insertTable(rows: 1, columns: 1)

        assertUniqueIDs(editor)
    }

    func testSnapshotRepairsLegacyDuplicateIdentities() {
        let model = LucerneDocumentModel(
            page: .a4,
            styles: DefaultDocuments.defaultStyles(),
            body: [
                Paragraph(id: "duplicate", style: "body", runs: [Run(text: "One")]),
                Paragraph(id: "duplicate", style: "body", runs: [Run(text: "Two")]),
            ],
            objects: [])
        let editor = EditorController(model: model)
        let paragraphs = editor.snapshotModel().body
        let secondSnapshot = editor.snapshotModel().body

        XCTAssertEqual(Set(paragraphs.map(\.id)).count, paragraphs.count)
        XCTAssertEqual(paragraphs.first?.id, "duplicate")
        XCTAssertEqual(secondSnapshot.map(\.id), paragraphs.map(\.id))
    }
}
