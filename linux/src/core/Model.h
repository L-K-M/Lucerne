#pragma once

// The canonical document model — the C++ realization of the `document.json`
// schema (docs/luce-format-spec.md), mirroring Swift LucerneCore's
// DocumentModel.swift field for field so the two implementations stay
// file-level compatible. The source of truth the app reads and writes;
// everything else (the live QTextDocument, content.md, PDF) is derived from or
// merged back into this.

#include "core/Geometry.h"

#include <QMap>
#include <QString>
#include <QStringList>
#include <QVector>
#include <optional>

namespace lucerne {

// MARK: - Header / footer (page furniture)

/// A running header or footer: three zones (left/center/right). Each zone is a
/// template that may contain the tokens {page}, {pages}, {date}, {title}.
struct PageFurniture {
    QString left;
    QString center;
    QString right;

    bool isEmpty() const { return left.isEmpty() && center.isEmpty() && right.isEmpty(); }
    friend bool operator==(const PageFurniture &a, const PageFurniture &b) {
        return a.left == b.left && a.center == b.center && a.right == b.right;
    }
    friend bool operator!=(const PageFurniture &a, const PageFurniture &b) { return !(a == b); }
};

// MARK: - Page (D1: one fixed size for the whole document)

struct PageConfig {
    QString size = QStringLiteral("A4");   // "A4" | "Letter" | "custom" (advisory)
    double width = 595.28;                 // points; authoritative
    double height = 841.89;
    EdgeInsetsModel margins = EdgeInsetsModel::uniform(72);
    std::optional<bool> foldMarks;         // DIN 5008 tri-fold ticks; absent = false

    static PageConfig a4();
    static PageConfig usLetter();

    /// Size of the text area (page minus margins) — the text container size (D1).
    SizeModel contentSize() const {
        return {std::max(0.0, width - margins.left - margins.right),
                std::max(0.0, height - margins.top - margins.bottom)};
    }

    friend bool operator==(const PageConfig &a, const PageConfig &b) {
        return a.size == b.size && a.width == b.width && a.height == b.height
            && a.margins == b.margins && a.foldMarks == b.foldMarks;
    }
    friend bool operator!=(const PageConfig &a, const PageConfig &b) { return !(a == b); }
};

// MARK: - Named paragraph styles (D3)

struct ParagraphStyle {
    QString name;
    std::optional<QString> font;
    std::optional<double> size;
    std::optional<bool> bold;
    std::optional<bool> italic;
    std::optional<bool> underline;        // style-level; a run's overrides it
    std::optional<double> lineSpacing;    // line-height multiple (1.2 == 120%)
    std::optional<double> spaceBefore;    // points
    std::optional<double> spaceAfter;
    std::optional<double> leftIndent;
    std::optional<double> firstLineIndent;
    std::optional<double> rightIndent;    // inward from the right margin
    std::optional<QString> alignment;     // "left"|"center"|"right"|"justified"
    std::optional<QString> color;         // "#RGB"|"#RRGGBB"|"#RRGGBBAA"
    std::optional<double> order;          // UI list position; presentational
    QString markdown = QStringLiteral("p");

    /// Everything except the presentational `order` — "looks the same on the page".
    bool visuallyEquals(const ParagraphStyle &other) const {
        ParagraphStyle a = *this, b = other;
        a.order.reset();
        b.order.reset();
        return a == b;
    }

    /// Last-resort body style used only when a file is missing its style table.
    static ParagraphStyle fallbackBody();

    friend bool operator==(const ParagraphStyle &a, const ParagraphStyle &b) {
        return a.name == b.name && a.font == b.font && a.size == b.size && a.bold == b.bold
            && a.italic == b.italic && a.underline == b.underline
            && a.lineSpacing == b.lineSpacing && a.spaceBefore == b.spaceBefore
            && a.spaceAfter == b.spaceAfter && a.leftIndent == b.leftIndent
            && a.firstLineIndent == b.firstLineIndent && a.rightIndent == b.rightIndent
            && a.alignment == b.alignment && a.color == b.color && a.order == b.order
            && a.markdown == b.markdown;
    }
    friend bool operator!=(const ParagraphStyle &a, const ParagraphStyle &b) { return !(a == b); }
};

// MARK: - Paragraph pieces

struct IndentModel {
    std::optional<double> left;
    std::optional<double> right;
    std::optional<double> firstLine;      // relative to the effective left indent

