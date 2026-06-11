import XCTest
import AppKit
@testable import LucerneKit

// Tests for the extensible-styles work (STYLES.md): the additive model fields,
// list ordering, the style-level underline / right-indent resolution, the S3
// redefinition invariants (direct formatting survives, no override bloat), and
// the copy-on-use style library.

final class StyleModelTests: XCTestCase {

    func testNewStyleFieldsRoundTripThroughJSON() throws {
        var model = DefaultDocuments.empty()
        model.styles["fine"] = ParagraphStyleDef(
            name: "Fine Print", font: "Helvetica", size: 9, underline: true,
            rightIndent: 36, order: 7.5, markdown: "p")
        let decoded = try DocumentCoding.decode(try DocumentCoding.encode(model))
        XCTAssertEqual(decoded, model)
        XCTAssertEqual(decoded.styles["fine"]?.underline, true)
        XCTAssertEqual(decoded.styles["fine"]?.rightIndent, 36)
        XCTAssertEqual(decoded.styles["fine"]?.order, 7.5)
    }

    func testAbsentNewFieldsDecodeAsNil() throws {
        // A v1 file that predates underline/rightIndent/order must load unchanged.
        let json = #"{ "name": "Body", "markdown": "p" }"#
        let def = try JSONDecoder().decode(ParagraphStyleDef.self, from: Data(json.utf8))
        XCTAssertNil(def.underline)
        XCTAssertNil(def.rightIndent)
        XCTAssertNil(def.order)
    }

    func testOrderedRolesFallBackToClassicOrderWithoutOrderFields() {
        // Strip the explicit orders → the traditional five-role order, extras after.
        var styles = DefaultDocuments.defaultStyles().mapValues { def -> ParagraphStyleDef in
            var def = def
            def.order = nil
            return def
        }
        styles["toc"] = ParagraphStyleDef(name: "Contents Entry", markdown: "p")
        XCTAssertEqual(LucerneDocumentModel.orderedStyleRoles(in: styles),
                       ["body", "heading1", "heading2", "listItem", "quote", "toc"])
    }

    func testExplicitOrderWinsAndInsertsBetween() {
        var styles = DefaultDocuments.defaultStyles()   // orders 0…4
        styles["legalese"] = ParagraphStyleDef(name: "Legalese", order: 0.5, markdown: "p")
        let roles = LucerneDocumentModel.orderedStyleRoles(in: styles)
        XCTAssertEqual(roles.first, "body")
        XCTAssertEqual(roles[1], "legalese", "order 0.5 sorts between body (0) and heading1 (1)")
        XCTAssertEqual(roles[2], "heading1")
    }

    func testNextStyleOrderAppends() {
        let model = DefaultDocuments.empty()   // orders 0…4
        XCTAssertEqual(model.nextStyleOrder(), 5)
    }

    func testVisualEqualityIgnoresOrder() {
        var a = ParagraphStyleDef(name: "Body", size: 12, order: 0, markdown: "p")
        var b = a
        b.order = 9
        XCTAssertTrue(a.visuallyEquals(b))
        b.size = 13
        XCTAssertFalse(a.visuallyEquals(b))
        a.order = nil
        XCTAssertNotEqual(a, b)
    }
}

final class StyleUnderlineAndIndentBridgeTests: XCTestCase {

    private func underlinedStyles() -> [String: ParagraphStyleDef] {
        var styles = DefaultDocuments.defaultStyles()
        styles["fine"] = ParagraphStyleDef(name: "Fine Print", font: "Helvetica", size: 9,
                                           underline: true, rightIndent: 36, markdown: "p")
        return styles
    }

    func testStyleLevelUnderlineAppliesAndRoundTripsWithoutOverrides() {
        let styles = underlinedStyles()
        let model = LucerneDocumentModel(
            page: .a4, styles: styles,
            body: [Paragraph(id: "p", style: "fine", runs: [Run(text: "all underlined")])],
            objects: [])
        let attributed = AttributedStringBuilder.attributedString(for: model)
        let underline = attributed.attribute(.underlineStyle, at: 0, effectiveRange: nil) as? Int
        XCTAssertEqual(underline, NSUnderlineStyle.single.rawValue, "the style supplies the underline")

        let restored = AttributedStringReader.paragraphs(from: attributed, styles: styles)
        XCTAssertNil(restored[0].runs.first?.underline,
                     "matching the style must not be stored as a run override")
    }

