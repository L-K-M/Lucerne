import XCTest
import AppKit
@testable import LucerneKit

final class PasteNormalizationTests: XCTestCase {
    /// AppKit's RTF reader on macOS 15 and earlier spells each list item's
    /// marker into the text; later releases leave it to the list attribute.
    /// Either way the pasted text must not keep a marker Lucerne no longer
    /// draws (it drops the pasted list structure).
    func testSpelledOutListMarkersFromOlderRTFReadersAreDropped() {
        let model = LucerneDocumentModel(
            page: .a4, styles: DefaultDocuments.defaultStyles(),
            body: [Paragraph(id: "destination", style: "body", runs: [Run(text: "x")])],
            objects: [])
        func listStyle(_ format: NSTextList.MarkerFormat, start: Int = 1) -> NSParagraphStyle {
            let style = NSMutableParagraphStyle()
            let list = NSTextList(markerFormat: format, options: 0)
            list.startingItemNumber = start
            style.textLists = [list]
            return style
        }
        let source = NSMutableAttributedString()
        source.append(NSAttributedString(string: "\t•\tFirst\n",
                                         attributes: [.paragraphStyle: listStyle(.disc)]))
        source.append(NSAttributedString(string: "\t•\tSecond\n",
                                         attributes: [.paragraphStyle: listStyle(.disc)]))
        source.append(NSAttributedString(string: "\t2.\tNumbered\n",
                                         attributes: [.paragraphStyle: listStyle(
                                             NSTextList.MarkerFormat("{decimal}."), start: 2)]))
        // Not a marker of its list, and not in a list: both stay as typed.
        source.append(NSAttributedString(string: "\tName\tValue\n",
                                         attributes: [.paragraphStyle: listStyle(.disc)]))
        source.append(NSAttributedString(string: "\t•\tPlain"))

        let normalized = PasteNormalizer.normalize(source, destination: [:], model: model)

        XCTAssertEqual(normalized.string,
                       "First\nSecond\nNumbered\n\tName\tValue\n\t•\tPlain")
    }

