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
#include "core/MiniZip.h"
#include "core/PageMetrics.h"
#include "testutil.h"

#include <QDir>
#include <QtTest>

#include <optional>

using namespace lucerne;

namespace {

QByteArray fixture(const QString &name) {
    QFile file(QStringLiteral(LUCERNE_FIXTURES_DIR) + QLatin1Char('/') + name);
    if (!file.open(QIODevice::ReadOnly)) return {};
    return file.readAll();
}

/// LuceArchive::read wrapped so a rejected fixture becomes a loud, named test
/// failure instead of an uncaught exception that aborts the whole binary
/// (QtTest does not catch exceptions escaping a slot).
std::optional<LuceArchive::Contents> tryRead(const QByteArray &data) {
    try {
        return LuceArchive::read(data);
    } catch (const std::exception &) {
        return std::nullopt;
    }
}

/// fixture() with a loud failure when the file is missing, so a moved or
/// renamed fixture fails with "file missing", never with a misleading
/// downstream parse error.
#define REQUIRE_FIXTURE(var, name)                                              \
    const QByteArray var = fixture(QStringLiteral(name));                       \
    QVERIFY2(!var.isEmpty(), name " missing - check LUCERNE_FIXTURES_DIR")

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
            LuceArchive::Contents contents;
            try {
                contents = LuceArchive::read(data);
            } catch (const std::exception &error) {
                // Name the fixture: an exception escaping the slot would abort
                // the whole binary without saying which of the six files broke.
                QFAIL(qPrintable(QStringLiteral("valid fixture rejected: %1 (%2)")
                                     .arg(name, QString::fromUtf8(error.what()))));
            }

            // JSON round-trip through this implementation's writer.
            const DocumentModel redecoded = Coding::decode(Coding::encode(contents.model));
            QVERIFY2(redecoded == contents.model, qPrintable(name + ": JSON round-trip drifted"));