    friend bool operator==(const IndentModel &a, const IndentModel &b) {
        return a.left == b.left && a.right == b.right && a.firstLine == b.firstLine;
    }
    friend bool operator!=(const IndentModel &a, const IndentModel &b) { return !(a == b); }
};

struct TabStopModel {
    double pos = 0;                            // points from the left margin
    QString type = QStringLiteral("left");     // "left"|"center"|"right"|"decimal"

    friend bool operator==(const TabStopModel &a, const TabStopModel &b) {
        return a.pos == b.pos && a.type == b.type;
    }
    friend bool operator!=(const TabStopModel &a, const TabStopModel &b) { return !(a == b); }
};

/// Marks a paragraph as a cell of a table (spec §6.7). Cells sharing a `table`
/// id form one table; the grid is derived from (row, column) plus spans.
struct TableCellModel {
    QString table;
    int row = 0;
    int column = 0;
    int rowSpan = 1;
    int columnSpan = 1;
    std::optional<double> width;          // percent of the table; absent = equal

    friend bool operator==(const TableCellModel &a, const TableCellModel &b) {
        return a.table == b.table && a.row == b.row && a.column == b.column
            && a.rowSpan == b.rowSpan && a.columnSpan == b.columnSpan && a.width == b.width;
    }
    friend bool operator!=(const TableCellModel &a, const TableCellModel &b) { return !(a == b); }
};

/// Marks a paragraph as an item of a list (spec §6.8). The visible marker is
/// derived from the run of items — never stored.
struct ListItemModel {
    QString list;
    bool ordered = false;
    QString marker;                       // constrained by `ordered`, see spec
    int level = 0;                        // 0-based nesting depth
    std::optional<int> start;             // ordered lists: first number (default 1)

    friend bool operator==(const ListItemModel &a, const ListItemModel &b) {
        return a.list == b.list && a.ordered == b.ordered && a.marker == b.marker
            && a.level == b.level && a.start == b.start;
    }
    friend bool operator!=(const ListItemModel &a, const ListItemModel &b) { return !(a == b); }
};

struct Run {
    QString text;
    std::optional<bool> bold;
    std::optional<bool> italic;
    std::optional<bool> underline;
    std::optional<QString> font;
    std::optional<double> size;
    std::optional<QString> color;

    friend bool operator==(const Run &a, const Run &b) {
        return a.text == b.text && a.bold == b.bold && a.italic == b.italic
            && a.underline == b.underline && a.font == b.font && a.size == b.size
            && a.color == b.color;
    }
    friend bool operator!=(const Run &a, const Run &b) { return !(a == b); }
};

struct Paragraph {
    QString id;
    QString style;                        // role key into the style table
    std::optional<QString> align;
    std::optional<IndentModel> indent;
    std::optional<QVector<TabStopModel>> tabStops;
    std::optional<double> lineSpacing;
    std::optional<double> spaceBefore;
    std::optional<double> spaceAfter;
    std::optional<bool> pageBreakBefore;
    std::optional<TableCellModel> cell;
    std::optional<ListItemModel> list;
    QVector<Run> runs;

    QString plainText() const {
        QString out;
        for (const Run &run : runs) out += run.text;
        return out;
    }

