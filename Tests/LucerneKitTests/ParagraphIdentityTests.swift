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
        XCTAssertEqual(paragraphs.last?.pageBreakBefore, true)
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