    func testRichPasteImmediatelyMatchesLucerneRepresentableFormatting() throws {
        let model = LucerneDocumentModel(
            page: .a4, styles: DefaultDocuments.defaultStyles(),
            body: [Paragraph(id: "destination", style: "body",
                             runs: [Run(text: "Replace me")])],
            objects: [])
        let editor = EditorController(model: model)
        let textView = try XCTUnwrap(
            editor.layoutManager.textContainers.first?.textView as? PageTextView)
        textView.setSelectedRange(NSRange(location: 0, length: editor.textStorage.length))
        editor.textViewBecameActive(textView)

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        paragraphStyle.paragraphSpacing = 9
        paragraphStyle.textLists = [NSTextList(markerFormat: .disc, options: 0)]
        let source = NSMutableAttributedString(
            string: "First\nSecond",
            attributes: [
                .font: NSFont.boldSystemFont(ofSize: 18),
                .foregroundColor: NSColor.systemRed,
                .underlineStyle: NSUnderlineStyle.single.rawValue,
                .paragraphStyle: paragraphStyle,
                .backgroundColor: NSColor.systemYellow,
                .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                .link: URL(string: "https://example.com")!
            ])
        let data = try source.data(
            from: NSRange(location: 0, length: source.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
        let pasteboard = NSPasteboard(name: NSPasteboard.Name(
            "ch.lkmc.lucerne.tests.rich-paste.\(UUID().uuidString)"))
        pasteboard.clearContents()
        pasteboard.declareTypes([.rtf], owner: nil)
        XCTAssertTrue(pasteboard.setData(data, forType: .rtf))

        let decoded = try XCTUnwrap(PasteNormalizer.read(from: pasteboard, type: .rtf))
        let normalized = PasteNormalizer.normalize(
            decoded,
            destination: editor.textStorage.attributes(at: 0, effectiveRange: nil),
            model: model)
        let normalizedFont = try XCTUnwrap(
            normalized.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        XCTAssertEqual(normalizedFont.pointSize, 18, accuracy: 0.01)

        // AppKit chooses its legacy RTF alias for this one-argument path. Exercise
        // the same dispatch Command-V uses rather than calling our override directly.
        XCTAssertTrue(textView.readSelection(from: pasteboard))
        XCTAssertEqual(editor.textStorage.string, "First\nSecond")

        let whole = NSRange(location: 0, length: editor.textStorage.length)
        for key: NSAttributedString.Key in [.backgroundColor, .strikethroughStyle, .link] {
            var found = false
            editor.textStorage.enumerateAttribute(key, in: whole, options: []) {
                value, _, stop in
                if value != nil {
                    found = true
                    stop.pointee = true
                }
            }
            XCTAssertFalse(found, "unsupported attribute \(key.rawValue) must disappear immediately")
        }

        let firstAttributes = editor.textStorage.attributes(at: 0, effectiveRange: nil)
        let font = try XCTUnwrap(firstAttributes[.font] as? NSFont)
        XCTAssertTrue(FontResolver.isBold(font))
        XCTAssertEqual(font.pointSize, 18, accuracy: 0.01)
        XCTAssertEqual((firstAttributes[.foregroundColor] as? NSColor)?.lucerneHexString,
                       NSColor.systemRed.lucerneHexString)
        XCTAssertEqual(firstAttributes[.underlineStyle] as? Int,
                       NSUnderlineStyle.single.rawValue)
        let pastedStyle = try XCTUnwrap(firstAttributes[.paragraphStyle] as? NSParagraphStyle)
        XCTAssertEqual(pastedStyle.alignment, .center)
        XCTAssertEqual(pastedStyle.paragraphSpacing, 9, accuracy: 0.01)
        XCTAssertTrue(pastedStyle.textLists.isEmpty)
        XCTAssertTrue(pastedStyle.textBlocks.isEmpty)

        let firstID = editor.textStorage.attribute(
            .lucerneParagraphID, at: 0, effectiveRange: nil) as? String
        let secondStart = (editor.textStorage.string as NSString).range(of: "Second").location
        let secondID = editor.textStorage.attribute(
            .lucerneParagraphID, at: secondStart, effectiveRange: nil) as? String
        XCTAssertEqual(firstAttributes[.lucerneStyleRole] as? String, "body")
        XCTAssertNotNil(firstID)
        XCTAssertNotNil(secondID)
        XCTAssertNotEqual(firstID, secondID)

        let snapshot = editor.snapshotModel()
        XCTAssertEqual(snapshot.body.map(\.plainText), ["First", "Second"])
        XCTAssertEqual(Set(snapshot.body.map(\.id)).count, 2)
        XCTAssertEqual(snapshot.body[0].align, "center")
        XCTAssertEqual(snapshot.body[0].spaceAfter, 9)
        XCTAssertNil(snapshot.body[0].tabStops)
        XCTAssertEqual(snapshot.body[0].runs.first?.bold, true)
        XCTAssertEqual(snapshot.body[0].runs.first?.underline, true)
    }

    func testNormalizerDropsAttachmentsAndRemintsForeignStructure() throws {
        let model = LucerneDocumentModel(
            page: .a4, styles: DefaultDocuments.defaultStyles(),
            body: [Paragraph(id: "destination", style: "body", runs: [Run(text: "")])],
            objects: [])
        let source = NSMutableAttributedString(
            string: "A\u{FFFC}\nB\n",
            attributes: [
                .font: NSFont.systemFont(ofSize: 13),
                .paragraphStyle: NSParagraphStyle.default,
                .lucerneStyleRole: "heading1",
                .lucerneParagraphID: "foreign-id",
                .lucernePageBreakBefore: true,
                .backgroundColor: NSColor.yellow
            ])
        source.addAttribute(.attachment, value: NSTextAttachment(),
                            range: NSRange(location: 1, length: 1))
        source.addAttribute(.lucerneTrailingParagraphID, value: "foreign-trailing",
                            range: NSRange(location: source.length - 1, length: 1))
        let destination = AttributedStringBuilder.typingAttributes(
            role: "body", in: model, paragraphID: "destination")

        let normalized = PasteNormalizer.normalize(
            source, destination: destination, model: model)

        XCTAssertEqual(normalized.string, "A\nB\n")
        let firstID = normalized.attribute(
            .lucerneParagraphID, at: 0, effectiveRange: nil) as? String
        let secondID = normalized.attribute(
            .lucerneParagraphID, at: 2, effectiveRange: nil) as? String
        let trailingID = normalized.attribute(
            .lucerneTrailingParagraphID, at: normalized.length - 1,
            effectiveRange: nil) as? String
        XCTAssertEqual(firstID, "destination")
        XCTAssertNotNil(secondID)
        XCTAssertNotEqual(secondID, firstID)
        XCTAssertNotNil(trailingID)
        XCTAssertNotEqual(trailingID, "foreign-trailing")
        XCTAssertEqual(normalized.attribute(
            .lucerneStyleRole, at: 2, effectiveRange: nil) as? String, "body")
        XCTAssertNil(normalized.attribute(.attachment, at: 0, effectiveRange: nil))
        XCTAssertNil(normalized.attribute(.backgroundColor, at: 0, effectiveRange: nil))
        XCTAssertNil(normalized.attribute(.lucernePageBreakBefore,
                                          at: 0, effectiveRange: nil))
    }

    func testAttachmentOnlyRichTextFallsBackToPlainText() throws {
        let model = LucerneDocumentModel(
            page: .a4, styles: DefaultDocuments.defaultStyles(),
            body: [Paragraph(id: "destination", style: "body",
                             runs: [Run(text: "Original")])],
            objects: [])
        let editor = EditorController(model: model)
        let textView = try XCTUnwrap(
            editor.layoutManager.textContainers.first?.textView as? PageTextView)
        textView.setSelectedRange(NSRange(location: 0, length: editor.textStorage.length))

        let attachment = NSTextAttachment(data: Data([0, 1]), ofType: "public.data")
        let source = NSAttributedString(attachment: attachment)
        let data = try source.data(
            from: NSRange(location: 0, length: source.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtfd])
        let pasteboard = NSPasteboard(name: NSPasteboard.Name(
            "ch.lkmc.lucerne.tests.attachment-fallback.\(UUID().uuidString)"))
        pasteboard.declareTypes([.rtfd, .string], owner: nil)
        XCTAssertTrue(pasteboard.setData(data, forType: .rtfd))
        XCTAssertTrue(pasteboard.setString("Fallback", forType: .string))

        XCTAssertTrue(textView.readSelection(from: pasteboard))
        XCTAssertEqual(editor.textStorage.string, "Fallback")
    }

    func testNormalizerPreservesDestinationPageListAndTableStructure() throws {
        let model = LucerneDocumentModel(
            page: .a4, styles: DefaultDocuments.defaultStyles(),
            body: [Paragraph(id: "destination", style: "body", runs: [Run(text: "")])],
            objects: [])
        let list = ListItemModel(list: "destination-list", ordered: false,
                                 marker: "disc", level: 2)
        var destination = AttributedStringBuilder.typingAttributes(
            role: "body", in: model, paragraphID: "destination", list: list)
        let table = AttributedStringBuilder.makeTextTable(columns: 2)
        let block = AttributedStringBuilder.makeTableBlock(
            table: table, row: 0, column: 0, rowSpan: 1, columnSpan: 1,
            widthPercent: 50)
        let destinationStyle = (destination[.paragraphStyle] as? NSParagraphStyle)?
            .mutableCopy() as? NSMutableParagraphStyle ?? NSMutableParagraphStyle()
        destinationStyle.textBlocks = [block]
        destination[.paragraphStyle] = destinationStyle
        destination[.lucernePageBreakBefore] = true

        let importedStyle = NSMutableParagraphStyle()
        importedStyle.textLists = [NSTextList(markerFormat: .decimal, options: 0)]
        let source = NSAttributedString(
            string: "First\nSecond",
            attributes: [
                .paragraphStyle: importedStyle,
                .lucerneParagraphID: "foreign",
                .lucerneStyleRole: "heading1",
                .lucernePageBreakBefore: true
            ])

        let normalized = PasteNormalizer.normalize(
            source, destination: destination, model: model)
        let secondStart = (normalized.string as NSString).range(of: "Second").location
        let firstID = normalized.attribute(
            .lucerneParagraphID, at: 0, effectiveRange: nil) as? String
        let secondID = normalized.attribute(
            .lucerneParagraphID, at: secondStart, effectiveRange: nil) as? String

        XCTAssertEqual(firstID, "destination")
        XCTAssertNotEqual(secondID, firstID)
        XCTAssertEqual(ListItemCodec.decode(normalized.attribute(
            .lucerneList, at: 0, effectiveRange: nil)), list)
        XCTAssertEqual(ListItemCodec.decode(normalized.attribute(
            .lucerneList, at: secondStart, effectiveRange: nil)), list)
        XCTAssertEqual(normalized.attribute(
            .lucernePageBreakBefore, at: 0, effectiveRange: nil) as? Bool, true)
        XCTAssertNil(normalized.attribute(
            .lucernePageBreakBefore, at: secondStart, effectiveRange: nil))

        for location in [0, secondStart] {
            let style = try XCTUnwrap(normalized.attribute(
                .paragraphStyle, at: location, effectiveRange: nil) as? NSParagraphStyle)
            XCTAssertTrue(style.textLists.isEmpty)
            XCTAssertEqual(style.textBlocks.count, 1)
            XCTAssertEqual(style.headIndent, CGFloat(ListGeometry.contentIndent(level: 2)),
                           accuracy: 0.01)
            XCTAssertEqual(style.firstLineHeadIndent,
                           CGFloat(ListGeometry.contentIndent(level: 2)), accuracy: 0.01)
        }
    }

    func testNormalizedPasteIsUndoable() throws {
        let model = LucerneDocumentModel(
            page: .a4, styles: DefaultDocuments.defaultStyles(),
            body: [Paragraph(id: "destination", style: "body",
                             runs: [Run(text: "Original")])],
            objects: [])
        let editor = EditorController(model: model)
        let textView = try XCTUnwrap(
            editor.layoutManager.textContainers.first?.textView as? PageTextView)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = editor.canvasView
        XCTAssertTrue(window.makeFirstResponder(textView))
        textView.setSelectedRange(NSRange(location: 0, length: editor.textStorage.length))

        let source = NSAttributedString(
            string: "Pasted",
            attributes: [.font: NSFont.boldSystemFont(ofSize: 16),
                         .backgroundColor: NSColor.yellow])
        let data = try source.data(
            from: NSRange(location: 0, length: source.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
        let pasteboard = NSPasteboard(name: NSPasteboard.Name(
            "ch.lkmc.lucerne.tests.undo-paste.\(UUID().uuidString)"))
        pasteboard.declareTypes([.rtf], owner: nil)
        XCTAssertTrue(pasteboard.setData(data, forType: .rtf))

        XCTAssertTrue(textView.readSelection(from: pasteboard, type: .rtf))
        XCTAssertEqual(editor.textStorage.string, "Pasted")
        let undoManager = try XCTUnwrap(textView.undoManager)
        XCTAssertTrue(undoManager.canUndo)

        undoManager.undo()
        XCTAssertEqual(editor.textStorage.string, "Original")
        undoManager.redo()
        XCTAssertEqual(editor.textStorage.string, "Pasted")
        XCTAssertNil(editor.textStorage.attribute(.backgroundColor,
                                                   at: 0, effectiveRange: nil))
    }

    func testMultilinePasteRestampsTheMergedSuffixWithItsNewParagraphID() throws {
        let model = LucerneDocumentModel(
            page: .a4, styles: DefaultDocuments.defaultStyles(),
            body: [Paragraph(id: "destination", style: "body",
                             runs: [Run(text: "BeforeAfter")])],
            objects: [])
        let editor = EditorController(model: model)
        let textView = try XCTUnwrap(
            editor.layoutManager.textContainers.first?.textView as? PageTextView)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = editor.canvasView
        XCTAssertTrue(window.makeFirstResponder(textView))
        textView.setSelectedRange(NSRange(location: 6, length: 0))
        editor.textViewBecameActive(textView)

        let source = NSAttributedString(
            string: "One\nTwo",
            attributes: [.font: NSFont.systemFont(ofSize: 12)])
        let data = try source.data(
            from: NSRange(location: 0, length: source.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
        let pasteboard = NSPasteboard(name: NSPasteboard.Name(
            "ch.lkmc.lucerne.tests.merged-paste.\(UUID().uuidString)"))
        pasteboard.declareTypes([.rtf], owner: nil)
        XCTAssertTrue(pasteboard.setData(data, forType: .rtf))

        XCTAssertTrue(textView.readSelection(from: pasteboard, type: .rtf))
        XCTAssertEqual(editor.textStorage.string, "BeforeOne\nTwoAfter")

        let secondStart = (editor.textStorage.string as NSString).range(of: "TwoAfter").location
        let secondParagraph = NSRange(
            location: secondStart,
            length: editor.textStorage.length - secondStart)
        let secondID = try XCTUnwrap(editor.textStorage.attribute(
            .lucerneParagraphID, at: secondParagraph.location,
            effectiveRange: nil) as? String)
        for location in secondParagraph.location..<NSMaxRange(secondParagraph) {
            XCTAssertEqual(editor.textStorage.attribute(
                .lucerneParagraphID, at: location, effectiveRange: nil) as? String,
                           secondID, "the joined suffix must belong to the pasted paragraph")
        }
        XCTAssertEqual(textView.typingAttributes[.lucerneParagraphID] as? String,
                       secondID)

        let undoManager = try XCTUnwrap(textView.undoManager)
        undoManager.undo()
        XCTAssertEqual(editor.textStorage.string, "BeforeAfter")
        for location in 0..<editor.textStorage.length {
            XCTAssertEqual(editor.textStorage.attribute(
                .lucerneParagraphID, at: location, effectiveRange: nil) as? String,
                           "destination")
        }

        undoManager.redo()
        XCTAssertEqual(editor.textStorage.string, "BeforeOne\nTwoAfter")
        let redoneID = try XCTUnwrap(editor.textStorage.attribute(
            .lucerneParagraphID, at: secondParagraph.location,
            effectiveRange: nil) as? String)
        for location in secondParagraph.location..<NSMaxRange(secondParagraph) {
            XCTAssertEqual(editor.textStorage.attribute(
                .lucerneParagraphID, at: location, effectiveRange: nil) as? String,
                           redoneID)
        }
    }

    func testJoinedPastePreservesTheDistinctTrailingEmptyParagraph() throws {
        let trailingList = ListItemModel(list: "trailing-list", ordered: false,
                                         marker: "disc", level: 1)
        let model = LucerneDocumentModel(
            page: .a4, styles: DefaultDocuments.defaultStyles(),
            body: [
                Paragraph(id: "destination", style: "body",
                          runs: [Run(text: "BeforeAfter")]),
                Paragraph(id: "trailing", style: "heading1", list: trailingList,
                          runs: [Run(text: "")])
            ], objects: [])
        let editor = EditorController(model: model)
        let textView = try XCTUnwrap(
            editor.layoutManager.textContainers.first?.textView as? PageTextView)
        textView.setSelectedRange(NSRange(location: 6, length: 0))

        XCTAssertTrue(textView.readSelection(
            from: try richPasteboard(containing: "One\nTwo"), type: .rtf))
        XCTAssertEqual(editor.textStorage.string, "BeforeOne\nTwoAfter\n")

        let terminator = editor.textStorage.length - 1
        XCTAssertEqual(editor.textStorage.attribute(
            .lucerneTrailingParagraphID, at: terminator,
            effectiveRange: nil) as? String, "trailing")
        XCTAssertEqual(editor.textStorage.attribute(
            .lucerneTrailingStyleRole, at: terminator,
            effectiveRange: nil) as? String, "heading1")
        XCTAssertEqual(ListItemCodec.decode(editor.textStorage.attribute(
            .lucerneTrailingList, at: terminator, effectiveRange: nil)), trailingList)

        let snapshot = editor.snapshotModel()
        XCTAssertEqual(snapshot.body.map(\.plainText), ["BeforeOne", "TwoAfter", ""])
        XCTAssertEqual(snapshot.body.map(\.id).last, "trailing")
        XCTAssertEqual(snapshot.body.map(\.style).last, "heading1")
        XCTAssertEqual(snapshot.body.last?.list, trailingList)
    }

    func testNewlineTerminatedPastePreservesTheUntouchedFollowingParagraph() throws {
        let list = ListItemModel(list: "following-list", ordered: true,
                                 marker: "decimal", level: 1)
        let model = LucerneDocumentModel(
            page: .a4, styles: DefaultDocuments.defaultStyles(),
            body: [
                Paragraph(id: "first", style: "body", runs: [Run(text: "A")]),
                Paragraph(id: "following", style: "heading1", pageBreakBefore: true,
                          list: list, runs: [Run(text: "B")])
            ], objects: [])
        let editor = EditorController(model: model)
        let textView = try XCTUnwrap(
            editor.layoutManager.textContainers.first?.textView as? PageTextView)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = editor.canvasView
        XCTAssertTrue(window.makeFirstResponder(textView))

        let pasteboard = try richPasteboard(containing: "X\n")
        textView.setSelectedRange(NSRange(location: 0, length: 2))
        XCTAssertTrue(textView.readSelection(from: pasteboard, type: .rtf))
        XCTAssertEqual(editor.textStorage.string, "X\nB")
        assertFollowingParagraph(in: editor, startsAt: 2, expectedList: list)

        let undoManager = try XCTUnwrap(textView.undoManager)
        undoManager.undo()
        XCTAssertEqual(editor.textStorage.string, "A\nB")
        assertFollowingParagraph(in: editor, startsAt: 2, expectedList: list)
        undoManager.redo()
        XCTAssertEqual(editor.textStorage.string, "X\nB")
        assertFollowingParagraph(in: editor, startsAt: 2, expectedList: list)
    }

    func testInsertingCompleteParagraphBeforeAnotherUsesANewIdentity() throws {
        let model = LucerneDocumentModel(
            page: .a4, styles: DefaultDocuments.defaultStyles(),
            body: [
                Paragraph(id: "first", style: "body", runs: [Run(text: "A")]),
                Paragraph(id: "following", style: "body", pageBreakBefore: true,
                          runs: [Run(text: "B")])
            ], objects: [])
        let editor = EditorController(model: model)
        let textView = try XCTUnwrap(
            editor.layoutManager.textContainers.first?.textView as? PageTextView)
        textView.setSelectedRange(NSRange(location: 2, length: 0))

        XCTAssertTrue(textView.readSelection(
            from: try richPasteboard(containing: "X\n"), type: .rtf))
        XCTAssertEqual(editor.textStorage.string, "A\nX\nB")
        let snapshot = editor.snapshotModel()
        XCTAssertEqual(snapshot.body.map(\.id).last, "following")
        XCTAssertEqual(snapshot.body.last?.pageBreakBefore, true)
        XCTAssertEqual(Set(snapshot.body.map(\.id)).count, 3)
        XCTAssertNil(snapshot.body[1].pageBreakBefore)
    }

    /// Pasting into the trailing empty break paragraph goes through the
    /// readSelection path rather than insertText: the pasted first paragraph must
    /// inherit the sentinel's break, role, id, and list, and the carrier must go.
    private func trailingBreakEditor() throws -> (EditorController, PageTextView) {
        let model = LucerneDocumentModel(
            page: .a4, styles: DefaultDocuments.defaultStyles(),
            body: [
                Paragraph(id: "before", style: "body", runs: [Run(text: "Before")]),
                Paragraph(id: "break", style: "body", pageBreakBefore: true,
                          runs: [Run(text: "")])
            ], objects: [])
        let editor = EditorController(model: model)
        let textView = try XCTUnwrap(
            editor.layoutManager.textContainers.last?.textView as? PageTextView)
        textView.setSelectedRange(NSRange(location: editor.textStorage.length, length: 0))
        editor.textViewBecameActive(textView)
        return (editor, textView)
    }

    func testPasteIntoTrailingBreakParagraphTransfersBreakAndIdentity() throws {
        let (editor, textView) = try trailingBreakEditor()

        XCTAssertTrue(textView.readSelection(
            from: try richPasteboard(containing: "Pasted"), type: .rtf))

        XCTAssertEqual(editor.textStorage.string, "Before\nPasted")
        let snapshot = editor.snapshotModel()
        XCTAssertEqual(snapshot.body.map(\.plainText), ["Before", "Pasted"])
        XCTAssertEqual(snapshot.body.last?.id, "break")
        XCTAssertEqual(snapshot.body.last?.pageBreakBefore, true)
    }

    func testMultiParagraphPasteIntoTrailingBreakParagraphKeepsBreakOnFirst() throws {
        let (editor, textView) = try trailingBreakEditor()

        XCTAssertTrue(textView.readSelection(
            from: try richPasteboard(containing: "One\nTwo"), type: .rtf))

        XCTAssertEqual(editor.textStorage.string, "Before\nOne\nTwo")
        let snapshot = editor.snapshotModel()
        XCTAssertEqual(snapshot.body.map(\.plainText), ["Before", "One", "Two"])
        XCTAssertEqual(snapshot.body[1].id, "break")
        XCTAssertEqual(snapshot.body[1].pageBreakBefore, true)
        XCTAssertNil(snapshot.body[2].pageBreakBefore)
    }

    private func richPasteboard(containing string: String) throws -> NSPasteboard {
        let source = NSAttributedString(
            string: string, attributes: [.font: NSFont.systemFont(ofSize: 12)])
        let data = try source.data(
            from: NSRange(location: 0, length: source.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
        let pasteboard = NSPasteboard(name: NSPasteboard.Name(
            "ch.lkmc.lucerne.tests.boundary-paste.\(UUID().uuidString)"))
        pasteboard.declareTypes([.rtf], owner: nil)
        XCTAssertTrue(pasteboard.setData(data, forType: .rtf))
        return pasteboard
    }

    private func assertFollowingParagraph(
        in editor: EditorController,
        startsAt location: Int,
        expectedList: ListItemModel,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(editor.textStorage.attribute(
            .lucerneParagraphID, at: location, effectiveRange: nil) as? String,
                       "following", file: file, line: line)
        XCTAssertEqual(editor.textStorage.attribute(
            .lucerneStyleRole, at: location, effectiveRange: nil) as? String,
                       "heading1", file: file, line: line)
        XCTAssertEqual(ListItemCodec.decode(editor.textStorage.attribute(
            .lucerneList, at: location, effectiveRange: nil)),
                       expectedList, file: file, line: line)
        XCTAssertEqual(editor.textStorage.attribute(
            .lucernePageBreakBefore, at: location, effectiveRange: nil) as? Bool,
                       true, file: file, line: line)
    }
}
