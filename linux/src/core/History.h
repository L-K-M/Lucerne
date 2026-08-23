#pragma once

// Dated Markdown snapshots stored under history/ in the .luce package — the C++
// mirror of Swift LucerneCore's DocumentHistory.swift. A safety net: deleted
// prose stays recoverable by unzipping the file.

#include <QByteArray>
#include <QDateTime>
#include <QString>
#include <QVector>

#include <functional>

namespace lucerne {

struct HistorySnapshot {
    QDateTime timestamp;   // UTC
    QString markdown;

    friend bool operator==(const HistorySnapshot &a, const HistorySnapshot &b) {
        return a.timestamp == b.timestamp && a.markdown == b.markdown;
    }
};

// Decides which snapshots to keep: dense for recent edits, thinning with age —
// the most recent N always, then hourly for a day, daily for a month, weekly
// for a year, ~monthly beyond, capped to a maximum.
namespace HistoryPruner {

/// Adds the current Markdown as a new snapshot (unless identical to the most
/// recent) and prunes. Returns snapshots sorted oldest→newest.
QVector<HistorySnapshot> updated(const QVector<HistorySnapshot> &history,
                                 const QString &markdown, const QDateTime &now);

inline QString directory() { return QStringLiteral("history/"); }
QString entryName(const QDateTime &timestamp);
/// Parses "history/<yyyyMMdd'T'HHmmss'Z'>.md"; invalid → null QDateTime.
QDateTime timestampFromEntryName(const QString &name);

} // namespace HistoryPruner

} // namespace lucerne
