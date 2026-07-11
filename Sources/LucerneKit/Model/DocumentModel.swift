import Foundation

// The canonical document model — the Swift realization of the `document.json`
// schema in lucerne-plan.md §7 (decisions D1–D3). This is the source of truth the
// app reads and writes; everything else (the live NSTextStorage, content.md, PDF,
// future RTF) is derived from or merged back into this.
//
// Kept free of AppKit so it is portable and unit-testable.

// MARK: - Root

public struct LucerneDocumentModel: Codable, Equatable {
    public var format: String
    public var formatVersion: Int
    public var page: PageConfig
    public var styles: [String: ParagraphStyleDef]
    public var body: [Paragraph]
    public var objects: [PlacedObject]
    public var header: PageFurniture?
    public var footer: PageFurniture?
    /// 1-based physical page on which the page number shown by `{page}` becomes 1.
    /// Earlier pages are unnumbered (e.g. set to 3 to skip a title page and a
    /// contents page). Absent / nil means every page is numbered starting at 1.
    public var pageNumberStart: Int?

    public static let canonicalFormat = "lucerne-document"
    public static let currentFormatVersion = 1
    /// Pagination's safety cap; valid zero-based object page indexes end at 1999.
    public static let maximumPageCount = 2000

    public init(format: String = LucerneDocumentModel.canonicalFormat,
                formatVersion: Int = LucerneDocumentModel.currentFormatVersion,
                page: PageConfig,
                styles: [String: ParagraphStyleDef],
                body: [Paragraph],
                objects: [PlacedObject],
                header: PageFurniture? = nil,
                footer: PageFurniture? = nil,
                pageNumberStart: Int? = nil) {
        self.format = format
        self.formatVersion = formatVersion
        self.page = page
        self.styles = styles
        self.body = body
        self.objects = objects
        self.header = header
        self.footer = footer
        self.pageNumberStart = pageNumberStart
    }

    /// The default style role applied to a paragraph that names a role we do not
    /// recognise (or to brand-new paragraphs).
    public static let defaultStyleRole = "body"

    /// Looks up a style role, falling back to `body`, then to a hard default so a
    /// malformed file still renders something sane.
    public func resolvedStyle(for role: String) -> ParagraphStyleDef {
        styles[role]
            ?? styles[LucerneDocumentModel.defaultStyleRole]
            ?? ParagraphStyleDef.fallbackBody
    }

    /// The document's style roles in UI order (STYLES.md S5): explicit `order`
    /// values ascending first, then — for files that predate `order` — the
    /// classic five roles in their traditional order, then everything else by
    /// display name.
    public var orderedStyleRoles: [String] { Self.orderedStyleRoles(in: styles) }

    public static func orderedStyleRoles(in styles: [String: ParagraphStyleDef]) -> [String] {
        func rank(_ key: String) -> (order: Double, legacy: Int, name: String) {
            if let order = styles[key]?.order { return (order, -1, "") }
            if let index = DefaultDocuments.styleRoleOrder.firstIndex(of: key) {
                return (.greatestFiniteMagnitude, index, "")
            }
            return (.greatestFiniteMagnitude, DefaultDocuments.styleRoleOrder.count,
                    styles[key]?.name ?? key)
        }
        return styles.keys.sorted { a, b in
            let ra = rank(a), rb = rank(b)
            if ra.order != rb.order { return ra.order < rb.order }
            if ra.legacy != rb.legacy { return ra.legacy < rb.legacy }
            switch ra.name.localizedCaseInsensitiveCompare(rb.name) {
            case .orderedAscending: return true
            case .orderedDescending: return false
            case .orderedSame: return a < b   // deterministic tiebreak
            }
        }
    }

    /// The `order` a newly created style should get: after everything else.
    public func nextStyleOrder() -> Double {
        (styles.values.compactMap(\.order).max() ?? Double(styles.count - 1)) + 1
    }
}

// MARK: - Header / footer (page furniture)

/// A running header or footer: three zones (left/center/right). Each zone is a
/// template that may contain the tokens {page}, {pages}, {date}, {title}.
public struct PageFurniture: Codable, Equatable {
    public var left: String
    public var center: String
    public var right: String

    public init(left: String = "", center: String = "", right: String = "") {
        self.left = left
        self.center = center
        self.right = right
    }

