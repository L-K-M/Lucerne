#include "core/DefaultDocuments.h"

namespace lucerne {
namespace DefaultDocuments {

namespace {

ParagraphStyle style(const QString &name, const QString &markdown, const QString &font,
                     double size, double order) {
    ParagraphStyle s;
    s.name = name;
    s.markdown = markdown;
    s.font = font;
    s.size = size;
    s.order = order;
    return s;
}

Paragraph paragraph(const QString &id, const QString &styleRole, const QString &text) {
    Paragraph p;
    p.id = id;
    p.style = styleRole;
    p.runs.append(Run{text});
    return p;
}

const char *const sampleLetterImageSource = "images/lake.png";

// 120 x 80 indexed-colour PNG: sky, mountains, sun, and lake (389 bytes) —
// identical to the Mac app's embedded sample image.
const char *const sampleLetterImageBase64 =
    "iVBORw0KGgoAAAANSUhEUgAAAHgAAABQCAMAAADlRUG7AAAAG1BMVEWJwuv/4HdefI7e5+EtUFg3"
    "ia1brsoeaJHGtH5OZNdCAAABJUlEQVR42u3XWxKCMAwFUHojdf87dhweFppQtAlgyf1DY04LjTN0"
    "ncfj+ZeEc9QhZ7m8TAe4rExE9i4nE1nRe2ATugCDjOgQtmXAii7tGB/6eNiE3oRpgi1o2X07gB0t"
    "uIOCXCZtmZ1fAJab7gL7t0FYwRKttJaZRQ5ztNJtSFgWXtOk8+gXrADP+cz5dFmKVJO3xlcpsUIN"
    "1wmKslDENwK0aKFIagMtma+SuwAqdPlkasDY45ZaQEPGYfCe42MEo86tgEf65x+jTsYpcNWiHW4f"
    "fpyUJuHkTeJKcG+XBM6/bBLuN9wFHLUzw+P15XbcDtzLrsOr1B3q3XCMNgOVrCSBo2mWcBqHDeTo"
    "cNtwFNw7wk/jBOHze8Pmz9hvtcM+Tj5OKvALmkV2w3RUVbcAAAAASUVORK5CYII=";

const char *const loremA =
    "Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod "
    "tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim "
    "veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea "
    "commodo consequat. Duis aute irure dolor in reprehenderit in voluptate.";
const char *const loremB =
    "Velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint "
    "occaecat cupidatat non proident, sunt in culpa qui officia deserunt "
    "mollit anim id est laborum. Sed ut perspiciatis unde omnis iste natus "
    "error sit voluptatem accusantium doloremque laudantium, totam rem.";
const char *const loremC =
    "Aperiam eaque ipsa quae ab illo inventore veritatis et quasi architecto "
    "beatae vitae dicta sunt explicabo. Nemo enim ipsam voluptatem quia "
    "voluptas sit aspernatur aut odit aut fugit, sed quia consequuntur magni "
    "dolores eos qui ratione voluptatem sequi nesciunt. Neque porro quisquam.";

} // namespace

QMap<QString, ParagraphStyle> defaultStyles() {
    QMap<QString, ParagraphStyle> styles;

    ParagraphStyle body = style(QStringLiteral("Body"), QStringLiteral("p"),
                                QStringLiteral("Helvetica"), 12, 0);
    body.lineSpacing = 1.2;
    body.spaceAfter = 6;
    styles.insert(QStringLiteral("body"), body);

    ParagraphStyle h1 = style(QStringLiteral("Heading 1"), QStringLiteral("h1"),
                              QStringLiteral("Helvetica"), 24, 1);
    h1.bold = true;
    h1.spaceBefore = 18;
    h1.spaceAfter = 8;
    styles.insert(QStringLiteral("heading1"), h1);

    ParagraphStyle h2 = style(QStringLiteral("Heading 2"), QStringLiteral("h2"),
                              QStringLiteral("Helvetica"), 18, 2);
    h2.bold = true;
    h2.spaceBefore = 14;
    h2.spaceAfter = 6;
    styles.insert(QStringLiteral("heading2"), h2);

    ParagraphStyle li = style(QStringLiteral("List Item"), QStringLiteral("li"),
                              QStringLiteral("Helvetica"), 12, 3);
    li.leftIndent = 24;
    styles.insert(QStringLiteral("listItem"), li);

    ParagraphStyle quote = style(QStringLiteral("Block Quote"), QStringLiteral("blockquote"),
                                 QStringLiteral("Helvetica"), 12, 4);
    quote.italic = true;
    quote.leftIndent = 36;
    styles.insert(QStringLiteral("quote"), quote);

    return styles;
}

QStringList styleRoleOrder() {
    return {QStringLiteral("body"), QStringLiteral("heading1"), QStringLiteral("heading2"),
            QStringLiteral("listItem"), QStringLiteral("quote")};
}

QMap<QString, ParagraphStyle> starterLibraryStyles() {
    // The classic five, mirrored with their library positions…
    QMap<QString, ParagraphStyle> styles = defaultStyles();
    styles[QStringLiteral("body")].order = 0;
    styles[QStringLiteral("heading1")].order = 1;
    styles[QStringLiteral("heading2")].order = 2;
    styles[QStringLiteral("listItem")].order = 6;
    styles[QStringLiteral("quote")].order = 7;

    // …plus the additions.
    ParagraphStyle h3 = style(QStringLiteral("Heading 3"), QStringLiteral("h3"),
                              QStringLiteral("Helvetica"), 14, 3);
    h3.bold = true;
    h3.spaceBefore = 12;
    h3.spaceAfter = 4;
    styles.insert(QStringLiteral("heading3"), h3);

    ParagraphStyle title = style(QStringLiteral("Title"), QStringLiteral("h1"),
                                 QStringLiteral("Helvetica"), 30, 4);
    title.bold = true;
    title.spaceAfter = 6;
    title.alignment = QStringLiteral("center");
    styles.insert(QStringLiteral("title"), title);

    ParagraphStyle subtitle = style(QStringLiteral("Subtitle"), QStringLiteral("p"),
                                    QStringLiteral("Helvetica"), 15, 5);
    subtitle.spaceAfter = 18;
    subtitle.alignment = QStringLiteral("center");
    subtitle.color = QStringLiteral("#444444");
    styles.insert(QStringLiteral("subtitle"), subtitle);

    ParagraphStyle code = style(QStringLiteral("Code"), QStringLiteral("code"),
                                QStringLiteral("Menlo"), 11, 8);
    code.lineSpacing = 1.2;
    code.leftIndent = 18;
    styles.insert(QStringLiteral("code"), code);

    ParagraphStyle pull = style(QStringLiteral("Pull Quote"), QStringLiteral("blockquote"),
                                QStringLiteral("Helvetica"), 16, 9);
    pull.italic = true;
    pull.spaceBefore = 12;
    pull.spaceAfter = 12;
    pull.leftIndent = 36;
    pull.rightIndent = 36;
    pull.alignment = QStringLiteral("center");
    pull.color = QStringLiteral("#333333");
    styles.insert(QStringLiteral("pullQuote"), pull);

    ParagraphStyle caption = style(QStringLiteral("Caption"), QStringLiteral("p"),
                                   QStringLiteral("Helvetica"), 10, 10);
    caption.italic = true;
    caption.spaceBefore = 4;
    caption.spaceAfter = 12;
    caption.alignment = QStringLiteral("center");
    caption.color = QStringLiteral("#555555");
    styles.insert(QStringLiteral("caption"), caption);

    ParagraphStyle fine = style(QStringLiteral("Fine Print"), QStringLiteral("p"),
                                QStringLiteral("Helvetica"), 9, 11);
    fine.lineSpacing = 1.15;
    fine.color = QStringLiteral("#666666");
    styles.insert(QStringLiteral("finePrint"), fine);

    return styles;
}

DocumentModel empty(const PageConfig &page) {
    DocumentModel model;
    model.page = page;
    model.styles = defaultStyles();
    Paragraph p;
    p.id = IDGenerator::next(QStringLiteral("p"));
    p.style = QStringLiteral("body");
    p.runs.append(Run{QString()});
    model.body.append(p);
    return model;
}

DocumentModel sampleLetter(const PageConfig &page) {
    DocumentModel model;
    model.page = page;
    model.styles = defaultStyles();

    model.body.append(paragraph(QStringLiteral("p1"), QStringLiteral("heading1"),
                                QStringLiteral("A Letter from the Lake")));
    auto firstLineIndented = [](const QString &id, const QString &text) {
        Paragraph p = paragraph(id, QStringLiteral("body"), text);
        IndentModel indent;
        indent.firstLine = 18;
        p.indent = indent;
        return p;
    };
    model.body.append(firstLineIndented(QStringLiteral("p2"), QStringLiteral("Dear friend,")));
    {
        Paragraph p3;
        p3.id = QStringLiteral("p3");
        p3.style = QStringLiteral("body");
        IndentModel indent;
        indent.firstLine = 18;
        p3.indent = indent;
        p3.runs.append(Run{QStringLiteral("Thank you for the ")});
        Run wonderful{QStringLiteral("wonderful")};
        wonderful.italic = true;
        p3.runs.append(wonderful);
        p3.runs.append(Run{QStringLiteral(
            " afternoon by the water — the light on the mountains was exactly as "
            "you described it. I have placed a little picture below; notice how "
            "these very words flow politely around it, and keep flowing correctly "
            "even as the paragraph is edited.")});
        model.body.append(p3);
    }
    model.body.append(firstLineIndented(QStringLiteral("p4"), QString::fromUtf8(loremA)));
    model.body.append(firstLineIndented(QStringLiteral("p5"), QString::fromUtf8(loremB)));
    model.body.append(firstLineIndented(QStringLiteral("p6"), QString::fromUtf8(loremC)));
    model.body.append(paragraph(QStringLiteral("p7"), QStringLiteral("body"),
                                QStringLiteral("Warmly, and with the lake's regards,")));
    {
        Paragraph p8 = paragraph(QStringLiteral("p8"), QStringLiteral("body"),
                                 QStringLiteral("— Lucerne"));
        p8.runs[0].italic = true;
        model.body.append(p8);
    }

    PlacedObject image;
    image.id = QStringLiteral("img1");
    image.src = QString::fromLatin1(sampleLetterImageSource);
    image.page = 0;
    image.frame = RectModel{300, 300, 220, 150};
    image.z = 1;
    model.objects.append(image);

    return model;
}

QMap<QString, QByteArray> sampleLetterImages() {
    const QByteArray image = QByteArray::fromBase64(sampleLetterImageBase64);
    return {{QString::fromLatin1(sampleLetterImageSource), image}};
}

} // namespace DefaultDocuments
} // namespace lucerne