    func testRunCanSwitchUnderlineOffUnderAnUnderlinedStyle() {
        let styles = underlinedStyles()
        let model = LucerneDocumentModel(
            page: .a4, styles: styles,
            body: [Paragraph(id: "p", style: "fine", runs: [
                Run(text: "underlined "),
                Run(text: "plain", underline: false)
            ])],
            objects: [])
        let attributed = AttributedStringBuilder.attributedString(for: model)
        let plainStart = ("underlined " as NSString).length
        let value = attributed.attribute(.underlineStyle, at: plainStart, effectiveRange: nil) as? Int
        XCTAssertTrue(value == nil || value == 0, "the false override switches underline off")

        let restored = AttributedStringReader.paragraphs(from: attributed, styles: styles)
        let plainRun = restored[0].runs.first { $0.text == "plain" }
        XCTAssertEqual(plainRun?.underline, false, "the false override must round-trip explicitly")
    }

    func testStyleRightIndentAppliesAndDoesNotBecomeAnOverride() {
        let styles = underlinedStyles()
        let model = LucerneDocumentModel(
            page: .a4, styles: styles,
            body: [Paragraph(id: "p", style: "fine", runs: [Run(text: "narrow")])],
            objects: [])
        let attributed = AttributedStringBuilder.attributedString(for: model)
        let ps = attributed.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
        XCTAssertEqual(ps?.tailIndent ?? 0, -36, accuracy: 0.01)

        let restored = AttributedStringReader.paragraphs(from: attributed, styles: styles)
        XCTAssertNil(restored[0].indent?.right ?? nil,
                     "matching the style's rightIndent must not be stored per paragraph")
    }
}

/// The S3 invariants, tested as the exact composition the editor's engine runs:
/// read back with the OLD stylesheet (capturing direct formatting as diffs),
/// swap a definition, rebuild, read back with the NEW stylesheet.
final class StyleRedefinitionTests: XCTestCase {

    private func makeModel() -> LucerneDocumentModel {
        LucerneDocumentModel(
            page: .a4, styles: DefaultDocuments.defaultStyles(),
            body: [
                Paragraph(id: "p1", style: "body", runs: [
                    Run(text: "plain "),
                    Run(text: "fancy", italic: true),
                    Run(text: " end")
                ]),
                Paragraph(id: "p2", style: "heading1", runs: [Run(text: "Title")]),
                Paragraph(id: "p3", style: "body", runs: [Run(text: "big", size: 18)])
            ],
            objects: [])
    }

    private func redefinedBody() -> ParagraphStyleDef {
        ParagraphStyleDef(name: "Body", font: "Times New Roman", size: 14,
                          lineSpacing: 1.0, spaceAfter: 10, order: 0, markdown: "p")
    }

    private func runEngine(on model: LucerneDocumentModel,
                           replacing key: String,
                           with def: ParagraphStyleDef) -> (text: Bool, restored: [Paragraph]) {
        let storage = AttributedStringBuilder.attributedString(for: model)
        let captured = AttributedStringReader.paragraphs(from: storage, styles: model.styles)
        var newStyles = model.styles
        newStyles[key] = def
        var temp = model
        temp.styles = newStyles
        temp.body = captured
        let rebuilt = AttributedStringBuilder.attributedString(for: temp)
        let restored = AttributedStringReader.paragraphs(from: rebuilt, styles: newStyles)
        return (rebuilt.string == storage.string, restored)
    }

    func testTextAndIdsSurviveRedefinition() {
        let model = makeModel()
        let (sameText, restored) = runEngine(on: model, replacing: "body", with: redefinedBody())
        XCTAssertTrue(sameText, "the re-apply pass must not change a single character")
        XCTAssertEqual(restored.map(\.id), model.body.map(\.id))
        XCTAssertEqual(restored.map(\.style), model.body.map(\.style))
        XCTAssertEqual(restored.map(\.plainText), model.body.map(\.plainText))
    }

    func testDirectFormattingSurvivesWithoutOverrideBloat() {
        let model = makeModel()
        let (_, restored) = runEngine(on: model, replacing: "body", with: redefinedBody())

        // The hand-italicized word survives as exactly the run override it was…
        let italicRun = restored[0].runs.first { $0.italic == true }
        XCTAssertEqual(italicRun?.text, "fancy")

        // …and nothing else sprouted overrides pinning the OLD definition: the
        // paragraphs simply follow the new Body.
        for run in restored[0].runs {
            XCTAssertNil(run.font, "no run may pin the old face")
            XCTAssertNil(run.size, "no run may pin the old size")
        }
        XCTAssertNil(restored[0].lineSpacing)
        XCTAssertNil(restored[0].spaceAfter)

        // An explicit pre-existing override is still an override.
        XCTAssertEqual(restored[2].runs.first?.size, 18)

        // Paragraphs of other roles are untouched.
        XCTAssertEqual(restored[1].style, "heading1")
        XCTAssertTrue(restored[1].runs.allSatisfy { $0.font == nil && $0.size == nil && $0.bold == nil })
    }
}

