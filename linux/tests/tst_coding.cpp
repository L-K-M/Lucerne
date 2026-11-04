// Document JSON coding (C++) — mirrors Swift's SpecConformanceTests /
// FormatSafetyTests where they exercise the coding layer: spec-optional
// members really are optional, rejections happen for the right reasons, and
// the encoder is deterministic.

#include "core/Coding.h"
#include "testutil.h"

#include <QtTest>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>

#include <limits>

using namespace lucerne;

namespace {

QByteArray minimalDocument() {
    return QByteArrayLiteral(R"({
      "format": "lucerne-document",
      "formatVersion": 1,
      "page": { "size": "A4", "width": 595.28, "height": 841.89,
                "margins": { "top": 72, "left": 72, "bottom": 72, "right": 72 } },
      "styles": { "body": { "name": "Body", "markdown": "p" } },
      "body": [
        { "id": "p1", "style": "body", "runs": [ { "text": "Hello, lake." } ] }
      ],
      "objects": [
        { "id": "img1", "src": "images/lake.png", "page": 0,
          "frame": { "x": 320, "y": 180, "width": 200, "height": 140 } }
      ]
    })");
}

} // namespace

class tst_coding : public QObject {
    Q_OBJECT

private slots:
    void minimalDocumentDecodesWithAppendixCDefaults() {
        const DocumentModel model = Coding::decode(minimalDocument());
        QCOMPARE(model.body.size(), 1);
        QCOMPARE(model.body.first().plainText(), QStringLiteral("Hello, lake."));

        const PlacedObject &obj = model.objects.first();
        QCOMPARE(obj.type, QStringLiteral("image"));            // default
        QCOMPARE(int(obj.anchorMode()), int(PlacedObject::Anchor::Page));
        QCOMPARE(obj.wrap, QStringLiteral("rectangular"));      // default
        QCOMPARE(obj.standoff, 12.0);                           // default
        QCOMPARE(obj.z, 0);                                     // default
    }

    void tabStopWithoutTypeDefaultsToLeft() {
        QByteArray json = minimalDocument();
        json.replace("\"style\": \"body\",",
                     "\"style\": \"body\", \"tabStops\": [ { \"pos\": 72 } ],");
        const DocumentModel model = Coding::decode(json);
        QVERIFY(model.body.first().tabStops.has_value());
        QCOMPARE(model.body.first().tabStops->first().type, QStringLiteral("left"));
    }

    void partialFooterDecodes() {
        QByteArray json = minimalDocument();
        json.replace("\"objects\":",
                     "\"footer\": { \"center\": \"Page {page}\" }, \"objects\":");
        const DocumentModel model = Coding::decode(json);
        QVERIFY(model.footer.has_value());
        QCOMPARE(model.footer->left, QString());
        QCOMPARE(model.footer->center, QStringLiteral("Page {page}"));
    }

    void emptyRunsArrayIsAccepted() {
        QByteArray json = minimalDocument();
        json.replace("[ { \"text\": \"Hello, lake.\" } ]", "[]");
        QCOMPARE(Coding::decode(json).body.first().runs.size(), 0);
    }

    void unknownMembersAreIgnoredEverywhere() {
        QByteArray json = minimalDocument();
        json.replace("\"formatVersion\": 1,", "\"formatVersion\": 1, \"mystery\": [1],");
        json.replace("\"name\": \"Body\",", "\"name\": \"Body\", \"glow\": true,");
        const DocumentModel model = Coding::decode(json);
        QCOMPARE(model.styles.value(QStringLiteral("body")).name, QStringLiteral("Body"));
    }

    void wrongFormatIsRejected() {
        QByteArray json = minimalDocument();
        json.replace("lucerne-document", "someone-elses");
        try {
            Coding::decode(json);
            QFAIL("expected CodingError");
        } catch (const CodingError &error) {
            QCOMPARE(int(error.kind()), int(CodingError::Kind::WrongFormat));
        }
    }

    void tooNewVersionIsRejected() {
        QByteArray json = minimalDocument();
        json.replace("\"formatVersion\": 1", "\"formatVersion\": 99");
        try {
            Coding::decode(json);
            QFAIL("expected CodingError");
        } catch (const CodingError &error) {
            QCOMPARE(int(error.kind()), int(CodingError::Kind::FormatTooNew));
        }
    }

