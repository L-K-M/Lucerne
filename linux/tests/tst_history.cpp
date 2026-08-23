// History pruning (C++) — mirrors Swift's IOSafetyTests history coverage:
// dedupe of identical prose, name-collision nudging, tiered retention, and the
// entry-name round-trip.

#include "core/History.h"

#include <QTimeZone>
#include <QtTest>

using namespace lucerne;

namespace {

QDateTime utc(int y, int mo, int d, int h = 12, int mi = 0, int s = 0) {
    return QDateTime(QDate(y, mo, d), QTime(h, mi, s), QTimeZone::utc());
}

} // namespace

class tst_history : public QObject {
    Q_OBJECT

private slots:
    void initTestCase() {
        // Pin a DST-observing zone so the spring-forward-gap regression below
        // is meaningful wherever the suite runs.
        qputenv("TZ", "Europe/Zurich");
    }

    void dstGapStampParsesAsUTC() {
        // 2026-03-29 02:30 UTC falls inside Europe/Zurich's spring-forward gap
        // when misparsed as LOCAL time; the parse must be timezone-independent
        // or this recovery snapshot silently vanishes on the next save.
        const QString name = QStringLiteral("history/20260329T023000Z.md");
        const QDateTime stamp = HistoryPruner::timestampFromEntryName(name);
        QVERIFY(stamp.isValid());
        QCOMPARE(stamp.toSecsSinceEpoch(),
                 QDateTime(QDate(2026, 3, 29), QTime(2, 30), QTimeZone::utc())
                     .toSecsSinceEpoch());
        QCOMPARE(HistoryPruner::entryName(stamp), name);
    }

    void entryNameRoundTrips() {
        const QDateTime stamp = utc(2026, 6, 9, 12, 0, 0);
        const QString name = HistoryPruner::entryName(stamp);
        QCOMPARE(name, QStringLiteral("history/20260609T120000Z.md"));
        QCOMPARE(HistoryPruner::timestampFromEntryName(name), stamp);
    }

    void invalidEntryNamesAreRejected() {
        QVERIFY(!HistoryPruner::timestampFromEntryName("history/nonsense.md").isValid());
        QVERIFY(!HistoryPruner::timestampFromEntryName("20260609T120000Z.md").isValid());
        QVERIFY(!HistoryPruner::timestampFromEntryName("history/20260609T120000Z.txt").isValid());
    }

    void identicalMarkdownIsNotDuplicated() {
        const QVector<HistorySnapshot> history = {{utc(2026, 1, 1), "same"}};
        const auto updated = HistoryPruner::updated(history, "same", utc(2026, 1, 2));
        QCOMPARE(updated.size(), 1);
    }

    void newMarkdownIsAppendedSortedOldestFirst() {
        const QVector<HistorySnapshot> history = {{utc(2026, 1, 1), "old"}};
        const auto updated = HistoryPruner::updated(history, "new", utc(2026, 1, 2));
        QCOMPARE(updated.size(), 2);
        QCOMPARE(updated.first().markdown, QStringLiteral("old"));
        QCOMPARE(updated.last().markdown, QStringLiteral("new"));
    }

    void sameSecondSaveGetsNudgedForward() {
        const QDateTime now = utc(2026, 1, 1);
        const QVector<HistorySnapshot> history = {{now, "old"}};
        const auto updated = HistoryPruner::updated(history, "new", now);
        QCOMPARE(updated.size(), 2);
        QCOMPARE(updated.last().timestamp, now.addSecs(1));
    }

    void recentSnapshotsAreAllKept() {
        QVector<HistorySnapshot> history;
        const QDateTime now = utc(2026, 6, 1);
        for (int i = 0; i < 10; ++i)
            history.append({now.addSecs(-60 * i), QStringLiteral("v%1").arg(i)});
        const auto updated = HistoryPruner::updated(history, "fresh", now);
        QCOMPARE(updated.size(), 11);   // 10 + the new one, all within "recent"
    }

    void agedSnapshotsThinToBuckets() {
        QVector<HistorySnapshot> history;
        const QDateTime now = utc(2026, 6, 1);
        // 50 snapshots, one per 10 minutes, starting 40 days back: outside the
        // recent-12 window they collapse into daily buckets.
        for (int i = 0; i < 50; ++i)
            history.append({now.addDays(-40).addSecs(600 * i), QStringLiteral("v%1").arg(i)});
        const auto updated = HistoryPruner::updated(history, "fresh", now);
        QVERIFY2(updated.size() < 20, qPrintable(QString::number(updated.size())));
    }
};

QTEST_GUILESS_MAIN(tst_history)
#include "tst_history.moc"