final class StyleLibraryTests: XCTestCase {

    private func temporaryLibrary() -> StyleLibrary {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("styles.json")
        return StyleLibrary(fileURL: url)
    }

    func testMissingFileLoadsEmpty() {
        XCTAssertTrue(temporaryLibrary().load().isEmpty)
    }

    func testCorruptFileLoadsEmpty() throws {
        let library = temporaryLibrary()
        try FileManager.default.createDirectory(at: library.fileURL.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try Data("definitely { not json".utf8).write(to: library.fileURL)
        XCTAssertTrue(library.load().isEmpty)
    }

    func testSaveLoadRoundTrip() {
        let library = temporaryLibrary()
        let styles = ["legal": ParagraphStyleDef(name: "Legalese", size: 9, order: 0, markdown: "p")]
        library.save(styles)
        XCTAssertEqual(library.load(), styles)
    }

    func testInterchangeRejectsWrongFormat() throws {
        let wrong = #"{ "format": "something-else", "formatVersion": 1, "styles": {} }"#
        XCTAssertThrowsError(try StyleLibrary.decode(Data(wrong.utf8)))
        let future = #"{ "format": "lucerne-styles", "formatVersion": 99, "styles": {} }"#
        XCTAssertThrowsError(try StyleLibrary.decode(Data(future.utf8)))
        let good = try StyleLibrary.encode(["k": ParagraphStyleDef(name: "K", markdown: "p")])
        XCTAssertEqual(try StyleLibrary.decode(good).count, 1)
    }

    func testSaveStylePreservesLibraryOrderOnUpdateAndAppendsNew() {
        let library = temporaryLibrary()
        library.save(["a": ParagraphStyleDef(name: "A", order: 3, markdown: "p")])

        let updatedA = ParagraphStyleDef(name: "A", size: 20, order: 99, markdown: "p")
        library.saveStyle(updatedA, forKey: "a")
        XCTAssertEqual(library.load()["a"]?.order, 3, "pushing must not reshuffle the library")
        XCTAssertEqual(library.load()["a"]?.size, 20)

        library.saveStyle(ParagraphStyleDef(name: "B", markdown: "p"), forKey: "b")
        XCTAssertEqual(library.load()["b"]?.order, 4, "a new entry goes after everything else")
    }

    func testSyncStateMatrix() {
        let doc = ParagraphStyleDef(name: "Body", size: 12, order: 0, markdown: "p")
        XCTAssertEqual(StyleLibrary.syncState(documentDef: doc, libraryDef: nil), .notInLibrary)

        var lib = doc
        lib.order = 9
        XCTAssertEqual(StyleLibrary.syncState(documentDef: doc, libraryDef: lib), .matches,
                       "order is presentational — it must not read as a difference")

        lib.size = 13
        XCTAssertEqual(StyleLibrary.syncState(documentDef: doc, libraryDef: lib), .differs)
    }
}

final class StarterLibraryTests: XCTestCase {

    private func temporaryLibrary() -> StyleLibrary {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("styles.json")
        return StyleLibrary(fileURL: url)
    }

    func testStarterStylesAreACompleteStylesheetMirroringTheCoreRoles() {
        let starter = DefaultDocuments.starterLibraryStyles()
        XCTAssertGreaterThanOrEqual(starter.count, 10)

        // The library IS the new-letter stylesheet (S6), so it carries the
        // classic five — as exact visual mirrors of the app defaults at seed
        // time, never silent forks.
        for (key, def) in DefaultDocuments.defaultStyles() {
            guard let mirrored = starter[key] else {
                return XCTFail("\(key) must be in the starter library")
            }
            XCTAssertTrue(mirrored.visuallyEquals(def),
                          "\(key) must match the app default at seed time")
        }

        let validHints: Set<String> = ["p", "h1", "h2", "h3", "h4", "li", "blockquote", "code"]
        for (key, def) in starter {
            XCTAssertTrue(validHints.contains(def.markdown), "\(key) has hint \(def.markdown)")
            XCTAssertNotNil(def.order, "\(key) needs a stable library position")
            XCTAssertFalse(def.name.isEmpty)
        }
        XCTAssertEqual(Set(starter.values.map(\.name)).count, starter.count,
                       "display names must be unique")

        // The heading ramp walks ⌃⌘2–⌃⌘4 in descending sizes.
        let roles = LucerneDocumentModel.orderedStyleRoles(in: starter)
        XCTAssertEqual(Array(roles.prefix(4)), ["body", "heading1", "heading2", "heading3"])
        XCTAssertEqual(starter["heading3"]?.markdown, "h3",
                       "Heading 3 joins the navigator/ToC heading ramp")
        XCTAssertEqual(starter["code"]?.font, "Menlo")
        XCTAssertEqual(starter["code"]?.markdown, "code")
    }

