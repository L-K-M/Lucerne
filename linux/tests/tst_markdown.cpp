// Markdown exporter (C++) — mirrors the load-bearing cases of Swift's
// ModelTests (exporter half), MarkdownExportEdgeTests, and
// ListMarkdownExportTests so content.md derivation matches across ports.

#include "core/DefaultDocuments.h"
#include "core/Markdown.h"

#include <QtTest>

using namespace lucerne;

namespace {

DocumentModel base() {
    DocumentModel model;
    model.page = PageConfig::a4();
    model.styles = DefaultDocuments::defaultStyles();
    return model;
}

Paragraph para(const QString &id, const QString &style, const QString &text) {
    Paragraph p;
    p.id = id;
    p.style = style;
    p.runs.append(Run{text});
    return p;
}

} // namespace

class tst_markdown : public QObject {
    Q_OBJECT

private slots:
    void headingsListsAndQuotes() {
        DocumentModel model = base();
        model.body.append(para("p1", "heading1", "Title"));
        model.body.append(para("p2", "heading2", "Sub"));
        model.body.append(para("p3", "listItem", "An item"));
        model.body.append(para("p4", "quote", "Wise words"));
        model.body.append(para("p5", "body", "Prose."));
        QCOMPARE(MarkdownExporter::exportModel(model),
                 QStringLiteral("# Title\n\n## Sub\n\n- An item\n\n> Wise words\n\nProse.\n"));
    }

    void inlineBoldItalicMapping() {
        DocumentModel model = base();
        Paragraph p;
        p.id = "p1";
        p.style = "body";
        p.runs.append(Run{"plain "});
        Run bold{"bold"};
        bold.bold = true;
        p.runs.append(bold);
        p.runs.append(Run{" and "});
        Run both{"both"};
        both.bold = true;
        both.italic = true;
        p.runs.append(both);
        model.body.append(p);
        QCOMPARE(MarkdownExporter::exportModel(model),
                 QStringLiteral("plain **bold** and ***both***\n"));
    }

    void emphasisMarkersDoNotHugWhitespace() {
        DocumentModel model = base();
        Paragraph p;
        p.id = "p1";
        p.style = "body";
        Run italicWithTrailingSpace{"word "};
        italicWithTrailingSpace.italic = true;
        p.runs.append(italicWithTrailingSpace);
        p.runs.append(Run{"next"});
        model.body.append(p);
        QCOMPARE(MarkdownExporter::exportModel(model), QStringLiteral("*word* next\n"));
    }

    void specialCharactersAreEscaped() {
        DocumentModel model = base();
        model.body.append(para("p1", "body", "a*b_c`d[e]f\\g"));
        QCOMPARE(MarkdownExporter::exportModel(model),
                 QStringLiteral("a\\*b\\_c\\`d\\[e\\]f\\\\g\n"));
    }

    void leadingBlockMarkersAreNeutralized() {
        DocumentModel model = base();
        model.body.append(para("p1", "body", "# not a heading"));
        model.body.append(para("p2", "body", "1. not a list"));
        model.body.append(para("p3", "body", "---"));
        model.body.append(para("p4", "body", "> not a quote"));
        QCOMPARE(MarkdownExporter::exportModel(model),
                 QStringLiteral("\\# not a heading\n\n1\\. not a list\n\n\\---\n\n"
                                "\\> not a quote\n"));
    }

    void imagesEmittedAsLinksOrderedByPageThenZ() {
        DocumentModel model = base();
        model.body.append(para("p1", "body", "Prose."));
        PlacedObject late;
        late.id = "b";
        late.src = QStringLiteral("images/z space.png");
        late.page = 1;
        late.frame = RectModel{0, 0, 10, 10};
        PlacedObject early;
        early.id = "a";
        early.src = QStringLiteral("images/lake.png");
        early.page = 0;
        early.frame = RectModel{0, 0, 10, 10};
        model.objects = {late, early};
        QCOMPARE(MarkdownExporter::exportModel(model),
                 QStringLiteral("Prose.\n\n![lake](images/lake.png)\n\n"
                                "![z space](images/z%20space.png)\n"));
    }

    void tightListWithNestingAndNumbering() {
        DocumentModel model = base();
        auto item = [&](const QString &id, const QString &text, bool ordered,
                        const QString &marker, int level) {
            Paragraph p = para(id, "body", text);
            ListItemModel list;
            list.list = "L";
            list.ordered = ordered;
            list.marker = marker;
            list.level = level;
            p.list = list;
            return p;
        };
        model.body.append(item("l1", "First", true, "decimal", 0));
        model.body.append(item("l2", "Nested", false, "disc", 1));
        model.body.append(item("l3", "Second", true, "upper-roman", 0));
        QCOMPARE(MarkdownExporter::exportModel(model),
                 QStringLiteral("1. First\n    - Nested\n2. Second\n"));
    }

    void tableBecomesGFMPipeTable() {
        DocumentModel model = base();
        auto cell = [&](const QString &id, const QString &text, int row, int col) {
            Paragraph p = para(id, "body", text);
            TableCellModel c;
            c.table = "t";
            c.row = row;
            c.column = col;
            p.cell = c;
            return p;
        };
        model.body.append(cell("c00", "H1", 0, 0));
        model.body.append(cell("c01", "H2", 0, 1));
        model.body.append(cell("c10", "a|b", 1, 0));
        model.body.append(cell("c11", "y", 1, 1));
        QCOMPARE(MarkdownExporter::exportModel(model),
                 QStringLiteral("| H1 | H2 |\n| --- | --- |\n| a\\|b | y |\n"));
    }
};

QTEST_GUILESS_MAIN(tst_markdown)
#include "tst_markdown.moc"