    void invalidObjectPageIsRejected() {
        QByteArray json = minimalDocument();
        json.replace("\"page\": 0", "\"page\": 5000");
        try {
            Coding::decode(json);
            QFAIL("expected CodingError");
        } catch (const CodingError &error) {
            QCOMPARE(int(error.kind()), int(CodingError::Kind::InvalidObjectPage));
        }
    }

    void invalidListLevelIsRejected() {
        QByteArray json = minimalDocument();
        json.replace("\"style\": \"body\",",
                     "\"style\": \"body\", "
                     "\"list\": { \"list\": \"a\", \"ordered\": false, "
                     "\"marker\": \"disc\", \"level\": 40 },");
        try {
            Coding::decode(json);
            QFAIL("expected CodingError");
        } catch (const CodingError &error) {
            QCOMPARE(int(error.kind()), int(CodingError::Kind::InvalidListLevel));
        }
    }

    void unsafePageGeometryIsRejected_data() {
        QTest::addColumn<QString>("field");
        QTest::addColumn<double>("value");
        QTest::newRow("zero width") << QStringLiteral("width") << 0.0;
        QTest::newRow("negative width") << QStringLiteral("width") << -1.0;
        QTest::newRow("huge width") << QStringLiteral("width") << 1e100;
        QTest::newRow("width over cap") << QStringLiteral("width") << 100001.0;
        QTest::newRow("zero height") << QStringLiteral("height") << 0.0;
        QTest::newRow("huge height") << QStringLiteral("height") << 1e100;
        QTest::newRow("height over cap") << QStringLiteral("height") << 100001.0;
        QTest::newRow("negative margin") << QStringLiteral("left") << -1.0;
        QTest::newRow("horizontal margins") << QStringLiteral("left") << 600.0;
        QTest::newRow("vertical margins") << QStringLiteral("top") << 900.0;
        // left + right must be strictly less than width (same for top +
        // bottom vs height): sums equal to the dimension leave no text area.
        QTest::newRow("margin sum equals width") << QStringLiteral("width") << 144.0;
        QTest::newRow("margin sum equals height") << QStringLiteral("height") << 144.0;
    }

    void unsafePageGeometryIsRejected() {
        QFETCH(QString, field);
        QFETCH(double, value);
        auto root = QJsonDocument::fromJson(minimalDocument()).object();
        auto page = root.value(QStringLiteral("page")).toObject();
        if (field == QLatin1String("width") || field == QLatin1String("height")) {
            page.insert(field, value);
        } else {
            auto margins = page.value(QStringLiteral("margins")).toObject();
            margins.insert(field, value);
            page.insert(QStringLiteral("margins"), margins);
        }
        root.insert(QStringLiteral("page"), page);
        EXPECT_THROW(Coding::decode(QJsonDocument(root).toJson()), CodingError);
    }

    void unsafeObjectGeometryIsRejected_data() {
        QTest::addColumn<QString>("field");
        QTest::addColumn<double>("value");
        QTest::newRow("negative width") << QStringLiteral("width") << -1.0;
        QTest::newRow("negative height") << QStringLiteral("height") << -1.0;
        QTest::newRow("huge width") << QStringLiteral("width") << 1e100;
        QTest::newRow("huge x") << QStringLiteral("x") << 1e100;
        QTest::newRow("negative standoff") << QStringLiteral("standoff") << -1.0;
        QTest::newRow("huge standoff") << QStringLiteral("standoff") << 1e100;
    }

    void unsafeObjectGeometryIsRejected() {
        QFETCH(QString, field);
        QFETCH(double, value);
        auto root = QJsonDocument::fromJson(minimalDocument()).object();
        auto objects = root.value(QStringLiteral("objects")).toArray();
        auto object = objects[0].toObject();
        if (field == QLatin1String("standoff")) {
            object.insert(field, value);
        } else {
            auto frame = object.value(QStringLiteral("frame")).toObject();
            frame.insert(field, value);
            object.insert(QStringLiteral("frame"), frame);
        }
        objects[0] = object;
        root.insert(QStringLiteral("objects"), objects);
        EXPECT_THROW(Coding::decode(QJsonDocument(root).toJson()), CodingError);
    }