    friend bool operator==(const Paragraph &a, const Paragraph &b) {
        return a.id == b.id && a.style == b.style && a.align == b.align && a.indent == b.indent
            && a.tabStops == b.tabStops && a.lineSpacing == b.lineSpacing
            && a.spaceBefore == b.spaceBefore && a.spaceAfter == b.spaceAfter
            && a.pageBreakBefore == b.pageBreakBefore && a.cell == b.cell && a.list == b.list
            && a.runs == b.runs;
    }
    friend bool operator!=(const Paragraph &a, const Paragraph &b) { return !(a == b); }
};

// MARK: - Placed objects (D2 + free placement)

struct PlacedObject {
    QString id;
    QString type = QStringLiteral("image");
    std::optional<QString> src;                    // e.g. "images/lake.png"
    QString anchor = QStringLiteral("page");       // "page" | "paragraph"
    std::optional<int> page;                       // when anchor == "page" (zero-based)
    std::optional<RectModel> frame;                // when anchor == "page" (page-relative)
    std::optional<QString> anchorParagraph;        // when anchor == "paragraph"
    std::optional<PointModel> offset;
    QString wrap = QStringLiteral("rectangular");  // "none"|"rectangular"|"irregular"
    double standoff = 12;                          // gutter in points
    int z = 0;                                     // stacking order

    enum class Anchor { Page, Paragraph };
    enum class Wrap { None, Rectangular, Irregular };

    Anchor anchorMode() const {
        return anchor == QLatin1String("paragraph") ? Anchor::Paragraph : Anchor::Page;
    }
    Wrap wrapMode() const {
        if (wrap == QLatin1String("none")) return Wrap::None;
        if (wrap == QLatin1String("irregular")) return Wrap::Irregular;
        return Wrap::Rectangular;
    }

    friend bool operator==(const PlacedObject &a, const PlacedObject &b) {
        return a.id == b.id && a.type == b.type && a.src == b.src && a.anchor == b.anchor
            && a.page == b.page && a.frame == b.frame && a.anchorParagraph == b.anchorParagraph
            && a.offset == b.offset && a.wrap == b.wrap && a.standoff == b.standoff && a.z == b.z;
    }
    friend bool operator!=(const PlacedObject &a, const PlacedObject &b) { return !(a == b); }
};

// MARK: - Root

struct DocumentModel {
    QString format = canonicalFormat();
    int formatVersion = currentFormatVersion();
    PageConfig page;
    QMap<QString, ParagraphStyle> styles;      // QMap: iteration is key-sorted
    QVector<Paragraph> body;
    QVector<PlacedObject> objects;
    std::optional<PageFurniture> header;
    std::optional<PageFurniture> footer;
    /// 1-based physical page on which {page} becomes 1; earlier pages unnumbered.
    std::optional<int> pageNumberStart;

    static QString canonicalFormat() { return QStringLiteral("lucerne-document"); }
    static int currentFormatVersion() { return 1; }
    /// Pagination's safety cap; valid zero-based object page indexes end at 1999.
    static int maximumPageCount() { return 2000; }
    static QString defaultStyleRole() { return QStringLiteral("body"); }

    /// Looks up a style role, falling back to `body`, then to a hard default so
    /// a malformed file still renders something sane.
    ParagraphStyle resolvedStyle(const QString &role) const;

    /// The document's style roles in UI order (STYLES.md S5): explicit `order`
    /// ascending, then the classic five for pre-`order` files, then by name.
    QStringList orderedStyleRoles() const;
    static QStringList orderedStyleRoles(const QMap<QString, ParagraphStyle> &styles);

    friend bool operator==(const DocumentModel &a, const DocumentModel &b) {
        return a.format == b.format && a.formatVersion == b.formatVersion && a.page == b.page
            && a.styles == b.styles && a.body == b.body && a.objects == b.objects
            && a.header == b.header && a.footer == b.footer
            && a.pageNumberStart == b.pageNumberStart;
    }
    friend bool operator!=(const DocumentModel &a, const DocumentModel &b) { return !(a == b); }
};

/// Stable, unique ids for paragraphs and placed objects (mirrors IDGenerator.swift).
namespace IDGenerator {
QString next(const QString &prefix);
}

} // namespace lucerne