            // Archive round-trip. The writer refuses dangling image references,
            // so supply a stand-in payload for any missing source.
            QMap<QString, QByteArray> images = contents.images;
            QMap<QString, QByteArray> expectedImages;   // the writer keeps referenced only
            for (const PlacedObject &object : contents.model.objects) {
                if (object.type != QLatin1String("image") || !object.src) continue;
                if (!images.contains(*object.src))
                    images.insert(*object.src, QByteArrayLiteral("\x89PNG"));
                expectedImages.insert(*object.src, images.value(*object.src));
            }
            const QByteArray rewritten =
                LuceArchive::write(contents.model, images, contents.history);
            const auto rereadParsed = tryRead(rewritten);
            QVERIFY2(rereadParsed, qPrintable(name + ": rewritten archive rejected"));
            const LuceArchive::Contents &reread = *rereadParsed;
            QVERIFY2(reread.model == contents.model,
                     qPrintable(name + ": archive round-trip drifted"));
            // Referenced payloads survive byte-identically; orphan entries are
            // shed (the writer keeps "only images actually referenced").
            QVERIFY2(reread.images == expectedImages,
                     qPrintable(name + ": image payloads did not survive the round-trip"));
            QCOMPARE(reread.history.size(), contents.history.size());
            for (int i = 0; i < contents.history.size(); ++i) {
                QCOMPARE(reread.history[i].timestamp, contents.history[i].timestamp);
                QCOMPARE(reread.history[i].markdown, contents.history[i].markdown);
            }
        }
    }

    void kitchenSinkDecodesEveryModelledFeature() {
        REQUIRE_FIXTURE(data, "kitchen-sink.luce");
        const auto parsed = tryRead(data);
        QVERIFY2(parsed, "kitchen-sink.luce rejected");
        const LuceArchive::Contents &contents = *parsed;
        const DocumentModel &model = contents.model;

        QCOMPARE(model.page.size, QStringLiteral("custom"));
        QCOMPARE(model.page.width, 500.0);
        QCOMPARE(model.page.height, 700.0);
        QCOMPARE(model.page.margins.right, 40.0);
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
        // Every assertion the Swift twin makes (SpecFixtureTests.swift) must
        // hold here too: the corpus is only a compatibility signal if BOTH
        // readers are pinned to the same decoded values.
        QVERIFY(p2->tabStops && p2->tabStops->size() == 4);
        QCOMPARE(p2->tabStops->at(0).type, QStringLiteral("left"));
        QCOMPARE(p2->tabStops->at(1).type, QStringLiteral("center"));
        QCOMPARE(p2->tabStops->at(2).type, QStringLiteral("right"));
        QCOMPARE(p2->tabStops->at(3).type, QStringLiteral("decimal"));
        QCOMPARE(p2->align, std::optional<QString>(QStringLiteral("right")));
        QVERIFY(p2->indent && p2->indent->firstLine == std::optional<double>(18));
        QCOMPARE(p2->lineSpacing, std::optional<double>(1.5));
        QCOMPARE(p2->runs[1].italic, std::optional<bool>(true));
        QCOMPARE(p2->runs[2].bold, std::optional<bool>(true));
        QCOMPARE(p2->runs[3].font, std::optional<QString>(QStringLiteral("Courier")));
        QCOMPARE(p2->runs[3].color, std::optional<QString>(QStringLiteral("#123456")));

        // Empty runs array tolerated (spec §6.1); explicit page break kept.
        const Paragraph *p4 = nullptr, *p5 = nullptr;
        for (const Paragraph &p : model.body) {
            if (p.id == QLatin1String("p4")) p4 = &p;
            if (p.id == QLatin1String("p5")) p5 = &p;
        }
        QVERIFY(p4 && p4->runs.isEmpty());
        QVERIFY(p5 && p5->pageBreakBefore == std::optional<bool>(true));

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
        QCOMPARE(anchored->anchorParagraph, std::optional<QString>(QStringLiteral("p2")));
        QVERIFY2(future, "unknown object types must be kept, not dropped");

        QVERIFY(contents.images.contains(QStringLiteral("images/lake.png")));
        QVERIFY(!contents.images.contains(QStringLiteral("images/missing.png")));

        // The wrapping objects on page 0 produce exclusion rects in z order
        // (img3 irregular→rect and img1; img2 wraps none).
        const PageMetrics metrics{model.page};
        QCOMPARE(ExclusionPathController::exclusionRects(0, model.objects, metrics).size(), 2);
    }

    void listsFixtureNumbering() {
        REQUIRE_FIXTURE(data, "lists.luce");
        const auto parsed = tryRead(data);
        QVERIFY2(parsed, "lists.luce rejected");
        const DocumentModel &model = parsed->model;
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
        REQUIRE_FIXTURE(data, "tables.luce");
        const auto parsed = tryRead(data);
        QVERIFY2(parsed, "tables.luce rejected");
        const DocumentModel &model = parsed->model;
        const QString markdown = MarkdownExporter::exportModel(model);
        QVERIFY2(markdown.contains("| Header A | Header B | Header C |"),
                 qPrintable(markdown));
        QVERIFY2(markdown.contains("y \\| pipe"), qPrintable(markdown));
    }

    void historyFixtureSnapshots() {
        REQUIRE_FIXTURE(data, "history.luce");
        const auto parsed = tryRead(data);
        QVERIFY2(parsed, "history.luce rejected");
        QCOMPARE(parsed->history.size(), 2);   // the unparseable name is skipped
    }

    void traversalImageNamesAreIgnoredOnRead() {
        // Ported from Swift's FormatSafetyTests: only flat "images/<file>"
        // names may enter the image map, so a hostile bundle can't smuggle
        // path-traversal entries toward a future extract-images feature.
        REQUIRE_FIXTURE(data, "minimal.luce");
        const auto parsed = tryRead(data);
        QVERIFY2(parsed, "minimal.luce rejected");
        const QByteArray archive = MiniZip::archive({
            {QStringLiteral("document.json"), Coding::encode(parsed->model)},
            {QStringLiteral("images/lake.png"), QByteArrayLiteral("\x01\x02\x03")},
            {QStringLiteral("images/../../escape.png"), QByteArrayLiteral("\x04\x05\x06")},
            {QStringLiteral("images/nested/dir.png"), QByteArrayLiteral("\x07\x08\x09")},
        });
        const LuceArchive::Contents contents = LuceArchive::read(archive);
        QCOMPARE(contents.images.keys(),
                 QStringList{QStringLiteral("images/lake.png")});
    }

    void wrongFormatIsRejected() {
        REQUIRE_FIXTURE(data, "invalid/wrong-format.luce");
        try {
            LuceArchive::read(data);
            QFAIL("expected CodingError");
        } catch (const CodingError &error) {
            QCOMPARE(int(error.kind()), int(CodingError::Kind::WrongFormat));
        }
    }

    void tooNewFormatVersionIsRejected() {
        REQUIRE_FIXTURE(data, "invalid/format-too-new.luce");
        try {
            LuceArchive::read(data);
            QFAIL("expected CodingError");
        } catch (const CodingError &error) {
            QCOMPARE(int(error.kind()), int(CodingError::Kind::FormatTooNew));
        }
    }
};

QTEST_GUILESS_MAIN(tst_fixtures)
#include "tst_fixtures.moc"