    // Tolerate files that omit some zones (spec §3.2: each optional, default "").
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        left = try c.decodeIfPresent(String.self, forKey: .left) ?? ""
        center = try c.decodeIfPresent(String.self, forKey: .center) ?? ""
        right = try c.decodeIfPresent(String.self, forKey: .right) ?? ""
    }

    public var isEmpty: Bool { left.isEmpty && center.isEmpty && right.isEmpty }
}

// MARK: - Page (D1: one fixed size for the whole document)

public struct PageConfig: Codable, Equatable {
    public var size: String          // "A4" | "Letter" | "custom"
    public var width: Double         // points; authoritative when size == "custom"
    public var height: Double
    public var margins: EdgeInsetsModel
    /// Print DIN 5008 tri-fold guide ticks in the outer left margin (for folding
    /// into a windowed envelope). Additive/optional: nil or false means none;
    /// synthesized Codable omits it when nil.
    public var foldMarks: Bool?

    public init(size: String, width: Double, height: Double, margins: EdgeInsetsModel,
                foldMarks: Bool? = nil) {
        self.size = size
        self.width = width
        self.height = height
        self.margins = margins
        self.foldMarks = foldMarks
    }

    public static let a4 = PageConfig(size: "A4", width: 595.28, height: 841.89,
                                      margins: .uniform(72))
    public static let usLetter = PageConfig(size: "Letter", width: 612, height: 792,
                                            margins: .uniform(72))

    /// Size of the text area (page minus margins) — the text container size (D1).
    public var contentSize: SizeModel {
        SizeModel(width: max(0, width - margins.left - margins.right),
                  height: max(0, height - margins.top - margins.bottom))
    }
}

// MARK: - Named paragraph styles (D3: roles → visual attrs + markdown hint)

public struct ParagraphStyleDef: Codable, Equatable {
    public var name: String
    public var font: String?
    public var size: Double?
    public var bold: Bool?
    public var italic: Bool?
    public var underline: Bool?         // style-level underline; a run's overrides it
    public var lineSpacing: Double?     // line-height multiple (1.2 == 120%)
    public var spaceBefore: Double?     // points before paragraph
    public var spaceAfter: Double?      // points after paragraph
    public var leftIndent: Double?
    public var firstLineIndent: Double?
    public var rightIndent: Double?     // points inward from the right margin
    public var alignment: String?       // "left"|"center"|"right"|"justified"
    public var color: String?           // hex, e.g. "#1a1a1a"
    public var order: Double?           // UI list position (ascending); presentational
    public var markdown: String         // "p"|"h1"|"h2"|"li"|"blockquote"

    public init(name: String,
                font: String? = nil,
                size: Double? = nil,
                bold: Bool? = nil,
                italic: Bool? = nil,
                underline: Bool? = nil,
                lineSpacing: Double? = nil,
                spaceBefore: Double? = nil,
                spaceAfter: Double? = nil,
                leftIndent: Double? = nil,
                firstLineIndent: Double? = nil,
                rightIndent: Double? = nil,
                alignment: String? = nil,
                color: String? = nil,
                order: Double? = nil,
                markdown: String) {
        self.name = name
        self.font = font
        self.size = size
        self.bold = bold
        self.italic = italic
        self.underline = underline
        self.lineSpacing = lineSpacing
        self.spaceBefore = spaceBefore
        self.spaceAfter = spaceAfter
        self.leftIndent = leftIndent
        self.firstLineIndent = firstLineIndent
        self.rightIndent = rightIndent
        self.alignment = alignment
        self.color = color
        self.order = order
        self.markdown = markdown
    }

    /// Whether two definitions look the same on the page — everything except the
    /// presentational `order`. The editor's library strip compares with this so
    /// merely reordering a list doesn't read as "differs from your Library".
    public func visuallyEquals(_ other: ParagraphStyleDef) -> Bool {
        var a = self, b = other
        a.order = nil
        b.order = nil
        return a == b
    }

    /// Last-resort body style used only when a file is missing its style table.
    public static let fallbackBody = ParagraphStyleDef(
        name: "Body", font: "Helvetica", size: 12, lineSpacing: 1.2,
        spaceAfter: 6, markdown: "p")
}

// MARK: - Paragraphs and runs