    void paragraphAnchoredObjectGeometryIsRejected() {
        // Validation is anchor-agnostic: a paragraph-anchored object reaches
        // the same layout machinery, so its frame and standoff face the same
        // bounds as a page-anchored one.
        const auto jsonWith = [](const QString &field, double value) {
            auto root = QJsonDocument::fromJson(minimalDocument()).object();
            auto objects = root.value(QStringLiteral("objects")).toArray();
            auto object = objects[0].toObject();
            object.insert(QStringLiteral("anchor"), QStringLiteral("paragraph"));
            object.insert(QStringLiteral("anchorParagraph"), QStringLiteral("p1"));
            if (field == QLatin1String("standoff")) {
                object.insert(field, value);
            } else {
                auto frame = object.value(QStringLiteral("frame")).toObject();
                frame.insert(field, value);
                object.insert(QStringLiteral("frame"), frame);
            }
            objects[0] = object;
            root.insert(QStringLiteral("objects"), objects);
            return QJsonDocument(root).toJson();
        };
        EXPECT_THROW(Coding::decode(jsonWith(QStringLiteral("width"), -1.0)),
                     CodingError);
        EXPECT_THROW(Coding::decode(jsonWith(QStringLiteral("width"), 1e100)),
                     CodingError);
        EXPECT_THROW(Coding::decode(jsonWith(QStringLiteral("x"), 1e100)),
                     CodingError);
        EXPECT_THROW(Coding::decode(jsonWith(QStringLiteral("standoff"), -1.0)),
                     CodingError);
    }

    void zeroSizedObjectFramesDecode() {
        // An empty extent is valid: only negative (or non-finite / over-cap)
        // geometry is unsafe, matching the reference decoder.
        auto root = QJsonDocument::fromJson(minimalDocument()).object();
        auto objects = root.value(QStringLiteral("objects")).toArray();
        auto object = objects[0].toObject();
        auto frame = object.value(QStringLiteral("frame")).toObject();
        for (const QSizeF size : {QSizeF(0, 0), QSizeF(0, 140), QSizeF(200, 0)}) {
            frame.insert(QStringLiteral("width"), size.width());
            frame.insert(QStringLiteral("height"), size.height());
            object.insert(QStringLiteral("frame"), frame);
            objects[0] = object;
            root.insert(QStringLiteral("objects"), objects);
            const auto model = Coding::decode(QJsonDocument(root).toJson());
            QCOMPARE(model.objects[0].frame->width, size.width());
            QCOMPARE(model.objects[0].frame->height, size.height());
        }
    }

    void marginsJustUnderThePageDecode() {
        // The bound is a strict less-than on the margin sums, not "more than
        // one point of text area": 72+72 = 144 < 144.5 is a valid page.
        auto root = QJsonDocument::fromJson(minimalDocument()).object();
        auto page = root.value(QStringLiteral("page")).toObject();
        page.insert(QStringLiteral("width"), 144.5);
        page.insert(QStringLiteral("height"), 144.5);
        root.insert(QStringLiteral("page"), page);
        const auto model = Coding::decode(QJsonDocument(root).toJson());
        QCOMPARE(model.page.width, 144.5);
    }

    void unsafeTableCellGeometryIsRejected_data() {
        QTest::addColumn<int>("row");
        QTest::addColumn<int>("column");
        QTest::addColumn<int>("rowSpan");
        QTest::addColumn<int>("columnSpan");
        QTest::newRow("negative row") << -1 << 0 << 1 << 1;
        QTest::newRow("negative column") << 0 << -1 << 1 << 1;
        QTest::newRow("zero rowSpan") << 0 << 0 << 0 << 1;
        QTest::newRow("zero columnSpan") << 0 << 0 << 1 << 0;
        QTest::newRow("row at extent") << 1000 << 0 << 1 << 1;
        QTest::newRow("column at extent") << 0 << 1000 << 1 << 1;
        QTest::newRow("row extent over") << 999 << 0 << 2 << 1;
        QTest::newRow("column extent over") << 0 << 999 << 1 << 2;
        // int-sized inputs, but the sums are computed in a wider type:
        // INT_MAX + span must reject, never wrap.
        QTest::newRow("overflowing row") << std::numeric_limits<int>::max() << 0 << 1 << 1;
        QTest::newRow("overflowing column") << 0 << std::numeric_limits<int>::max() << 1 << 1;
    }

