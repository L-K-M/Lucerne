import Foundation

// Factory helpers for new documents and the default style table. The style table
// mirrors lucerne-plan.md §7 so files are self-contained and user-customisable.
public enum DefaultDocuments {

    /// The standard ClarisWorks-ish stylesheet: Body, two headings, a list item,
    /// and a block quote. Each role carries its markdown export hint (D3) and an
    /// explicit `order` so the UI lists are stable (STYLES.md S5).
    public static func defaultStyles() -> [String: ParagraphStyleDef] {
        [
            "body": ParagraphStyleDef(
                name: "Body", font: "Helvetica", size: 12,
                lineSpacing: 1.2, spaceAfter: 6, order: 0, markdown: "p"),
            "heading1": ParagraphStyleDef(
                name: "Heading 1", font: "Helvetica", size: 24, bold: true,
                spaceBefore: 18, spaceAfter: 8, order: 1, markdown: "h1"),
            "heading2": ParagraphStyleDef(
                name: "Heading 2", font: "Helvetica", size: 18, bold: true,
                spaceBefore: 14, spaceAfter: 6, order: 2, markdown: "h2"),
            "listItem": ParagraphStyleDef(
                name: "List Item", font: "Helvetica", size: 12,
                leftIndent: 24, order: 3, markdown: "li"),
            "quote": ParagraphStyleDef(
                name: "Block Quote", font: "Helvetica", size: 12, italic: true,
                leftIndent: 36, order: 4, markdown: "blockquote")
        ]
    }

    /// The traditional menu order of the classic five roles. Files that predate
    /// the per-style `order` member sort by this (see
    /// `LucerneDocumentModel.orderedStyleRoles`); new documents carry explicit
    /// orders instead.
    public static let styleRoleOrder = ["body", "heading1", "heading2", "listItem", "quote"]

    /// The starter collection a brand-new style library is seeded with
    /// (STYLES.md S6). Because **the library IS the stylesheet new letters
    /// start with** — what the Style Library window shows is exactly what a
    /// new document gets, contents and order alike — this is a *complete*
    /// stylesheet: the classic five (exact visual mirrors of `defaultStyles()`,
    /// never silent forks) plus the additions that earn their place by being
    /// applied repeatedly. Headings sit on adjacent positions so ⌃⌘2–⌃⌘4 walk
    /// the ramp (24 / 18 / 14 pt; all heading hints join the navigator + ToC).
    public static func starterLibraryStyles() -> [String: ParagraphStyleDef] {
        // The classic five, mirrored with their library positions…
        var styles = defaultStyles()
        styles["body"]?.order = 0
        styles["heading1"]?.order = 1
        styles["heading2"]?.order = 2
        styles["listItem"]?.order = 6
        styles["quote"]?.order = 7

        // …plus the additions.
        styles["heading3"] = ParagraphStyleDef(
            name: "Heading 3", font: "Helvetica", size: 14, bold: true,
            spaceBefore: 12, spaceAfter: 4, order: 3, markdown: "h3")
        styles["title"] = ParagraphStyleDef(
            name: "Title", font: "Helvetica", size: 30, bold: true,
            spaceAfter: 6, alignment: "center", order: 4, markdown: "h1")
        styles["subtitle"] = ParagraphStyleDef(
            name: "Subtitle", font: "Helvetica", size: 15,
            spaceAfter: 18, alignment: "center", color: "#444444", order: 5, markdown: "p")
        styles["code"] = ParagraphStyleDef(
            name: "Code", font: "Menlo", size: 11,
            lineSpacing: 1.2, leftIndent: 18, order: 8, markdown: "code")
        styles["pullQuote"] = ParagraphStyleDef(
            name: "Pull Quote", font: "Helvetica", size: 16, italic: true,
            spaceBefore: 12, spaceAfter: 12, leftIndent: 36, rightIndent: 36,
            alignment: "center", color: "#333333", order: 9, markdown: "blockquote")
        styles["caption"] = ParagraphStyleDef(
            name: "Caption", font: "Helvetica", size: 10, italic: true,
            spaceBefore: 4, spaceAfter: 12, alignment: "center", color: "#555555",
            order: 10, markdown: "p")
        styles["finePrint"] = ParagraphStyleDef(
            name: "Fine Print", font: "Helvetica", size: 9,
            lineSpacing: 1.15, color: "#666666", order: 11, markdown: "p")
        return styles
    }

    /// A blank document with a single empty Body paragraph (File ▸ New).
    public static func empty(page: PageConfig = .a4) -> LucerneDocumentModel {
        LucerneDocumentModel(
            page: page,
            styles: defaultStyles(),
            body: [Paragraph(id: IDGenerator.next("p"), style: "body", runs: [Run(text: "")])],
            objects: [])
    }

