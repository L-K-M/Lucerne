#include "core/Markdown.h"
#include "core/Lists.h"

#include <QFileInfo>
#include <QStringList>

namespace lucerne {
namespace MarkdownExporter {

namespace {

/// Light, targeted escaping — enough to keep the recovery file from
/// accidentally forming emphasis/code/links, without over-escaping prose.
QString escapeInline(const QString &text) {
    QString out;
    out.reserve(text.size());
    for (const QChar ch : text) {
        switch (ch.unicode()) {
        case '\\': case '*': case '_': case '`': case '[': case ']':
            out += QLatin1Char('\\');
            [[fallthrough]];
        default:
            out += ch;
        }
    }
    return out;
}

/// Splits into (leadingWhitespace, core, trailingWhitespace) so emphasis
/// markers never hug whitespace ("** x **" doesn't render).
void splitSurroundingWhitespace(const QString &s, QString &lead, QString &core,
                                QString &trail) {
    int start = 0, end = int(s.size());
    while (start < end && s[start].isSpace()) ++start;
    while (end > start && s[end - 1].isSpace()) --end;
    lead = s.left(start);
    core = s.mid(start, end - start);
    trail = s.mid(end);
}

QString inlineMarkdown(const Run &run) {
    const bool bold = run.bold.value_or(false);
    const bool italic = run.italic.value_or(false);
    const QString escaped = escapeInline(run.text);
    if (!bold && !italic) return escaped;

    QString lead, core, trail;
    splitSurroundingWhitespace(escaped, lead, core, trail);
    if (core.isEmpty()) return escaped;

    const QString marker = bold && italic ? QStringLiteral("***")
                          : bold ? QStringLiteral("**") : QStringLiteral("*");
    return lead + marker + core + marker + trail;
}

QString inlineMarkdown(const Paragraph &paragraph) {
    QString out;
    for (const Run &run : paragraph.runs) out += inlineMarkdown(run);
    return out;
}

/// Block-level escaping for the plain-paragraph path: a paragraph whose text
/// *starts* with a Markdown block marker would otherwise change structure in
/// the recovery file. Neutralize just the leading marker.
QString blockEscape(const QString &line) {
    // Indented code block: 4+ leading spaces → trim to 3 and re-check.
    int start = 0;
    while (start < line.size() && line[start] == QLatin1Char(' ')) ++start;
    if (start >= 4) return QStringLiteral("   ") + blockEscape(line.mid(start));

    const QString indent = line.left(start);
    const QString rest = line.mid(start);
    if (rest.isEmpty()) return line;
    const QChar first = rest[0];

    // Thematic break / setext underline: the whole line is only "-" (3+) or "=".
    if (first == QLatin1Char('-') || first == QLatin1Char('=')) {
        bool uniform = true;
        for (const QChar c : rest) {
            if (c != first) { uniform = false; break; }
        }
        if (uniform && (first == QLatin1Char('=') || rest.size() >= 3))
            return indent + QLatin1Char('\\') + rest;
    }

    // ATX heading: 1–6 "#" then a space.
    if (first == QLatin1Char('#')) {
        int hashes = 0;
        while (hashes < rest.size() && rest[hashes] == QLatin1Char('#')) ++hashes;
        if (hashes <= 6 && hashes < rest.size() && rest[hashes] == QLatin1Char(' '))
            return indent + QLatin1Char('\\') + rest;
    }

    // Blockquote.
    if (first == QLatin1Char('>')) return indent + QLatin1Char('\\') + rest;

    // Bullet list: "- " or "+ " ("*" is already escaped inline).
    if ((first == QLatin1Char('-') || first == QLatin1Char('+'))
        && rest.size() >= 2 && rest[1] == QLatin1Char(' '))
        return indent + QLatin1Char('\\') + rest;

    // Ordered list: digits then ". " or ") " — escape the delimiter only.
    // isNumber (not isDigit) to match Swift's Character.isNumber, which also
    // covers letterlike and other numerals (Nl/No).
    if (first.isNumber()) {
        int digits = 0;
        while (digits < rest.size() && rest[digits].isNumber()) ++digits;
        if (digits + 1 < rest.size()
            && (rest[digits] == QLatin1Char('.') || rest[digits] == QLatin1Char(')'))
            && rest[digits + 1] == QLatin1Char(' '))
            return indent + rest.left(digits) + QLatin1Char('\\') + rest.mid(digits);
    }

    return line;
}

QString block(const QString &inlineText, const QString &markdownRole) {
    if (markdownRole == QLatin1String("h1")) return QStringLiteral("# ") + inlineText;
    if (markdownRole == QLatin1String("h2")) return QStringLiteral("## ") + inlineText;
    if (markdownRole == QLatin1String("h3")) return QStringLiteral("### ") + inlineText;
    if (markdownRole == QLatin1String("h4")) return QStringLiteral("#### ") + inlineText;
    if (markdownRole == QLatin1String("li")) return QStringLiteral("- ") + inlineText;
    if (markdownRole == QLatin1String("blockquote")) return QStringLiteral("> ") + inlineText;
    if (markdownRole == QLatin1String("code")) return QStringLiteral("    ") + inlineText;
    return blockEscape(inlineText);   // "p" and anything unknown
}

// MARK: - Lists

QString listBlock(const QVector<Paragraph> &items) {
    QVector<std::optional<ListItemModel>> descriptors;
    for (const Paragraph &p : items) descriptors.append(p.list);
    const auto resolved = ListMarkers::resolve(descriptors);

    QStringList lines;
    for (int i = 0; i < items.size(); ++i) {
        const auto &item = items[i].list;
        if (!item) continue;
        const QString indent(4 * ListGeometry::clampedLevel(item->level), QLatin1Char(' '));
        const QString inlineText = inlineMarkdown(items[i]);
        if (item->ordered) {
            const int number = resolved[i] && resolved[i]->number ? *resolved[i]->number : 1;
            lines.append(QStringLiteral("%1%2. %3").arg(indent).arg(number).arg(inlineText));
        } else {
            lines.append(QStringLiteral("%1- %2").arg(indent, inlineText));
        }
    }
    return lines.join(QLatin1Char('\n'));
}

// MARK: - Tables

QString rowLine(const QStringList &cells) {
    return QStringLiteral("| ") + cells.join(QStringLiteral(" | ")) + QStringLiteral(" |");
}

QString tableCellText(const Paragraph &paragraph) {
    QString text = inlineMarkdown(paragraph);
    text.replace(QLatin1Char('|'), QStringLiteral("\\|"));
    return text;
}

QString tableBlock(const QVector<Paragraph> &cells, const DocumentModel &model) {
    int columnCount = 0, rowCount = 0;
    for (const Paragraph &p : cells) {
        if (!p.cell) continue;
        columnCount = std::max(columnCount, p.cell->column + std::max(p.cell->columnSpan, 1));
        rowCount = std::max(rowCount, p.cell->row + std::max(p.cell->rowSpan, 1));
    }
    if (columnCount <= 0 || rowCount <= 0) {
        // Degenerate — fall back to plain paragraph blocks.
        QStringList blocks;
        for (const Paragraph &p : cells)
            blocks.append(block(inlineMarkdown(p), model.resolvedStyle(p.style).markdown));
        return blocks.join(QStringLiteral("\n\n"));
    }

    QVector<QStringList> grid(rowCount, QStringList());
    for (auto &row : grid)
        for (int c = 0; c < columnCount; ++c) row.append(QString());
    for (const Paragraph &p : cells) {
        if (!p.cell) continue;
        const int r = p.cell->row, c = p.cell->column;
        if (r < 0 || r >= rowCount || c < 0 || c >= columnCount) continue;
        grid[r][c] = tableCellText(p);
    }

    // GFM needs a header + delimiter row; row 0 is the header by convention.
    QStringList lines;
    lines.append(rowLine(grid[0]));
    QStringList delims;
    for (int c = 0; c < columnCount; ++c) delims.append(QStringLiteral("---"));
    lines.append(rowLine(delims));
    for (int r = 1; r < rowCount; ++r) lines.append(rowLine(grid[r]));
    return lines.join(QLatin1Char('\n'));
}

// MARK: - Images

QString altText(const PlacedObject &object) {
    if (object.src) {
        // Mirror NSString.deletingPathExtension: strip one trailing extension,
        // but a leading dot is not an extension separator (".hidden" keeps its
        // name — QFileInfo::completeBaseName would empty it out).
        const QString name = QFileInfo(*object.src).fileName();
        const qsizetype lastDot = name.lastIndexOf(QLatin1Char('.'));
        const QString stem = lastDot > 0 ? name.left(lastDot) : name;
        if (!stem.isEmpty()) return stem;
    }
    return object.id;
}

bool isNewlineChar(QChar c) {
    switch (c.unicode()) {
    case '\n': case '\r': case '\v': case '\f': case 0x85: case 0x2028: case 0x2029:
        return true;
    default:
        return false;
    }
}

QString escapeImageAltText(const QString &text) {
    QString out;
    out.reserve(text.size());
    for (const QChar ch : text) {
        if (isNewlineChar(ch)) {
            out += QLatin1Char(' ');
        } else if (ch == QLatin1Char('\\') || ch == QLatin1Char('[')
                   || ch == QLatin1Char(']')) {
            out += QLatin1Char('\\');
            out += ch;
        } else {
            out += ch;
        }
    }
    return out;
}

/// Percent-encode bytes that can terminate or change a Markdown link
/// destination, keeping ordinary relative paths readable.
QString escapeImageDestination(const QString &destination) {
    static const char hex[] = "0123456789ABCDEF";
    const QByteArray utf8 = destination.toUtf8();
    QString out;
    out.reserve(utf8.size());
    for (const char raw : utf8) {
        const quint8 byte = quint8(raw);
        const bool alnum = (byte >= '0' && byte <= '9') || (byte >= 'A' && byte <= 'Z')
            || (byte >= 'a' && byte <= 'z');
        if (alnum || byte == '-' || byte == '.' || byte == '/' || byte == '_'
            || byte == '~') {
            out += QLatin1Char(char(byte));
        } else {
            out += QLatin1Char('%');
            out += QLatin1Char(hex[byte >> 4]);
            out += QLatin1Char(hex[byte & 0x0f]);
        }
    }
    return out;
}

} // namespace

QString exportModel(const DocumentModel &model) {
    QStringList blocks;

    const QVector<Paragraph> &body = model.body;
    int i = 0;
    while (i < body.size()) {
        const Paragraph &paragraph = body[i];
        // A run of consecutive cell paragraphs sharing a table id becomes one
        // GFM pipe table (spec §8 item 7).
        if (paragraph.cell) {
            const QString tableID = paragraph.cell->table;
            QVector<Paragraph> group;
            while (i < body.size() && body[i].cell && body[i].cell->table == tableID) {
                group.append(body[i]);
                ++i;
            }
            blocks.append(tableBlock(group, model));
            continue;
        }
        // A run of list items sharing one list id becomes one tight block.
        // Grouping by id keeps two adjacent lists as separate blocks so a
        // viewer restarts the second list's numbering. Cells never join.
        if (paragraph.list && !paragraph.cell) {
            const QString listID = paragraph.list->list;
            QVector<Paragraph> group;
            while (i < body.size() && body[i].list && body[i].list->list == listID
                   && !body[i].cell) {
                group.append(body[i]);
                ++i;
            }
            blocks.append(listBlock(group));
            continue;
        }
        const ParagraphStyle style = model.resolvedStyle(paragraph.style);
        blocks.append(block(inlineMarkdown(paragraph), style.markdown));
        ++i;
    }

    // Pictures appended after the prose, ordered by (page, z); page-anchored
    // objects with no page sort last.
    QVector<PlacedObject> images;
    for (const PlacedObject &object : model.objects)
        if (object.type == QLatin1String("image")) images.append(object);
    std::stable_sort(images.begin(), images.end(),
                     [](const PlacedObject &a, const PlacedObject &b) {
        const int pa = a.page.value_or(std::numeric_limits<int>::max());
        const int pb = b.page.value_or(std::numeric_limits<int>::max());
        if (pa != pb) return pa < pb;
        return a.z < b.z;
    });
    for (const PlacedObject &object : images) {
        if (!object.src) continue;
        blocks.append(QStringLiteral("![%1](%2)")
                          .arg(escapeImageAltText(altText(object)),
                               escapeImageDestination(*object.src)));
    }

    return blocks.join(QStringLiteral("\n\n")) + QLatin1Char('\n');
}

} // namespace MarkdownExporter
} // namespace lucerne
