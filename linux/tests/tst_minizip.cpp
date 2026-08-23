// MiniZip (C++) — mirrors the intent of Swift's MiniZipHardeningTests plus the
// DEFLATE fixture from MiniZipDeflateReadTests, so both implementations enforce
// the same container behavior.

#include "core/MiniZip.h"
#include "testutil.h"

#include <QtTest>

using namespace lucerne;

class tst_minizip : public QObject {
    Q_OBJECT

    // Same externally-built fixture as the Swift test: one entry
    // "deflated.txt", 268 bytes of text deflated to 72.
    static QByteArray deflateFixture() {
        return QByteArray::fromBase64(
            "UEsDBBQAAAgIAAAAIQD6e05fSAAAAAwBAAAMAAAAZGVmbGF0ZWQudHh080jNyclXSCvKz1VIVHBx"
            "dfNxDHHVTc7PLShKLS5OTVFIzSspqlTIzCvOTEkFqtDLKU1OVShJLS5RSMusKCktStVT8BguRgAA"
            "UEsBAhQAFAAACAgAAAAhAPp7Tl9IAAAADAEAAAwAAAAAAAAAAAAAAAAAAAAAAGRlZmxhdGVkLnR4"
            "dFBLBQYAAAAAAQABADoAAAByAAAAAAA=");
    }

private slots:
    void storedRoundTrip() {
        const QVector<MiniZip::Entry> entries = {
            {QStringLiteral("document.json"), QByteArrayLiteral("{}")},
            {QStringLiteral("images/Zürich.png"), QByteArrayLiteral("\x89PNG rest")},
        };
        const QByteArray archive = MiniZip::archive(entries);
        const auto read = MiniZip::entries(archive);
        QCOMPARE(read, entries);
    }

    void writerIsDeterministic() {
        const QVector<MiniZip::Entry> entries = {
            {QStringLiteral("a.txt"), QByteArrayLiteral("alpha")},
            {QStringLiteral("b.txt"), QByteArrayLiteral("beta")},
        };
        QCOMPARE(MiniZip::archive(entries), MiniZip::archive(entries));
    }

    void utf8NameFlagIsSet() {
        const QByteArray archive =
            MiniZip::archive({{QStringLiteral("images/Zürich.png"), "x"}});
        // General-purpose flag of the local header sits at offset 6.
        const quint16 flag = quint8(archive[6]) | (quint16(quint8(archive[7])) << 8);
        QVERIFY2(flag & 0x0800, "the UTF-8 (EFS) name flag must be set");
    }

    void corruptPayloadIsRejected() {
        QByteArray archive = MiniZip::archive({{QStringLiteral("a.txt"), "hello world"}});
        const int payloadAt = 30 + int(strlen("a.txt"));
        archive[payloadAt] = archive[payloadAt] ^ 0x55;   // flip bits inside "hello"
        EXPECT_THROW(MiniZip::entries(archive), MiniZip::ZipError);
    }

    void corruptDroppableEntryIsSkipped() {
        QByteArray archive = MiniZip::archive({
            {QStringLiteral("document.json"), QByteArrayLiteral("{\"k\":1}")},
            {QStringLiteral("history/x.md"), QByteArrayLiteral("old prose")},
        });
        // Find and corrupt the history payload only.
        const int at = int(archive.indexOf("old prose"));
        QVERIFY(at > 0);
        archive[at] = 'X';
        const auto entries = MiniZip::entries(archive, [](const QString &name) {
            return name.startsWith(QLatin1String("history/"));
        });
        QCOMPARE(entries.size(), 1);
        QCOMPARE(entries.first().name, QStringLiteral("document.json"));
    }

    void notAZipIsRejected() {
        EXPECT_THROW(MiniZip::entries(QByteArrayLiteral("plain text")), MiniZip::ZipError);
    }

    void zip64SentinelIsRejectedAsUnsupported() {
        QByteArray archive = MiniZip::archive({{QStringLiteral("a.txt"), "x"}});
        // EOCD total-entries field (offset eocd+10) → 0xFFFF sentinel.
        const int eocd = int(archive.size()) - 22;
        archive[eocd + 10] = char(0xff);
        archive[eocd + 11] = char(0xff);
        try {
            MiniZip::entries(archive);
            QFAIL("expected ZipError");
        } catch (const MiniZip::ZipError &error) {
            QCOMPARE(int(error.kind()), int(MiniZip::ZipError::Kind::Unsupported));
        }
    }

    void deflatedEntryInflatesAndPassesCRC() {
        const auto entries = MiniZip::entries(deflateFixture());
        QCOMPARE(entries.size(), 1);
        QCOMPARE(entries.first().name, QStringLiteral("deflated.txt"));
        const QByteArray expected =
            QByteArrayLiteral("Hello from a DEFLATE-compressed entry inside a .luce "
                              "test fixture. ").repeated(4);
        QCOMPARE(entries.first().data, expected);
    }

    void truncatedDeflateStreamFailsCleanly() {
        QByteArray corrupt = deflateFixture();
        corrupt.remove(50, 10);   // bytes out of the middle of the payload
        EXPECT_THROW(MiniZip::entries(corrupt), MiniZip::ZipError);
    }
};

QTEST_GUILESS_MAIN(tst_minizip)
#include "tst_minizip.moc"