    /// The §6 milestone demo: a short letter with one page-anchored image so the
    /// app demonstrates live reflow the moment it launches.
    public static func sampleLetter(page: PageConfig = .a4) -> LucerneDocumentModel {
        let body: [Paragraph] = [
            Paragraph(id: "p1", style: "heading1",
                      runs: [Run(text: "A Letter from the Lake")]),
            Paragraph(id: "p2", style: "body", indent: IndentModel(firstLine: 18),
                      runs: [
                        Run(text: "Dear friend,"),
                      ]),
            Paragraph(id: "p3", style: "body", indent: IndentModel(firstLine: 18),
                      runs: [
                        Run(text: "Thank you for the "),
                        Run(text: "wonderful", italic: true),
                        Run(text: " afternoon by the water — the light on the "
                            + "mountains was exactly as you described it. I have "
                            + "placed a little picture below; notice how these very "
                            + "words flow politely around it, and keep flowing "
                            + "correctly even as the paragraph is edited."),
                      ]),
            Paragraph(id: "p4", style: "body", indent: IndentModel(firstLine: 18),
                      runs: [Run(text: loremA)]),
            Paragraph(id: "p5", style: "body", indent: IndentModel(firstLine: 18),
                      runs: [Run(text: loremB)]),
            Paragraph(id: "p6", style: "body", indent: IndentModel(firstLine: 18),
                      runs: [Run(text: loremC)]),
            Paragraph(id: "p7", style: "body",
                      runs: [Run(text: "Warmly, and with the lake's regards,")]),
            Paragraph(id: "p8", style: "body",
                      runs: [Run(text: "— Lucerne", italic: true)]),
        ]

        let image = PlacedObject(
            id: "img1", type: "image", src: sampleLetterImageSource,
            anchor: "page", page: 0,
            frame: RectModel(x: 300, y: 300, width: 220, height: 150),
            wrap: "rectangular", standoff: 12, z: 1)

        return LucerneDocumentModel(
            page: page,
            styles: defaultStyles(),
            body: body,
            objects: [image])
    }

    /// Original bytes for the sample letter's small, stylised lake illustration.
    /// Keeping the payload beside its model makes the untitled sample self-contained
    /// without adding bundle/resource lookup to LucerneKit.
    public static func sampleLetterImages() -> [String: Data] {
        guard let image = Data(base64Encoded: sampleLetterImageBase64) else {
            preconditionFailure("The built-in sample letter image is invalid")
        }
        return [sampleLetterImageSource: image]
    }

    private static let sampleLetterImageSource = "images/lake.png"
    // 120 x 80 indexed-colour PNG: sky, mountains, sun, and lake (389 bytes).
    private static let sampleLetterImageBase64 = [
        "iVBORw0KGgoAAAANSUhEUgAAAHgAAABQCAMAAADlRUG7AAAAG1BMVEWJwuv/4HdefI7e5+EtUFg3",
        "ia1brsoeaJHGtH5OZNdCAAABJUlEQVR42u3XWxKCMAwFUHojdf87dhweFppQtAlgyf1DY04LjTN0",
        "ncfj+ZeEc9QhZ7m8TAe4rExE9i4nE1nRe2ATugCDjOgQtmXAii7tGB/6eNiE3oRpgi1o2X07gB0t",
        "uIOCXCZtmZ1fAJab7gL7t0FYwRKttJaZRQ5ztNJtSFgWXtOk8+gXrADP+cz5dFmKVJO3xlcpsUIN",
        "1wmKslDENwK0aKFIagMtma+SuwAqdPlkasDY45ZaQEPGYfCe42MEo86tgEf65x+jTsYpcNWiHW4f",
        "fpyUJuHkTeJKcG+XBM6/bBLuN9wFHLUzw+P15XbcDtzLrsOr1B3q3XCMNgOVrCSBo2mWcBqHDeTo",
        "cNtwFNw7wk/jBOHze8Pmz9hvtcM+Tj5OKvALmkV2w3RUVbcAAAAASUVORK5CYII=",
    ].joined()

    private static let loremA =
        "Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod "
        + "tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim "
        + "veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea "
        + "commodo consequat. Duis aute irure dolor in reprehenderit in voluptate."
    private static let loremB =
        "Velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint "
        + "occaecat cupidatat non proident, sunt in culpa qui officia deserunt "
        + "mollit anim id est laborum. Sed ut perspiciatis unde omnis iste natus "
        + "error sit voluptatem accusantium doloremque laudantium, totam rem."
    private static let loremC =
        "Aperiam eaque ipsa quae ab illo inventore veritatis et quasi architecto "
        + "beatae vitae dicta sunt explicabo. Nemo enim ipsam voluptatem quia "
        + "voluptas sit aspernatur aut odit aut fugit, sed quia consequuntur magni "
        + "dolores eos qui ratione voluptatem sequi nesciunt. Neque porro quisquam."
}
