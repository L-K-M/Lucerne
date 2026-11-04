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

    // Overwrite every central directory's declared uncompressed size field
    // (offset 24) — the numbers the aggregate budget sums — without touching
    // the real payloads.
    static void patchDeclaredUncompressedSizes(QByteArray &archive, quint32 declared) {
        const QByteArray signature("PK\x01\x02", 4);
        for (qsizetype at = archive.indexOf(signature); at >= 0;
             at = archive.indexOf(signature, at + 4)) {
            for (int i = 0; i < 4; ++i)
                archive[at + 24 + i] = char((declared >> (8 * i)) & 0xff);
        }
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

    void oversizedOptionalDeclarationsAreDropped_data() {
        QTest::addColumn<QString>("name");
        QTest::addColumn<int>("sizeOffset");
        QTest::newRow("history compressed") << QStringLiteral("history/old.md") << 20;
        QTest::newRow("history expanded") << QStringLiteral("history/old.md") << 24;
        QTest::newRow("markdown compressed") << QStringLiteral("content.md") << 20;
        QTest::newRow("markdown expanded") << QStringLiteral("content.md") << 24;
    }

    void oversizedOptionalDeclarationsAreDropped() {
        QFETCH(QString, name);
        QFETCH(int, sizeOffset);
        QByteArray archive = MiniZip::archive({{"document.json", "{}"}, {name, "old"}});
        const qsizetype central = archive.lastIndexOf(QByteArray("PK\x01\x02", 4));
        QVERIFY(central > 0);
        const quint32 invalidSize = quint32(MiniZip::maxEntrySize) + 1;
        for (int i = 0; i < 4; ++i)
            archive[central + sizeOffset + i] = char((invalidSize >> (8 * i)) & 0xff);

        EXPECT_THROW(MiniZip::entries(archive), MiniZip::ZipError);
        try {
            const auto recovered = MiniZip::entries(archive,
                [&](const QString &candidate) { return candidate == name; });
            QCOMPARE(recovered, (QVector<MiniZip::Entry>{{"document.json", "{}"}}));
        } catch (const MiniZip::ZipError &error) {
            QFAIL(qPrintable(error.message()));
        }
    }

    void duplicateNamesAreRejectedByWriter() {
        EXPECT_THROW(MiniZip::archive({{"document.json", "first"},
                                       {"document.json", "second"}}), MiniZip::ZipError);
    }

    void duplicateNamesAreRejectedByReader() {
        QByteArray archive = MiniZip::archive({{"a.txt", "first"}, {"b.txt", "second"}});
        archive.replace("b.txt", "a.txt");
        EXPECT_THROW(MiniZip::entries(archive), MiniZip::ZipError);
    }

    void aggregateDeclaredSizesAreCheckedBeforeExtraction() {
        QByteArray archive = MiniZip::archive({{"a.txt", "a"}, {"b.txt", "b"}});
        // Each declaration exceeds the 512 MiB per-entry cap (so every entry is
        // droppable-skippable), yet the declared sizes still sum into the 2 GiB
        // aggregate budget: 2 × (1 GiB + 1) > 2 GiB.
        patchDeclaredUncompressedSizes(archive, 0x40000001);
        try {
            MiniZip::entries(archive, [](const QString &) { return true; });
            QFAIL("aggregate extraction budget was not enforced");
        } catch (const MiniZip::ZipError &error) {
            QVERIFY2(error.message().contains(QStringLiteral("aggregate")),
                     qPrintable(error.message()));
        }
    }

    void aggregateBudgetAtTheLimitIsAccepted() {
        // 4 × exactly 512 MiB declared sums to exactly the 2 GiB budget — the
        // envelope must accept it. The stored-size mismatch it leaves behind
        // (a real payload of 1 byte) then fails strict extraction, which the
        // all-droppable read skips — proving the budget itself did not fire.
        QByteArray archive = MiniZip::archive({
            {"a.txt", "x"}, {"b.txt", "x"}, {"c.txt", "x"}, {"d.txt", "x"}});
        patchDeclaredUncompressedSizes(archive, quint32(MiniZip::maxEntrySize));
        const auto read = MiniZip::entries(archive, [](const QString &) { return true; });
        QCOMPARE(read.size(), 0);
        try {
            MiniZip::entries(archive);
            QFAIL("expected a downstream extraction failure");
        } catch (const MiniZip::ZipError &error) {
            QVERIFY2(!error.message().contains(QStringLiteral("aggregate")),
                     qPrintable(error.message()));
        }
    }

    void aggregateJustOverTheLimitIsRejected() {
        // One byte over the budget anywhere in the directory fails the read,
        // even when every name is droppable — droppable relaxes payload
        // damage, never the size envelope.
        QByteArray archive = MiniZip::archive({
            {"a.txt", "x"}, {"b.txt", "x"}, {"c.txt", "x"}, {"d.txt", "x"}});
        patchDeclaredUncompressedSizes(archive, quint32(MiniZip::maxEntrySize) + 1);
        try {
            MiniZip::entries(archive, [](const QString &) { return true; });
            QFAIL("aggregate budget was not enforced");
        } catch (const MiniZip::ZipError &error) {
            QVERIFY2(error.message().contains(QStringLiteral("aggregate")),
                     qPrintable(error.message()));
        }
    }

    void entryCountIsBoundedOnWriteAndRead() {
        constexpr int entryBudget = 4096;
        QVector<MiniZip::Entry> entries;
        for (int i = 0; i <= entryBudget; ++i)
            entries.append({QString::number(i), {}});
        EXPECT_THROW(MiniZip::archive(entries), MiniZip::ZipError);

        QByteArray archive = MiniZip::archive({{"a.txt", "x"}});
        const qsizetype eocd = archive.size() - 22;
        for (const int offset : {8, 10}) {
            archive[eocd + offset] = char(1);
            archive[eocd + offset + 1] = char(0x10);
        }
        try {
            MiniZip::entries(archive);
            QFAIL("entry count was not bounded");
        } catch (const MiniZip::ZipError &error) {
            QVERIFY2(error.message().contains(QStringLiteral("entry count")),
                     qPrintable(error.message()));
        }
    }

    void writerChecksAggregateBeforeAllocatingOutput() {
        const QByteArray sharedPayload(1024 * 1024, 'x');
        QVector<MiniZip::Entry> entries;
        const int count = int(MiniZip::maxTotalUncompressedSize / sharedPayload.size()) + 1;
        for (int i = 0; i < count; ++i)
            entries.append({QString::number(i), sharedPayload});
        EXPECT_THROW(MiniZip::archive(entries), MiniZip::ZipError);
    }

    void entryCountAtTheLimitRoundTrips() {
        QVector<MiniZip::Entry> entries;
        for (int i = 0; i < MiniZip::maxEntryCount; ++i)
            entries.append({QString::number(i), {}});
        QCOMPARE(MiniZip::entries(MiniZip::archive(entries)), entries);
    }

    void storedSizeMismatchIsRejected() {
        QByteArray archive = MiniZip::archive({{"a.txt", "x"}});
        const qsizetype central = archive.indexOf(QByteArray("PK\x01\x02", 4));
        archive[central + 24] = char(2);
        EXPECT_THROW(MiniZip::entries(archive), MiniZip::ZipError);
    }

    void encryptedEntryIsRejected() {
        QByteArray archive = MiniZip::archive({{"a.txt", "x"}});
        const qsizetype central = archive.indexOf(QByteArray("PK\x01\x02", 4));
        archive[6] = char(1);
        archive[central + 8] = char(1);
        EXPECT_THROW(MiniZip::entries(archive), MiniZip::ZipError);
    }

    void localNameMustMatchDirectoryName() {
        QByteArray archive = MiniZip::archive({{"a.txt", "x"}});
        archive[30] = 'b';
        EXPECT_THROW(MiniZip::entries(archive), MiniZip::ZipError);
    }

    void directorySizeMustMatchItsRecords() {
        QByteArray archive = MiniZip::archive({{"a.txt", "x"}});
        const qsizetype eocd = archive.size() - 22;
        archive[eocd + 12] = char(quint8(archive[eocd + 12]) + 1);
        EXPECT_THROW(MiniZip::entries(archive), MiniZip::ZipError);
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
        // be rejected by the size sanity checks, never allocated. Two distinct
        // guards: 0xFFFFFFFF alone already exceeds the 2 GiB aggregate budget,
        // and 0x30000000 (768 MiB) stays under it but over the 512 MiB entry cap.
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
