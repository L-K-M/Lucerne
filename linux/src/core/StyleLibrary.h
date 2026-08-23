#pragma once

// The app-global style library — the C++ mirror of Swift LucerneCore's
// StyleLibrary.swift: a plain JSON file in the same dialect as a document's
// `styles` block ({"format":"lucerne-styles","formatVersion":1,"styles":{…}}),
// used only to seed new documents and for explicit import/export (copy-on-use;
// documents never reference it). On Linux it lives in XDG data
// (~/.local/share/Lucerne/styles.json). Missing or corrupt files degrade to
// "no library"; a file that exists but won't load is never overwritten.

#include "core/Model.h"

#include <QByteArray>
#include <QDateTime>
#include <QObject>
#include <QString>

namespace lucerne {

class StyleLibrary : public QObject {
    Q_OBJECT
public:
    static QString canonicalFormat() { return QStringLiteral("lucerne-styles"); }
    static int currentFormatVersion() { return 1; }

    /// Default path (XDG data dir); injectable for tests.
    explicit StyleLibrary(const QString &filePath = QString(), QObject *parent = nullptr);

    static StyleLibrary *shared();

    QString filePath() const { return m_filePath; }

    enum class LoadFailure { None, Unreadable, Undecodable };
    LoadFailure loadFailure() const { return m_loadFailure; }

    /// The library's styles. A missing file is an empty library; a file that
    /// exists but won't load is reported empty AND flips loadFailure so writes
    /// refuse rather than clobber it.
    QMap<QString, ParagraphStyle> load();

    /// Rewrites the library file atomically and emits changed(). Refuses while
    /// the last load failed on an existing file.
    void save(const QMap<QString, ParagraphStyle> &styles);

    /// Adds or updates one style, keeping the library's existing `order` for
    /// the key (a brand-new entry goes to the end).
    void saveStyle(const ParagraphStyle &def, const QString &key);
    void removeStyle(const QString &key);

    /// Seeds a brand-new library (no file on disk) with the starter collection.
    void seedStarterLibraryIfNeeded();

    /// The stylesheet a new document starts with — exactly the library, with
    /// two guard rails: empty/missing falls back to `base`, and a library
    /// without `body` has it materialized (body is the format's fallback anchor).
    QMap<QString, ParagraphStyle> seededStyles(
        const QMap<QString, ParagraphStyle> &base) ;
    QMap<QString, ParagraphStyle> seededStyles();

    // Interchange (Import / Export Stylesheet…) — throws CodingError on bad input.
    static QByteArray encode(const QMap<QString, ParagraphStyle> &styles);
    static QMap<QString, ParagraphStyle> decode(const QByteArray &data);

signals:
    void changed();

private:
    QString m_filePath;
    LoadFailure m_loadFailure = LoadFailure::None;
    // Cache keyed by the file's modification time (load() is called on hot paths).
    std::optional<QMap<QString, ParagraphStyle>> m_cache;
    QDateTime m_cacheModDate;
};

} // namespace lucerne
