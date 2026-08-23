#include "app/DocumentBridge.h"
#include "core/Lists.h"

#include <QFontDatabase>
#include <QJsonDocument>
#include <QJsonObject>
#include <QTextBlock>
#include <QTextCursor>

namespace lucerne {
namespace DocumentBridge {

namespace {

Qt::Alignment alignmentFromString(const QString &value, bool *ok = nullptr) {
    if (ok) *ok = true;
    if (value == QLatin1String("left")) return Qt::AlignLeft;
    if (value == QLatin1String("center")) return Qt::AlignHCenter;
    if (value == QLatin1String("right")) return Qt::AlignRight;
    if (value == QLatin1String("justified")) return Qt::AlignJustify;
    if (ok) *ok = false;
    return Qt::AlignLeft;
}

QString alignmentToString(Qt::Alignment alignment) {
    if (alignment & Qt::AlignHCenter) return QStringLiteral("center");
    if (alignment & Qt::AlignRight) return QStringLiteral("right");
    if (alignment & Qt::AlignJustify) return QStringLiteral("justified");
    return QStringLiteral("left");
}

QTextOption::TabType tabTypeFromString(const QString &type) {
    if (type == QLatin1String("center")) return QTextOption::CenterTab;
    if (type == QLatin1String("right")) return QTextOption::RightTab;
    if (type == QLatin1String("decimal")) return QTextOption::DelimiterTab;
    return QTextOption::LeftTab;
}

QString tabTypeToString(QTextOption::TabType type) {
    switch (type) {
    case QTextOption::CenterTab: return QStringLiteral("center");
    case QTextOption::RightTab: return QStringLiteral("right");
    case QTextOption::DelimiterTab: return QStringLiteral("decimal");
    default: return QStringLiteral("left");
    }
}

/// The effective (style ⊕ overrides) values the Mac calls "resolution order"
/// (spec §6.6) — computed for both build and read-back so the delta capture
/// compares against exactly what build wrote.
struct EffectiveText {
    QString font;
    double size;
    bool bold;
    bool italic;
    bool underline;
    QString color;
};

EffectiveText effectiveText(const ParagraphStyle &style, const Run *run) {
    EffectiveText e;
    e.font = (run && run->font) ? *run->font : style.font.value_or(QStringLiteral("Helvetica"));
    e.size = (run && run->size) ? *run->size : style.size.value_or(12.0);
    e.bold = (run && run->bold) ? *run->bold : style.bold.value_or(false);
    e.italic = (run && run->italic) ? *run->italic : style.italic.value_or(false);
    e.underline = (run && run->underline) ? *run->underline : style.underline.value_or(false);
    e.color = (run && run->color) ? *run->color : style.color.value_or(QStringLiteral("#000000"));
    return e;
}

} // namespace

QString encodeListItem(const ListItemModel &item) {
    QJsonObject o;
    o.insert(QLatin1String("list"), item.list);
    o.insert(QLatin1String("ordered"), item.ordered);
    o.insert(QLatin1String("marker"), item.marker);
    o.insert(QLatin1String("level"), item.level);
    if (item.start) o.insert(QLatin1String("start"), *item.start);
    return QString::fromUtf8(QJsonDocument(o).toJson(QJsonDocument::Compact));
}

std::optional<ListItemModel> decodeListItem(const QString &json) {
    const QJsonDocument doc = QJsonDocument::fromJson(json.toUtf8());
    if (!doc.isObject()) return std::nullopt;
    const QJsonObject o = doc.object();
    if (!o.value(QLatin1String("list")).isString()
        || !o.value(QLatin1String("ordered")).isBool()
        || !o.value(QLatin1String("marker")).isString())
        return std::nullopt;
    ListItemModel item;
    item.list = o.value(QLatin1String("list")).toString();
    item.ordered = o.value(QLatin1String("ordered")).toBool();
    item.marker = o.value(QLatin1String("marker")).toString();
    item.level = o.value(QLatin1String("level")).toInt(0);
    if (item.level < 0 || item.level > ListGeometry::maximumLevel()) return std::nullopt;
    if (o.contains(QLatin1String("start")))
        item.start = o.value(QLatin1String("start")).toInt(1);
    return item;
}

QString encodeCell(const TableCellModel &cell) {
    QJsonObject o;
    o.insert(QLatin1String("table"), cell.table);
    o.insert(QLatin1String("row"), cell.row);
    o.insert(QLatin1String("column"), cell.column);
    o.insert(QLatin1String("rowSpan"), cell.rowSpan);
    o.insert(QLatin1String("columnSpan"), cell.columnSpan);
    if (cell.width) o.insert(QLatin1String("width"), *cell.width);
    return QString::fromUtf8(QJsonDocument(o).toJson(QJsonDocument::Compact));
}

std::optional<TableCellModel> decodeCell(const QString &json) {
    const QJsonDocument doc = QJsonDocument::fromJson(json.toUtf8());
    if (!doc.isObject()) return std::nullopt;
    const QJsonObject o = doc.object();
    if (!o.value(QLatin1String("table")).isString()) return std::nullopt;
    TableCellModel cell;
    cell.table = o.value(QLatin1String("table")).toString();
    cell.row = o.value(QLatin1String("row")).toInt(0);
    cell.column = o.value(QLatin1String("column")).toInt(0);
    cell.rowSpan = o.value(QLatin1String("rowSpan")).toInt(1);
    cell.columnSpan = o.value(QLatin1String("columnSpan")).toInt(1);
    if (o.contains(QLatin1String("width")))
        cell.width = o.value(QLatin1String("width")).toDouble();
    return cell;
}

QFont displayFont(const QString &family, double pointSize, bool bold, bool italic) {
    QFont font(family);
    font.setPointSizeF(pointSize > 0 ? pointSize : 12);
    font.setBold(bold);
    font.setItalic(italic);
    return font;
}

std::optional<QColor> parseColor(const QString &hex) {
    if (!hex.startsWith(QLatin1Char('#'))) return std::nullopt;
    const QString h = hex.mid(1);
    // Every character must be a hex digit — QString::toInt would happily
    // accept a sign ("#-12345") and produce garbage channels.
    for (const QChar ch : h) {
        const char16_t u = ch.unicode();
        const bool digit = (u >= '0' && u <= '9') || (u >= 'a' && u <= 'f')
            || (u >= 'A' && u <= 'F');
        if (!digit) return std::nullopt;
    }
    bool ok = false;
    if (h.size() == 3) {
        const int v = h.toInt(&ok, 16);
        if (!ok) return std::nullopt;
        const int r = (v >> 8) & 0xf, g = (v >> 4) & 0xf, b = v & 0xf;
        return QColor(r * 17, g * 17, b * 17);
    }
    if (h.size() == 6) {
        const int v = h.toInt(&ok, 16);
        if (!ok) return std::nullopt;
        return QColor((v >> 16) & 0xff, (v >> 8) & 0xff, v & 0xff);
    }
    if (h.size() == 8) {
        const qlonglong v = h.toLongLong(&ok, 16);
        if (!ok) return std::nullopt;
        return QColor(int((v >> 24) & 0xff), int((v >> 16) & 0xff), int((v >> 8) & 0xff),
                      int(v & 0xff));
    }
    return std::nullopt;
}

QString colorToHex(const QColor &color) {
    return color.name(QColor::HexRgb);   // "#rrggbb"
}

QTextCharFormat charFormat(const ParagraphStyle &style, const Run &run) {
    const EffectiveText e = effectiveText(style, &run);
    QTextCharFormat format;
    format.setFont(displayFont(e.font, e.size, e.bold, e.italic));
    format.setFontUnderline(e.underline);
    // A malformed color string still gets an explicit foreground: an unset
    // brush would inherit whatever the paint context defaults to.
    format.setForeground(parseColor(e.color).value_or(QColor(Qt::black)));
    format.setProperty(Props::ModelFont, e.font);
    format.setProperty(Props::ModelColor, e.color);
    return format;
}

QTextBlockFormat blockFormat(const DocumentModel &model, const Paragraph &paragraph) {
    const ParagraphStyle style = model.resolvedStyle(paragraph.style);
    QTextBlockFormat format;

    const QString align = paragraph.align.value_or(style.alignment.value_or(QString()));
    if (!align.isEmpty()) format.setAlignment(alignmentFromString(align));

    double leftIndent = style.leftIndent.value_or(0);
    double rightIndent = style.rightIndent.value_or(0);
    double firstLine = style.firstLineIndent.value_or(0);
    if (paragraph.indent) {
        if (paragraph.indent->left) leftIndent = *paragraph.indent->left;
        if (paragraph.indent->right) rightIndent = *paragraph.indent->right;
        if (paragraph.indent->firstLine) firstLine = *paragraph.indent->firstLine;
    }
    format.setLeftMargin(leftIndent);
    format.setRightMargin(rightIndent);
    format.setTextIndent(firstLine);   // relative to the left margin, like the model

    format.setTopMargin(paragraph.spaceBefore.value_or(style.spaceBefore.value_or(0)));
    format.setBottomMargin(paragraph.spaceAfter.value_or(style.spaceAfter.value_or(0)));

    const double lineSpacing = paragraph.lineSpacing.value_or(style.lineSpacing.value_or(1.0));
    format.setLineHeight(lineSpacing * 100.0, QTextBlockFormat::ProportionalHeight);

    if (paragraph.tabStops) {
        QList<QTextOption::Tab> tabs;
        for (const TabStopModel &stop : *paragraph.tabStops) {
            QTextOption::Tab tab;
            tab.position = stop.pos;
            tab.type = tabTypeFromString(stop.type);
            if (tab.type == QTextOption::DelimiterTab)
                tab.delimiter = QLocale().decimalPoint().isEmpty()
                    ? QLatin1Char('.') : QLocale().decimalPoint().at(0);
            tabs.append(tab);
        }
        format.setTabPositions(tabs);
    }
    return format;
}

QTextCharFormat blockCharFormat(const DocumentModel &model, const Paragraph &paragraph) {
    const ParagraphStyle style = model.resolvedStyle(paragraph.style);
    QTextCharFormat format = charFormat(style, Run{});
    format.setProperty(Props::StyleRole, paragraph.style);
    format.setProperty(Props::ParagraphId, paragraph.id);
    if (paragraph.pageBreakBefore.value_or(false))
        format.setProperty(Props::PageBreakBefore, true);
    if (paragraph.list) format.setProperty(Props::ListItem, encodeListItem(*paragraph.list));
    if (paragraph.cell) format.setProperty(Props::TableCell, encodeCell(*paragraph.cell));
    return format;
}

void build(QTextDocument *doc, const DocumentModel &model) {
    doc->setUndoRedoEnabled(false);
    doc->clear();
    QTextCursor cursor(doc);
    cursor.beginEditBlock();
    bool first = true;
    for (const Paragraph &paragraph : model.body) {
        const ParagraphStyle style = model.resolvedStyle(paragraph.style);
        const QTextBlockFormat bf = blockFormat(model, paragraph);
        const QTextCharFormat bcf = blockCharFormat(model, paragraph);
        if (first) {
            cursor.setBlockFormat(bf);
            cursor.setBlockCharFormat(bcf);
            first = false;
        } else {
            cursor.insertBlock(bf, bcf);
        }
        for (const Run &run : paragraph.runs) {
            if (run.text.isEmpty()) continue;
            cursor.insertText(run.text, charFormat(style, run));
        }
    }
    cursor.endEditBlock();
    doc->setUndoRedoEnabled(true);
    doc->setModified(false);
}

QVector<Paragraph> readBody(const QTextDocument *doc, const DocumentModel &model) {
    QVector<Paragraph> body;
    QSet<QString> seenIds;
    for (QTextBlock block = doc->begin(); block.isValid(); block = block.next()) {
        const QTextCharFormat bcf = block.charFormat();
        Paragraph paragraph;
        paragraph.style = bcf.stringProperty(Props::StyleRole);
        if (paragraph.style.isEmpty()) paragraph.style = DocumentModel::defaultStyleRole();
        paragraph.id = bcf.stringProperty(Props::ParagraphId);
        // A block minted by typing Return has no id yet (or inherited its
        // neighbour's): assign a fresh one, keeping ids unique.
        if (paragraph.id.isEmpty() || seenIds.contains(paragraph.id))
            paragraph.id = IDGenerator::next(QStringLiteral("p"));
        seenIds.insert(paragraph.id);

        const ParagraphStyle style = model.resolvedStyle(paragraph.style);

        if (bcf.boolProperty(Props::PageBreakBefore)) paragraph.pageBreakBefore = true;
        if (bcf.hasProperty(Props::ListItem))
            paragraph.list = decodeListItem(bcf.stringProperty(Props::ListItem));
        if (bcf.hasProperty(Props::TableCell))
            paragraph.cell = decodeCell(bcf.stringProperty(Props::TableCell));

        // Paragraph-level deltas against the style role.
        const QTextBlockFormat bf = block.blockFormat();
        const QString styleAlign = style.alignment.value_or(QString());
        const QString blockAlign = alignmentToString(bf.alignment());
        if (bf.hasProperty(QTextFormat::BlockAlignment)) {
            if (blockAlign != (styleAlign.isEmpty() ? QStringLiteral("left") : styleAlign))
                paragraph.align = blockAlign;
        }
        IndentModel indent;
        bool hasIndent = false;
        if (bf.leftMargin() != style.leftIndent.value_or(0)) {
            indent.left = bf.leftMargin();
            hasIndent = true;
        }
        if (bf.rightMargin() != style.rightIndent.value_or(0)) {
            indent.right = bf.rightMargin();
            hasIndent = true;
        }
        if (bf.textIndent() != style.firstLineIndent.value_or(0)) {
            indent.firstLine = bf.textIndent();
            hasIndent = true;
        }
        if (hasIndent) paragraph.indent = indent;

        if (bf.topMargin() != style.spaceBefore.value_or(0))
            paragraph.spaceBefore = bf.topMargin();
        if (bf.bottomMargin() != style.spaceAfter.value_or(0))
            paragraph.spaceAfter = bf.bottomMargin();

        const double blockSpacing =
            bf.lineHeightType() == QTextBlockFormat::ProportionalHeight
                ? bf.lineHeight() / 100.0 : 1.0;
        if (std::abs(blockSpacing - style.lineSpacing.value_or(1.0)) > 1e-9)
            paragraph.lineSpacing = blockSpacing;

        if (!bf.tabPositions().isEmpty()) {
            QVector<TabStopModel> stops;
            for (const QTextOption::Tab &tab : bf.tabPositions())
                stops.append({tab.position, tabTypeToString(tab.type)});
            paragraph.tabStops = stops;
        }

        // Runs: walk fragments, capturing only run-level deltas; adjacent
        // fragments with identical captured formatting merge into one run.
        for (auto it = block.begin(); !it.atEnd(); ++it) {
            const QTextFragment fragment = it.fragment();
            if (!fragment.isValid() || fragment.text().isEmpty()) continue;
            const QTextCharFormat cf = fragment.charFormat();
            Run run;
            run.text = fragment.text();
            // Object replacement characters can't appear (images are floating,
            // never inline), but strip any that paste smuggled in.
            run.text.remove(QChar(0xFFFC));

            const QString fontName = cf.hasProperty(Props::ModelFont)
                ? cf.stringProperty(Props::ModelFont) : cf.font().family();
            if (fontName != style.font.value_or(QStringLiteral("Helvetica")))
                run.font = fontName;
            const double size = cf.font().pointSizeF();
            if (std::abs(size - style.size.value_or(12.0)) > 1e-9) run.size = size;
            if (cf.font().bold() != style.bold.value_or(false)) run.bold = cf.font().bold();
            if (cf.font().italic() != style.italic.value_or(false))
                run.italic = cf.font().italic();
            if (cf.fontUnderline() != style.underline.value_or(false))
                run.underline = cf.fontUnderline();

            QString colorHex = cf.hasProperty(Props::ModelColor)
                ? cf.stringProperty(Props::ModelColor)
                : colorToHex(cf.foreground().color());
            // The preserved string wins only while it still names the actual
            // color (a Format ▸ Color change updates the foreground, not it).
            if (const auto preserved = parseColor(colorHex)) {
                if (cf.hasProperty(QTextFormat::ForegroundBrush)
                    && *preserved != cf.foreground().color())
                    colorHex = colorToHex(cf.foreground().color());
            }
            const QString styleColor = style.color.value_or(QStringLiteral("#000000"));
            const auto styleParsed = parseColor(styleColor);
            const auto runParsed = parseColor(colorHex);
            if (colorHex != styleColor
                && !(styleParsed && runParsed && *styleParsed == *runParsed))
                run.color = colorHex;

            if (!paragraph.runs.isEmpty()) {
                Run &last = paragraph.runs.last();
                Run mergedProbe = last;
                mergedProbe.text = run.text;
                if (mergedProbe == run) {
                    last.text += run.text;
                    continue;
                }
            }
            paragraph.runs.append(run);
        }
        if (paragraph.runs.isEmpty()) paragraph.runs.append(Run{QString()});
        body.append(paragraph);
    }
    return body;
}

} // namespace DocumentBridge
} // namespace lucerne
