#pragma once

// model ⇆ QTextDocument bridge — the Qt analogue of the Mac app's
// AttributedStringBuilder/AttributedStringReader pair. One QTextBlock per
// paragraph; style roles, paragraph ids, list/cell descriptors and page-break
// flags ride on custom QTextFormat properties so they survive editing and
// round-trip on save. Formatting VALUES are baked into the storage at build
// time (the Mac convention): on read-back, only deltas against the paragraph's
// style role are captured as run/paragraph overrides, so files stay lean.

#include "core/Model.h"

#include <QTextCharFormat>
#include <QTextDocument>

namespace lucerne {

namespace Props {
// QTextFormat custom property ids. Block char format carries the block-level
// ones; run char formats carry the per-run ones.
constexpr int StyleRole = QTextFormat::UserProperty + 1;      // QString (block)
constexpr int ParagraphId = QTextFormat::UserProperty + 2;    // QString (block)
constexpr int PageBreakBefore = QTextFormat::UserProperty + 3;// bool    (block)
constexpr int ListItem = QTextFormat::UserProperty + 4;       // QString JSON (block)
constexpr int TableCell = QTextFormat::UserProperty + 5;      // QString JSON (block)
constexpr int ModelFont = QTextFormat::UserProperty + 6;      // QString (char): the
    // file's font name (e.g. "Helvetica") as distinct from the fontconfig-
    // substituted family Qt renders with — preserved so saves don't rewrite
    // every Mac document's fonts to Linux family names.
constexpr int ModelColor = QTextFormat::UserProperty + 7;     // QString (char): the
    // file's color string, preserved verbatim (case, #RGB shorthand, alpha).
constexpr int MergeSalt = QTextFormat::UserProperty + 8;      // int (char): bumped
    // after every non-text undo command so the next insertion's format differs
    // and QTextDocument cannot merge it into the text command that came before
    // the object edit (which would break unified-undo ordering). Never read
    // back; invisible to rendering and to the saved file.
}

namespace DocumentBridge {

/// JSON codecs for the descriptor properties (the Mac's ListItemCodec idiom).
QString encodeListItem(const ListItemModel &item);
std::optional<ListItemModel> decodeListItem(const QString &json);
QString encodeCell(const TableCellModel &cell);
std::optional<TableCellModel> decodeCell(const QString &json);

/// The display QFont for a model font name + attributes (applies the
/// Helvetica→Liberation Sans class of substitutions via QFont's own machinery).
QFont displayFont(const QString &family, double pointSize, bool bold, bool italic);

/// The fully resolved character format for a run within a paragraph style.
QTextCharFormat charFormat(const ParagraphStyle &style, const Run &run);
/// The block-level formats for a paragraph (indents, spacing, alignment, tabs).
QTextBlockFormat blockFormat(const DocumentModel &model, const Paragraph &paragraph);
/// The block char format (carries role/id/descriptor properties + the style's
/// base font so empty paragraphs type in the right face).
QTextCharFormat blockCharFormat(const DocumentModel &model, const Paragraph &paragraph);

/// Rebuilds `doc` from the model's body (undo history is cleared).
void build(QTextDocument *doc, const DocumentModel &model);

/// Reads the document back into a body paragraph list, capturing only deltas
/// against each paragraph's style role. The rest of the model (page, styles,
/// objects, furniture) is untouched by editing and lives outside the storage.
QVector<Paragraph> readBody(const QTextDocument *doc, const DocumentModel &model);

/// Parses a color string per spec §6.3 (#RGB, #RRGGBB, #RRGGBBAA).
std::optional<QColor> parseColor(const QString &hex);
QString colorToHex(const QColor &color);

} // namespace DocumentBridge

} // namespace lucerne