public struct Paragraph: Codable, Equatable {
    public var id: String
    public var style: String                 // role key into `styles`
    public var align: String?                // per-paragraph override
    public var indent: IndentModel?
    public var tabStops: [TabStopModel]?
    // Optional per-paragraph spacing overrides (additive to the §7 sketch; the
    // base values live on the style role). Present only when they differ from the
    // style, so direct-formatting commands round-trip without bloating the file.
    public var lineSpacing: Double?          // line-height multiple
    public var spaceBefore: Double?          // points before paragraph
    public var spaceAfter: Double?           // points after paragraph
    public var pageBreakBefore: Bool?        // force this paragraph onto a new page
    public var cell: TableCellModel?         // present when this paragraph is a table cell
    public var list: ListItemModel?          // present when this paragraph is a list item
    public var runs: [Run]

    public init(id: String,
                style: String,
                align: String? = nil,
                indent: IndentModel? = nil,
                tabStops: [TabStopModel]? = nil,
                lineSpacing: Double? = nil,
                spaceBefore: Double? = nil,
                spaceAfter: Double? = nil,
                pageBreakBefore: Bool? = nil,
                cell: TableCellModel? = nil,
                list: ListItemModel? = nil,
                runs: [Run]) {
        self.id = id
        self.style = style
        self.align = align
        self.indent = indent
        self.tabStops = tabStops
        self.lineSpacing = lineSpacing
        self.spaceBefore = spaceBefore
        self.spaceAfter = spaceAfter
        self.pageBreakBefore = pageBreakBefore
        self.cell = cell
        self.list = list
        self.runs = runs
    }

    /// The plain text of the paragraph (runs concatenated).
    public var plainText: String { runs.map(\.text).joined() }
}

/// Marks a paragraph as a cell of a table. Cells sharing a `table` id form one
/// table; the grid is laid out by each cell's `(row, column)` plus its spans. The
/// table's column count is derived from the cells (no redundant field), so the
/// content is still a flat ordered paragraph list (no nested block type).
public struct TableCellModel: Codable, Equatable {
    public var table: String                 // shared id grouping a table's cells
    public var row: Int                      // 0-based
    public var column: Int                   // 0-based
    public var rowSpan: Int
    public var columnSpan: Int
    public var width: Double?                // this column's width, percent of the table (nil = equal share)

    public init(table: String, row: Int, column: Int,
                rowSpan: Int = 1, columnSpan: Int = 1, width: Double? = nil) {
        self.table = table
        self.row = row
        self.column = column
        self.rowSpan = rowSpan
        self.columnSpan = columnSpan
        self.width = width
    }

    // Tolerate files that omit the defaulted spans / width.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        table = try c.decode(String.self, forKey: .table)
        row = try c.decode(Int.self, forKey: .row)
        column = try c.decode(Int.self, forKey: .column)
        rowSpan = try c.decodeIfPresent(Int.self, forKey: .rowSpan) ?? 1
        columnSpan = try c.decodeIfPresent(Int.self, forKey: .columnSpan) ?? 1
        width = try c.decodeIfPresent(Double.self, forKey: .width)
    }
}

/// Marks a paragraph as an item of a list. Items sharing a `list` id, laid out
/// contiguously, form one list; each carries its own `marker` style and nesting
/// `level`, so a single list can mix depths. Unlike a table's `cell`, list
/// membership is orthogonal to the paragraph's named style — a bulleted paragraph
/// keeps its Body (or any) text style and merely gains a marker + hanging indent.
/// The visible marker glyph/number is *derived* (never stored): the number an
/// ordered item shows depends on its neighbours, so it is recomputed from the run
/// of items rather than frozen into the file.
public struct ListItemModel: Codable, Equatable {
    public var list: String       // shared id grouping one list's items
    public var ordered: Bool      // numbered (true) vs bulleted (false)
    /// Unordered: "disc" | "circle" | "square" | "dash".
    /// Ordered:   "decimal" | "lower-alpha" | "upper-alpha" | "lower-roman" | "upper-roman".
    public var marker: String
    public var level: Int         // 0-based nesting depth
    public var start: Int?        // ordered lists: the first item's number (default 1)

    public init(list: String, ordered: Bool, marker: String, level: Int = 0, start: Int? = nil) {
        self.list = list
        self.ordered = ordered
        self.marker = marker
        self.level = level
        self.start = start
    }

    // Tolerate files that omit the defaulted level / start.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        list = try c.decode(String.self, forKey: .list)
        ordered = try c.decode(Bool.self, forKey: .ordered)
        marker = try c.decode(String.self, forKey: .marker)
        level = try c.decodeIfPresent(Int.self, forKey: .level) ?? 0
        start = try c.decodeIfPresent(Int.self, forKey: .start)
    }

    /// A copy at a different nesting depth, clamped to the editor's supported range.
    public func atLevel(_ newLevel: Int) -> ListItemModel {
        ListItemModel(list: list, ordered: ordered, marker: marker,
                      level: ListGeometry.clampedLevel(newLevel), start: start)
    }
}

