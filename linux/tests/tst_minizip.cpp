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
        // The central directory carries its own flag word (offset 8) and is
        // what most third-party readers consult for name encoding.
        const int central = int(archive.indexOf(QByteArrayLiteral("PK\x01\x02")));
        QVERIFY(central > 0);
        const quint16 centralFlag = quint8(archive[central + 8])
            | (quint16(quint8(archive[central + 9])) << 8);
        QVERIFY2(centralFlag & 0x0800, "EFS must also be set in the central directory");
    }

    void corruptPayloadIsRejected() {
        QByteArray archive = MiniZip::archive({{QStringLiteral("a.txt"), "hello world"}});
        // Stored payloads appear verbatim exactly once (the central directory
        // holds metadata only), so locate it instead of hardcoding the 30-byte
        // local-header layout.
        const int payloadAt = int(archive.indexOf("hello world"));
        QVERIFY(payloadAt > 0);
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

    void zip64CentralDirectoryOffsetSentinelIsRejected() {
        // The OTHER ZIP64 sentinel (the Swift suite's IOSafetyTests case (c)):
        // a 0xFFFFFFFF central-directory offset must report Unsupported, not
        // get chased as a real offset.
        QByteArray archive = MiniZip::archive({{QStringLiteral("a.txt"), "x"}});
        const int eocd = int(archive.size()) - 22;
        for (int i = 16; i < 20; ++i) archive[eocd + i] = char(0xff);
        try {
            MiniZip::entries(archive);
            QFAIL("expected ZipError");
        } catch (const MiniZip::ZipError &error) {
            QCOMPARE(int(error.kind()), int(MiniZip::ZipError::Kind::Unsupported));
        }
    }

    void hugeDeclaredSizeIsRejectedNotAllocated() {
        // Mirrors Swift's MiniZipHardeningTests: hostile declared sizes must
        // be rejected by the size sanity check, never allocated. Two distinct
        // branches: 0xFFFFFFFF wraps negative through int(), and 0x30000000
        // (768 MiB) stays positive but exceeds the 512 MiB entry cap.
        const QByteArray original = MiniZip::archive({{QStringLiteral("a.txt"), "x"}});
        const int central = int(original.indexOf(QByteArrayLiteral("PK\x01\x02")));
        QVERIFY(central > 0);

        QByteArray negative = original;
        for (int i = 24; i < 28; ++i) negative[central + i] = char(0xff);
        EXPECT_THROW(MiniZip::entries(negative), MiniZip::ZipError);

        QByteArray overCap = original;
        for (int i = 24; i < 27; ++i) overCap[central + i] = char(0x00);
        overCap[central + 27] = char(0x30);
        EXPECT_THROW(MiniZip::entries(overCap), MiniZip::ZipError);
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

    void corruptDeflateStreamFailsCleanly() {
        // Flip a byte INSIDE the compressed payload (data starts at 42 =
        // 30-byte header + 12-byte name): every record length stays valid and
        // the central directory stays reachable, so only the inflate/CRC path
        // can throw. (Removing bytes instead would desync the EOCD's central-
        // directory offset and fail before inflate ever ran.)
        QByteArray corrupt = deflateFixture();
        corrupt[60] = char(quint8(corrupt[60]) ^ 0xFF);
        EXPECT_THROW(MiniZip::entries(corrupt), MiniZip::ZipError);
    }
};

QTEST_GUILESS_MAIN(tst_minizip)
#include "tst_minizip.moc"
