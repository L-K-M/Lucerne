#include "core/History.h"

#include <QSet>
#include <QTimeZone>

#include <algorithm>

namespace lucerne {
namespace HistoryPruner {

namespace {

const QString stampFormat = QStringLiteral("yyyyMMdd'T'HHmmss'Z'");

QString bucketKey(const QDateTime &timestamp, qint64 ageSeconds) {
    const qint64 t = timestamp.toSecsSinceEpoch();
    constexpr qint64 day = 86'400;
    if (ageSeconds < day) return QStringLiteral("h%1").arg(t / 3600);          // hourly, last day
    if (ageSeconds < 30 * day) return QStringLiteral("d%1").arg(t / day);      // daily, last month
    if (ageSeconds < 365 * day) return QStringLiteral("w%1").arg(t / (7 * day)); // weekly, last year
    return QStringLiteral("M%1").arg(t / (30 * day));                          // ~monthly beyond
}

/// The subset of timestamps to retain (newest-first tiers).
QSet<QDateTime> keep(QVector<QDateTime> timestamps, const QDateTime &now,
                     int recent = 12, int maxCount = 120) {
    std::sort(timestamps.begin(), timestamps.end(),
              [](const QDateTime &a, const QDateTime &b) { return a > b; });  // newest first
    QVector<QDateTime> kept;
    QSet<QString> seenBuckets;
    for (int index = 0; index < timestamps.size(); ++index) {
        const QDateTime &timestamp = timestamps[index];
        if (index < recent) {
            kept.append(timestamp);
            continue;
        }
        const QString bucket = bucketKey(timestamp, timestamp.secsTo(now));
        if (!seenBuckets.contains(bucket)) {
            seenBuckets.insert(bucket);
            kept.append(timestamp);
        }
    }
    if (kept.size() > maxCount) kept.resize(maxCount);
    return QSet<QDateTime>(kept.begin(), kept.end());
}

} // namespace

QVector<HistorySnapshot> updated(const QVector<HistorySnapshot> &history,
                                 const QString &markdown, const QDateTime &now) {
    QVector<HistorySnapshot> snapshots = history;
    const auto newest = std::max_element(snapshots.begin(), snapshots.end(),
        [](const HistorySnapshot &a, const HistorySnapshot &b) {
            return a.timestamp < b.timestamp;
        });
    if (newest == snapshots.end() || newest->markdown != markdown) {
        // Entry names have one-second granularity, so two saves in the same
        // second would collide into one ZIP entry name; nudge forward whole
        // seconds until the name is unique.
        QSet<QString> takenNames;
        for (const HistorySnapshot &s : snapshots) takenNames.insert(entryName(s.timestamp));
        QDateTime stamp = now.toUTC();
        while (takenNames.contains(entryName(stamp))) stamp = stamp.addSecs(1);
        snapshots.append({stamp, markdown});
    }
    const QSet<QDateTime> keepDates = keep([&] {
        QVector<QDateTime> stamps;
        for (const HistorySnapshot &s : snapshots) stamps.append(s.timestamp);
        return stamps;
    }(), now);
    QVector<HistorySnapshot> result;
    for (const HistorySnapshot &s : snapshots)
        if (keepDates.contains(s.timestamp)) result.append(s);
    std::sort(result.begin(), result.end(),
              [](const HistorySnapshot &a, const HistorySnapshot &b) {
                  return a.timestamp < b.timestamp;
              });
    return result;
}

QString entryName(const QDateTime &timestamp) {
    return directory() + timestamp.toUTC().toString(stampFormat) + QStringLiteral(".md");
}

QDateTime timestampFromEntryName(const QString &name) {
    if (!name.startsWith(directory()) || !name.endsWith(QLatin1String(".md")))
        return {};
    const QString stem = name.mid(directory().size(),
                                  name.size() - directory().size() - 3);
    QDateTime stamp = QDateTime::fromString(stem, stampFormat);
    if (!stamp.isValid()) return {};
    stamp.setTimeZone(QTimeZone::utc());
    return stamp;
}

} // namespace HistoryPruner
} // namespace lucerne