    void unsafeTableCellGeometryIsRejected() {
        QFETCH(int, row);
        QFETCH(int, column);
        QFETCH(int, rowSpan);
        QFETCH(int, columnSpan);
        auto root = QJsonDocument::fromJson(minimalDocument()).object();
        auto body = root.value(QStringLiteral("body")).toArray();
        auto paragraph = body[0].toObject();
        QJsonObject cell;
        cell.insert(QStringLiteral("table"), QStringLiteral("t"));
        cell.insert(QStringLiteral("row"), row);
        cell.insert(QStringLiteral("column"), column);
        cell.insert(QStringLiteral("rowSpan"), rowSpan);
        cell.insert(QStringLiteral("columnSpan"), columnSpan);
        paragraph.insert(QStringLiteral("cell"), cell);
        body[0] = paragraph;
        root.insert(QStringLiteral("body"), body);
        try {
            Coding::decode(QJsonDocument(root).toJson());
            QFAIL("expected CodingError");
        } catch (const CodingError &error) {
            QCOMPARE(int(error.kind()), int(CodingError::Kind::InvalidTableCell));
            QVERIFY2(error.message().contains(QLatin1String("p1")),
                     qPrintable(error.message()));
            QVERIFY2(error.message().contains(QLatin1String("1000")),
                     qPrintable(error.message()));
        }
    }

    void tableCellAtTheGridBoundaryDecodes() {
        // row + rowSpan == 1000 and column + columnSpan == 1000 sit exactly at
        // the grid bound and are valid; only sums above it (or a coordinate
        // reaching it) fail.
        auto root = QJsonDocument::fromJson(minimalDocument()).object();
        auto body = root.value(QStringLiteral("body")).toArray();
        auto paragraph = body[0].toObject();
        QJsonObject cell;
        cell.insert(QStringLiteral("table"), QStringLiteral("t"));
        cell.insert(QStringLiteral("row"), 999);
        cell.insert(QStringLiteral("column"), 999);
        cell.insert(QStringLiteral("rowSpan"), 1);
        cell.insert(QStringLiteral("columnSpan"), 1);
        paragraph.insert(QStringLiteral("cell"), cell);
        body[0] = paragraph;
        root.insert(QStringLiteral("body"), body);
        const auto model = Coding::decode(QJsonDocument(root).toJson());
        QVERIFY(model.body[0].cell.has_value());
        QCOMPARE(model.body[0].cell->row, 999);
    }

    void largePagesAndImageOverhangRemainSupported() {
        auto root = QJsonDocument::fromJson(minimalDocument()).object();
        auto page = root.value(QStringLiteral("page")).toObject();
        page.insert(QStringLiteral("width"), 100000);
        page.insert(QStringLiteral("height"), 100000);
        root.insert(QStringLiteral("page"), page);

        auto objects = root.value(QStringLiteral("objects")).toArray();
        auto object = objects[0].toObject();
        auto frame = object.value(QStringLiteral("frame")).toObject();
        frame.insert(QStringLiteral("x"), -20);
        frame.insert(QStringLiteral("y"), -10);
        object.insert(QStringLiteral("frame"), frame);
        objects[0] = object;
        root.insert(QStringLiteral("objects"), objects);

        const auto model = Coding::decode(QJsonDocument(root).toJson());
        QCOMPARE(model.page.width, 100000.0);
        QCOMPARE(model.objects[0].frame->x, -20.0);
        QCOMPARE(Coding::decode(Coding::encode(model)), model);
    }

    void missingRequiredMemberIsMalformed() {
        QByteArray json = minimalDocument();
        json.replace("\"id\": \"p1\", ", "");
        EXPECT_THROW(Coding::decode(json), CodingError);
    }

    void wrongTypedOptionalIsMalformed() {
        QByteArray json = minimalDocument();
        json.replace("\"src\": \"images/lake.png\"", "\"src\": 7");
        EXPECT_THROW(Coding::decode(json), CodingError);
    }

    void encodeIsDeterministicAndRoundTrips() {
        const DocumentModel model = Coding::decode(minimalDocument());
        const QByteArray first = Coding::encode(model);
        QCOMPARE(Coding::encode(model), first);
        QCOMPARE(Coding::decode(first), model);
    }

    void encodeWritesIntegralNumbersWithoutFraction() {
        const DocumentModel model = Coding::decode(minimalDocument());
        const QByteArray out = Coding::encode(model);
        QVERIFY2(out.contains("\"top\" : 72"), out.constData());
        QVERIFY2(out.contains("\"width\" : 595.28"), out.constData());
        QVERIFY2(!out.contains("72.0"), out.constData());
    }