    func testCodeAndH4HintsExport() {
        var model = DefaultDocuments.empty()
        model.styles["code"] = ParagraphStyleDef(name: "Code", font: "Menlo", markdown: "code")
        model.styles["heading4"] = ParagraphStyleDef(name: "Heading 4", size: 12, bold: true, markdown: "h4")
        model.body = [
            Paragraph(id: "p1", style: "heading4", runs: [Run(text: "Deep heading")]),
            Paragraph(id: "p2", style: "code", runs: [Run(text: "let x = 1")])
        ]
        let md = MarkdownExporter.export(model)
        XCTAssertTrue(md.contains("#### Deep heading"),
                      "an h4-hinted style exports as a level-4 heading")
        XCTAssertTrue(md.contains("    let x = 1"),
                      "a code-hinted paragraph exports as an indented code block")
    }

    func testSeedHappensOnlyWhenNoFileExists() {
        let library = temporaryLibrary()
        library.seedStarterLibraryIfNeeded()
        XCTAssertEqual(library.load(), DefaultDocuments.starterLibraryStyles())

        // Emptying the library leaves its file behind — re-seeding must not
        // resurrect the starter set against the user's wishes.
        library.save([:])
        library.seedStarterLibraryIfNeeded()
        XCTAssertTrue(library.load().isEmpty, "an emptied library stays empty")
    }

    func testSeededDocumentsGetExactlyTheLibrary() {
        let library = temporaryLibrary()
        library.save([
            "body": ParagraphStyleDef(name: "Body", font: "Palatino", size: 12, order: 1, markdown: "p"),
            "fancy": ParagraphStyleDef(name: "Fancy", order: 0, markdown: "p")
        ])
        let seeded = library.seededStyles()
        XCTAssertEqual(seeded, library.load(),
                       "what the Library window shows is what a new letter gets — nothing more")
        XCTAssertEqual(LucerneDocumentModel.orderedStyleRoles(in: seeded), ["fancy", "body"],
                       "the library's own order carries into new letters")
    }

    func testEmptiedLibraryFallsBackToBuiltInDefaults() {
        let library = temporaryLibrary()
        library.save([:])
        XCTAssertEqual(library.seededStyles(), DefaultDocuments.defaultStyles())
    }

    func testMissingBodyIsMaterializedFirst() {
        let library = temporaryLibrary()
        library.save(["fancy": ParagraphStyleDef(name: "Fancy", order: 0, markdown: "p")])
        let seeded = library.seededStyles()
        XCTAssertNotNil(seeded["body"], "body is the format's fallback anchor and must exist")
        XCTAssertEqual(LucerneDocumentModel.orderedStyleRoles(in: seeded).first, "body")
    }
}

final class StyleSnapshotSafetyTests: XCTestCase {

    /// A paragraph whose role has no definition (dangling after a hand-edit or
    /// an undone style creation) must still produce a conformant file: the save
    /// path materializes a definition for it.
    func testMarkdownExportTreatsUnknownRoleAsBody() {
        var model = DefaultDocuments.empty()
        model.body = [Paragraph(id: "p", style: "ghost", runs: [Run(text: "hello")])]
        let md = MarkdownExporter.export(model)
        XCTAssertTrue(md.contains("hello"))
    }

    func testCustomHeadingStyleJoinsTheOutlineExport() {
        var model = DefaultDocuments.empty()
        model.styles["chapter"] = ParagraphStyleDef(name: "Chapter", size: 30, markdown: "h3")
        model.body = [Paragraph(id: "p", style: "chapter", runs: [Run(text: "One")])]
        XCTAssertTrue(MarkdownExporter.export(model).contains("### One"),
                      "a user style with an h3 hint exports as a heading")
    }
}
