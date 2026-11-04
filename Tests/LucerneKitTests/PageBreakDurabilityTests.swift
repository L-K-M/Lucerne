import XCTest
import AppKit
@testable import LucerneKit

final class PageBreakDurabilityTests: XCTestCase {
    private let styles = DefaultDocuments.defaultStyles()

    private func model(target: String = "Target", final: Bool = false) -> LucerneDocumentModel {
        var body = [
            Paragraph(id: "before", style: "body", runs: [Run(text: "Before")]),
            Paragraph(id: "target", style: "body", pageBreakBefore: true,
                      runs: [Run(text: target)])
        ]
        if !final {
            body.append(Paragraph(id: "after", style: "body", runs: [Run(text: "After")]))
        }
        return LucerneDocumentModel(page: .a4, styles: styles, body: body, objects: [])
    }

    private func storage(for model: LucerneDocumentModel) -> NSMutableAttributedString {
        NSMutableAttributedString(
            attributedString: AttributedStringBuilder.attributedString(for: model))
    }

    private func paragraphs(from storage: NSAttributedString) -> [Paragraph] {
        AttributedStringReader.paragraphs(from: storage, styles: styles)
    }

    private func targetStart(in storage: NSAttributedString, text: String = "Target") -> Int {
        let location = (storage.string as NSString).range(of: text).location
        precondition(location != NSNotFound, "Text \"\(text)\" not found in storage")
        return location
    }

    private func unmarkedAttributes(in storage: NSAttributedString) -> [NSAttributedString.Key: Any] {
        var attributes = storage.attributes(at: 0, effectiveRange: nil)
        attributes[.lucernePageBreakBefore] = nil
        attributes[.lucerneTrailingPageBreakBefore] = nil
        return attributes
    }

    func testInsertingAtParagraphStartKeepsBreak() throws {
        let storage = storage(for: model())
        let start = targetStart(in: storage)
        storage.insert(NSAttributedString(string: "X",
                                          attributes: unmarkedAttributes(in: storage)),
                       at: start)

        let target = try XCTUnwrap(paragraphs(from: storage).first { $0.plainText == "XTarget" })
        XCTAssertEqual(target.pageBreakBefore, true)
    }

    func testDeletingFirstCharacterKeepsBreak() throws {
        let storage = storage(for: model())
        storage.deleteCharacters(in: NSRange(location: targetStart(in: storage), length: 1))

        let target = try XCTUnwrap(paragraphs(from: storage).first { $0.plainText == "arget" })
        XCTAssertEqual(target.pageBreakBefore, true)
    }

    func testReplacingFirstCharacterKeepsBreak() throws {
        let storage = storage(for: model())
        let start = targetStart(in: storage)
        storage.deleteCharacters(in: NSRange(location: start, length: 1))
        storage.insert(NSAttributedString(string: "R",
                                          attributes: unmarkedAttributes(in: storage)),
                       at: start)

        let target = try XCTUnwrap(paragraphs(from: storage).first { $0.plainText == "Rarget" })
        XCTAssertEqual(target.pageBreakBefore, true)
    }

    func testSplittingAtParagraphStartMovesBreakWithContent() throws {
        let storage = storage(for: model())
        storage.insert(NSAttributedString(string: "\n",
                                          attributes: unmarkedAttributes(in: storage)),
                       at: targetStart(in: storage))

        let restored = paragraphs(from: storage)
        let blank = try XCTUnwrap(restored.first { $0.plainText.isEmpty })
        let target = try XCTUnwrap(restored.first { $0.plainText == "Target" })
        XCTAssertNil(blank.pageBreakBefore)
        XCTAssertEqual(target.pageBreakBefore, true)
    }

    func testDeletingOnlyCharacterOfMiddleParagraphKeepsBreak() {
        let storage = storage(for: model(target: "X"))
        storage.deleteCharacters(in: NSRange(location: targetStart(in: storage, text: "X"),
                                             length: 1))

        let restored = paragraphs(from: storage)
        XCTAssertEqual(restored[1].plainText, "")
        XCTAssertEqual(restored[1].pageBreakBefore, true)
    }

    func testDeletingOnlyCharacterOfFinalParagraphKeepsBreak() {
        let storage = storage(for: model(target: "X", final: true))
        storage.deleteCharacters(in: NSRange(location: targetStart(in: storage, text: "X"),
                                             length: 1))

        let target = paragraphs(from: storage).last
        XCTAssertEqual(target?.plainText, "")
        XCTAssertEqual(target?.pageBreakBefore, true)
    }

    func testAlreadyEmptyFinalParagraphRoundTripsBreak() {
        let restored = paragraphs(from: storage(for: model(target: "", final: true)))

        XCTAssertEqual(restored.last?.plainText, "")
        XCTAssertEqual(restored.last?.pageBreakBefore, true)
    }

    func testEmptyFinalBreakCreatesAnotherPage() {
        let editor = EditorController(model: model(target: "", final: true))

        XCTAssertEqual(editor.layoutManager.textContainers.count, 2)
    }

