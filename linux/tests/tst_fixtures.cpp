// The shared .luce conformance corpus (docs/ubuntu-port.md §3): the same
// files Swift's SpecFixtureTests walks (Tests/Fixtures at the repo root,
// injected as LUCERNE_FIXTURES_DIR). Every valid fixture must open and
// round-trip through this implementation's writer, and the invalid ones must
// be rejected for the reason their name states — this is what keeps the Qt
// port file-level compatible with the Mac app.

#include "core/Coding.h"
#include "core/Lists.h"
#include "core/LuceArchive.h"
#include "core/Markdown.h"
#include "core/PageMetrics.h"
#include "testutil.h"

#include <QDir>
#include <QtTest>

using namespace lucerne;

namespace {

QByteArray fixture(const QString &name) {
    QFile file(QStringLiteral(LUCERNE_FIXTURES_DIR) + QLatin1Char('/') + name);
    if (!file.open(QIODevice::ReadOnly)) return {};
    return file.readAll();
}

const QStringList validFixtures = {
    QStringLiteral("minimal.luce"),      QStringLiteral("kitchen-sink.luce"),
    QStringLiteral("lists.luce"),        QStringLiteral("tables.luce"),
    QStringLiteral("history.luce"),      QStringLiteral("deflate.luce"),
};

} // namespace

class tst_fixtures : public QObject {
    Q_OBJECT

private slots:
    void corpusIsFullyEnumerated() {
        // Adding a fixture without wiring it up here must fail loudly (the
        // Swift suite has the same guard).
        QDir dir(QStringLiteral(LUCERNE_FIXTURES_DIR));
        QVERIFY2(dir.exists(), "fixtures directory missing — configure with the repo checkout");
        QStringList onDisk = dir.entryList({QStringLiteral("*.luce")}, QDir::Files);
        onDisk.sort();
        QStringList expected = validFixtures;
        expected.sort();
        QCOMPARE(onDisk, expected);

        // The rejection corpus is enumerated too - an invalid/ fixture added
        // without a matching rejection test must fail loudly as well.
        QDir invalid(dir.filePath(QStringLiteral("invalid")));
        QStringList invalidOnDisk =
            invalid.entryList({QStringLiteral("*.luce")}, QDir::Files);
        invalidOnDisk.sort();
        QCOMPARE(invalidOnDisk,
                 (QStringList{QStringLiteral("format-too-new.luce"),
                              QStringLiteral("wrong-format.luce")}));
    }

    void validFixturesOpenAndRoundTrip() {
        for (const QString &name : validFixtures) {
            const QByteArray data = fixture(name);
            QVERIFY2(!data.isEmpty(), qPrintable(name));
            const LuceArchive::Contents contents = LuceArchive::read(data);

            // JSON round-trip through this implementation's writer.
            const DocumentModel redecoded = Coding::decode(Coding::encode(contents.model));
            QVERIFY2(redecoded == contents.model, qPrintable(name + ": JSON round-trip drifted"));

            // Archive round-trip. The writer refuses dangling image references,
            // so supply a stand-in payload for any missing source.
            QMap<QString, QByteArray> images = contents.images;
            for (const PlacedObject &object : contents.model.objects) {
                if (object.type != QLatin1String("image") || !object.src) continue;
                if (!images.contains(*object.src))
                    images.insert(*object.src, QByteArrayLiteral("\x89PNG"));
            }
            const QByteArray rewritten =
                LuceArchive::write(contents.model, images, contents.history);
            const LuceArchive::Contents reread = LuceArchive::read(rewritten);
            QVERIFY2(reread.model == contents.model,
                     qPrintable(name + ": archive round-trip drifted"));
            QCOMPARE(reread.history.size(), contents.history.size());
        }
    }

