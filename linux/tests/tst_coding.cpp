// Document JSON coding (C++) — mirrors Swift's SpecConformanceTests /
// FormatSafetyTests where they exercise the coding layer: spec-optional
// members really are optional, rejections happen for the right reasons, and
// the encoder is deterministic.

#include "core/Coding.h"
#include "testutil.h"

#include <QtTest>

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