public struct IndentModel: Codable, Equatable {
    public var left: Double?
    public var right: Double?
    public var firstLine: Double?

    public init(left: Double? = nil, right: Double? = nil, firstLine: Double? = nil) {
        self.left = left
        self.right = right
        self.firstLine = firstLine
    }
}

public struct TabStopModel: Codable, Equatable {
    public var pos: Double                    // points from the left margin
    public var type: String                   // "left"|"center"|"right"|"decimal"

    public init(pos: Double, type: String = "left") {
        self.pos = pos
        self.type = type
    }

    // Tolerate files that omit the defaulted type (spec §6.5: default "left").
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        pos = try c.decode(Double.self, forKey: .pos)
        type = try c.decodeIfPresent(String.self, forKey: .type) ?? "left"
    }

    public enum Kind: String { case left, center, right, decimal }
    public var kind: Kind { Kind(rawValue: type) ?? .left }
}

public struct Run: Codable, Equatable {
    public var text: String
    public var bold: Bool?
    public var italic: Bool?
    public var underline: Bool?
    public var font: String?
    public var size: Double?
    public var color: String?

    public init(text: String,
                bold: Bool? = nil,
                italic: Bool? = nil,
                underline: Bool? = nil,
                font: String? = nil,
                size: Double? = nil,
                color: String? = nil) {
        self.text = text
        self.bold = bold
        self.italic = italic
        self.underline = underline
        self.font = font
        self.size = size
        self.color = color
    }
}

// MARK: - Placed objects (D2 + free placement)

public struct PlacedObject: Codable, Equatable {
    public var id: String
    public var type: String                  // "image"
    public var src: String?                  // e.g. "images/lake.png"
    public var anchor: String                // "page" | "paragraph"
    public var page: Int?                    // when anchor == "page" (zero-based)
    public var frame: RectModel?             // when anchor == "page" (page-relative)
    public var anchorParagraph: String?      // when anchor == "paragraph"
    public var offset: PointModel?           // when anchor == "paragraph"
    public var wrap: String                  // "none"|"rectangular"|"irregular"
    public var standoff: Double              // gutter in points
    public var z: Int                        // stacking order

    public enum Anchor: String { case page, paragraph }
    public enum Wrap: String { case none, rectangular, irregular }

    public var anchorMode: Anchor { Anchor(rawValue: anchor) ?? .page }
    public var wrapMode: Wrap { Wrap(rawValue: wrap) ?? .rectangular }

    public init(id: String,
                type: String = "image",
                src: String? = nil,
                anchor: String = Anchor.page.rawValue,
                page: Int? = nil,
                frame: RectModel? = nil,
                anchorParagraph: String? = nil,
                offset: PointModel? = nil,
                wrap: String = Wrap.rectangular.rawValue,
                standoff: Double = 12,
                z: Int = 0) {
        self.id = id
        self.type = type
        self.src = src
        self.anchor = anchor
        self.page = page
        self.frame = frame
        self.anchorParagraph = anchorParagraph
        self.offset = offset
        self.wrap = wrap
        self.standoff = standoff
        self.z = z
    }

    // Custom decoder so older or hand-edited files missing the defaulted fields
    // (wrap/standoff/z/anchor/type) still load cleanly.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        type = try c.decodeIfPresent(String.self, forKey: .type) ?? "image"
        src = try c.decodeIfPresent(String.self, forKey: .src)
        anchor = try c.decodeIfPresent(String.self, forKey: .anchor) ?? Anchor.page.rawValue
        page = try c.decodeIfPresent(Int.self, forKey: .page)
        frame = try c.decodeIfPresent(RectModel.self, forKey: .frame)
        anchorParagraph = try c.decodeIfPresent(String.self, forKey: .anchorParagraph)
        offset = try c.decodeIfPresent(PointModel.self, forKey: .offset)
        wrap = try c.decodeIfPresent(String.self, forKey: .wrap) ?? Wrap.rectangular.rawValue
        standoff = try c.decodeIfPresent(Double.self, forKey: .standoff) ?? 12
        z = try c.decodeIfPresent(Int.self, forKey: .z) ?? 0
    }
}