    void kitchenSinkDecodesEveryModelledFeature() {
        const LuceArchive::Contents contents =
            LuceArchive::read(fixture(QStringLiteral("kitchen-sink.luce")));
        const DocumentModel &model = contents.model;

        QCOMPARE(model.page.size, QStringLiteral("custom"));
        QCOMPARE(model.page.width, 500.0);
        QCOMPARE(model.page.foldMarks, std::optional<bool>(true));
        QVERIFY(model.header && model.header->left == QLatin1String("{title}"));
        QVERIFY(model.footer && model.footer->center == QLatin1String("Page {page} of {pages}"));
        QCOMPARE(model.pageNumberStart, std::optional<int>(2));

        const ParagraphStyle fancy = model.styles.value(QStringLiteral("fancy"));
        QCOMPARE(fancy.underline, std::optional<bool>(true));
        QCOMPARE(fancy.firstLineIndent, std::optional<double>(-10));
        QCOMPARE(fancy.color, std::optional<QString>(QStringLiteral("#8000FF80")));

        const Paragraph *p2 = nullptr;
        for (const Paragraph &p : model.body)
            if (p.id == QLatin1String("p2")) p2 = &p;
        QVERIFY(p2);
        QVERIFY(p2->tabStops && p2->tabStops->size() == 4);
        QCOMPARE(p2->tabStops->at(3).type, QStringLiteral("decimal"));
        QCOMPARE(p2->align, std::optional<QString>(QStringLiteral("right")));
        QCOMPARE(p2->runs[3].font, std::optional<QString>(QStringLiteral("Courier")));

        // Unknown style role resolves through the body fallback.
        QCOMPARE(model.resolvedStyle(QStringLiteral("unknownRole")).name,
                 QStringLiteral("Body"));

        // Object defaults (Appendix C) for omitted members.
        const PlacedObject *img2 = nullptr, *anchored = nullptr, *future = nullptr;
        for (const PlacedObject &o : model.objects) {
            if (o.id == QLatin1String("img2")) img2 = &o;
            if (o.id == QLatin1String("anchored")) anchored = &o;
            if (o.id == QLatin1String("future")) future = &o;
        }
        QVERIFY(img2 && img2->type == QLatin1String("image") && img2->standoff == 12
                && img2->wrapMode() == PlacedObject::Wrap::None);
        QVERIFY(anchored && anchored->anchorMode() == PlacedObject::Anchor::Paragraph
                && anchored->offset == std::optional<PointModel>(PointModel{10, 20}));
        QVERIFY2(future, "unknown object types must be kept, not dropped");

        QVERIFY(contents.images.contains(QStringLiteral("images/lake.png")));
        QVERIFY(!contents.images.contains(QStringLiteral("images/missing.png")));

        // The wrapping objects on page 0 produce exclusion rects in z order
        // (img3 irregular→rect and img1; img2 wraps none).
        const PageMetrics metrics{model.page};
        QCOMPARE(ExclusionPathController::exclusionRects(0, model.objects, metrics).size(), 2);
    }

    void listsFixtureNumbering() {
        const DocumentModel model =
            LuceArchive::read(fixture(QStringLiteral("lists.luce"))).model;
        QVector<std::optional<ListItemModel>> items;
        for (const Paragraph &p : model.body) items.append(p.list);
        const auto resolved = ListMarkers::resolve(items);
        QMap<QString, QString> byID;
        for (int i = 0; i < model.body.size(); ++i)
            byID.insert(model.body[i].id, resolved[i] ? resolved[i]->text : QString());
        QCOMPARE(byID.value("l1"), QStringLiteral("1."));
        QCOMPARE(byID.value("l3"), QStringLiteral("a."));
        QCOMPARE(byID.value("l5"), QStringLiteral("3."));
        QCOMPARE(byID.value("l6"), QStringLiteral("–"));
        QCOMPARE(byID.value("l7"), QStringLiteral("4."));
        QCOMPARE(byID.value("break"), QString());
        QCOMPARE(byID.value("l8"), QStringLiteral("X."));
        QCOMPARE(byID.value("l9"), QStringLiteral("◦"));
    }

    void tablesFixtureMarkdown() {
        const DocumentModel model =
            LuceArchive::read(fixture(QStringLiteral("tables.luce"))).model;
        const QString markdown = MarkdownExporter::exportModel(model);
        QVERIFY2(markdown.contains("| Header A | Header B | Header C |"),
                 qPrintable(markdown));
        QVERIFY2(markdown.contains("y \\| pipe"), qPrintable(markdown));
    }

    void historyFixtureSnapshots() {
        const LuceArchive::Contents contents =
            LuceArchive::read(fixture(QStringLiteral("history.luce")));
        QCOMPARE(contents.history.size(), 2);   // the unparseable name is skipped
    }

    void wrongFormatIsRejected() {
        try {
            LuceArchive::read(fixture(QStringLiteral("invalid/wrong-format.luce")));
            QFAIL("expected CodingError");
        } catch (const CodingError &error) {
            QCOMPARE(int(error.kind()), int(CodingError::Kind::WrongFormat));
        }
    }

    void tooNewFormatVersionIsRejected() {
        try {
            LuceArchive::read(fixture(QStringLiteral("invalid/format-too-new.luce")));
            QFAIL("expected CodingError");
        } catch (const CodingError &error) {
            QCOMPARE(int(error.kind()), int(CodingError::Kind::FormatTooNew));
        }
    }
};

QTEST_GUILESS_MAIN(tst_fixtures)
#include "tst_fixtures.moc"