    func testAdjacentForcedBreaksCreateDistinctPages() {
        let adjacent = LucerneDocumentModel(
            page: .a4, styles: styles,
            body: [
                Paragraph(id: "p1", style: "body", runs: [Run(text: "One")]),
                Paragraph(id: "p2", style: "body", pageBreakBefore: true,
                          runs: [Run(text: "Two")]),
                Paragraph(id: "p3", style: "body", pageBreakBefore: true,
                          runs: [Run(text: "Three")])
            ],
            objects: [])
        let editor = EditorController(model: adjacent)

        XCTAssertEqual(editor.layoutManager.textContainers.count, 3)
    }

    func testEditorBreakSurvivesDeletingFirstCharacter() throws {
        var initial = model()
        initial.body[1].pageBreakBefore = nil
        let editor = EditorController(model: initial)
        let textView = try XCTUnwrap(
            editor.layoutManager.textContainers.first?.textView as? PageTextView)
        let start = targetStart(in: editor.textStorage)
        textView.setSelectedRange(NSRange(location: start, length: 0))
        editor.textViewBecameActive(textView)

        editor.insertPageBreak()
        editor.textStorage.deleteCharacters(in: NSRange(location: start, length: 1))

        let target = try XCTUnwrap(
            editor.snapshotModel().body.first { $0.plainText == "arget" })
        XCTAssertEqual(target.pageBreakBefore, true)
    }

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
        XCTAssertEqual(paragraphs.map(\.plainText), ["Before", "Target", "After"])
        XCTAssertEqual(paragraphs[1].pageBreakBefore, true)
    }

    func testEditorBreakAtDocumentEndCreatesOneTrailingBreakParagraph() throws {
        let initial = LucerneDocumentModel(
            page: .a4, styles: styles,
            body: [Paragraph(id: "only", style: "body", runs: [Run(text: "Only")])],
            objects: [])
        let editor = EditorController(model: initial)
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

    func testEditorBreakUsesExistingTrailingEmptyParagraph() throws {
        let initial = LucerneDocumentModel(
            page: .a4, styles: styles,
            body: [
                Paragraph(id: "only", style: "body", runs: [Run(text: "Only")]),
                Paragraph(id: "empty", style: "body", runs: [Run(text: "")])
            ], objects: [])
        let editor = EditorController(model: initial)
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

    func testReturnAtMarkedParagraphStartMovesBreakWithContent() throws {
        let (editor, textView, start) = try markedEditor()
        textView.setSelectedRange(NSRange(location: start, length: 0))

        textView.insertNewline(nil)

        let paragraphs = editor.snapshotModel().body
        let blank = try XCTUnwrap(paragraphs.first { $0.plainText.isEmpty })
        let target = try XCTUnwrap(paragraphs.first { $0.plainText == "Target" })
        XCTAssertNil(blank.pageBreakBefore)
        XCTAssertEqual(target.pageBreakBefore, true)
    }

    func testReturnInsideMarkedParagraphLeavesBreakOnFirstHalfOnly() throws {
        let (editor, textView, start) = try markedEditor()
        textView.setSelectedRange(NSRange(location: start + 3, length: 0))

        textView.insertNewline(nil)

        let paragraphs = editor.snapshotModel().body
        XCTAssertEqual(paragraphs.first { $0.plainText == "Tar" }?.pageBreakBefore, true)
        XCTAssertNil(paragraphs.first { $0.plainText == "get" }?.pageBreakBefore)
    }

    func testReturnAfterMarkedParagraphDoesNotMarkNewTypedParagraph() throws {
        let (editor, textView, start) = try markedEditor()
        textView.setSelectedRange(NSRange(location: start + "Target".utf16.count, length: 0))

        textView.insertNewline(nil)
        textView.insertText("New", replacementRange: textView.selectedRange())

        let paragraphs = editor.snapshotModel().body
        XCTAssertEqual(paragraphs.first { $0.plainText == "Target" }?.pageBreakBefore, true)
        XCTAssertNil(paragraphs.first { $0.plainText == "New" }?.pageBreakBefore)
    }

    func testReturnInTrailingEmptyBreakKeepsOneMarkedEmptyParagraph() throws {
        let initial = LucerneDocumentModel(
            page: .a4, styles: styles,
            body: [Paragraph(id: "only", style: "body", runs: [Run(text: "Only")])],
            objects: [])
        let editor = EditorController(model: initial)
        let textView = try XCTUnwrap(
            editor.layoutManager.textContainers.first?.textView as? PageTextView)
        editor.textViewBecameActive(textView)
        textView.setSelectedRange(NSRange(location: editor.textStorage.length, length: 0))
        editor.insertPageBreak()

        textView.insertNewline(nil)

        let paragraphs = editor.snapshotModel().body
        XCTAssertEqual(paragraphs.map(\.plainText), ["Only", "", ""])
        XCTAssertEqual(paragraphs.filter { $0.pageBreakBefore == true }.count, 1)
        XCTAssertEqual(paragraphs[1].pageBreakBefore, true)
        XCTAssertNil(paragraphs[2].pageBreakBefore)
    }

    private func markedEditor() throws -> (EditorController, PageTextView, Int) {
        let editor = EditorController(model: model())
        let textView = try XCTUnwrap(
            editor.layoutManager.textContainers.first?.textView as? PageTextView)
        editor.textViewBecameActive(textView)
        return (editor, textView, targetStart(in: editor.textStorage))
    }
}