    void encodeSortsKeys() {
        const DocumentModel model = Coding::decode(minimalDocument());
        const QByteArray out = Coding::encode(model);
        // "body" < "format" < "formatVersion" < "objects" < "page" < "styles"
        QVERIFY(out.indexOf("\"body\"") < out.indexOf("\"format\""));
        QVERIFY(out.indexOf("\"format\"") < out.indexOf("\"objects\""));
        QVERIFY(out.indexOf("\"objects\"") < out.indexOf("\"page\""));
    }

    void emptyContainersKeepTheReferenceEncodersShape() {
        // Swift's JSONEncoder(.prettyPrinted) writes an empty array/object as
        // an open bracket, a BLANK line, then the close at the parent indent.
        // Emitting "[]" instead shifts every later byte of document.json, so a
        // no-op resave on Linux would rewrite a Mac-written file (and vice
        // versa) — the one thing that broke byte-identical cross-app saves.
        DocumentModel model = Coding::decode(minimalDocument());
        model.objects.clear();   // every document without a placed image
        const QByteArray out = Coding::encode(model);
        QVERIFY2(out.contains("\"objects\" : [\n\n  ]"), out.constData());
        QVERIFY2(!out.contains("[]"), out.constData());
        QVERIFY2(!out.contains("{}"), out.constData());
        // Nested containers close at their OWN depth, not the root's.
        Paragraph empty;
        empty.id = QStringLiteral("pEmpty");
        empty.style = QStringLiteral("body");
        model.body = {empty};
        const QByteArray nested = Coding::encode(model);
        QVERIFY2(nested.contains("\"runs\" : [\n\n      ]"), nested.constData());
    }

    void slashesAreNotEscaped() {
        const DocumentModel model = Coding::decode(minimalDocument());
        QVERIFY(Coding::encode(model).contains("images/lake.png"));
    }

    void nonBMPTextSurvivesEncoding() {
        // Non-BMP characters (emoji, mathematical alphanumerics) are surrogate
        // PAIRS in QString; encoding them one QChar at a time would destroy
        // them. The bytes below are U+1F3D4 (mountain) and U+1D4BB (script h).
        const QString fancy = QString::fromUtf8("Gr\xC3\xBC\xC3\x9F" "e vom See "
                                                "\xF0\x9F\x8F\x94 \xF0\x9D\x92\xBB");
        DocumentModel model = Coding::decode(minimalDocument());
        model.body[0].runs[0].text = fancy;
        const QByteArray out = Coding::encode(model);
        QVERIFY2(out.contains("\xF0\x9F\x8F\x94"), out.constData());
        QVERIFY2(!out.contains('?'), out.constData());
        const DocumentModel back = Coding::decode(out);
        QCOMPARE(back.body[0].runs[0].text, fancy);
    }

    void formatVersionBeyondIntRangeIsStillRejected() {
        // QJsonValue::toInt returns 0 for out-of-int-range numbers - the
        // too-new check must not be bypassable that way (spec 9 MUST), and the
        // message must name the real version, not a toInt-collapsed 0.
        QByteArray json = minimalDocument();
        json.replace("\"formatVersion\": 1", "\"formatVersion\": 10000000000");
        try {
            Coding::decode(json);
            QFAIL("expected CodingError");
        } catch (const CodingError &error) {
            QCOMPARE(int(error.kind()), int(CodingError::Kind::FormatTooNew));
            QVERIFY2(error.message().contains(QLatin1String("10000000000")),
                     qPrintable(error.message()));
        }
    }

    void nonFiniteNumbersRefuseToEncode() {
        // JSON cannot represent NaN/Infinity; the Swift reference encoder
        // throws, and writing "nan" would produce a file our own decoder
        // rejects - the save must fail loudly instead.
        DocumentModel model = Coding::decode(minimalDocument());
        model.page.width = std::numeric_limits<double>::quiet_NaN();
        EXPECT_THROW(Coding::encode(model), CodingError);
        model.page.width = std::numeric_limits<double>::infinity();
        EXPECT_THROW(Coding::encode(model), CodingError);
    }

    void outOfRangeIntegerFieldIsMalformed() {
        QByteArray json = minimalDocument();
        json.replace("\"page\": 0", "\"page\": 99999999999");
        EXPECT_THROW(Coding::decode(json), CodingError);
    }
};

QTEST_GUILESS_MAIN(tst_coding)
#include "tst_coding.moc"
