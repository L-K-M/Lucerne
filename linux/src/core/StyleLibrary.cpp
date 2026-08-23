#include "core/StyleLibrary.h"
#include "core/Coding.h"
#include "core/DefaultDocuments.h"

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonDocument>
#include <QJsonObject>
#include <QSaveFile>
#include <QStandardPaths>

#include <cmath>
#include <limits>

namespace lucerne {

namespace {

QString defaultFilePath() {
    QString base = QStandardPaths::writableLocation(QStandardPaths::AppDataLocation);
    if (base.isEmpty()) base = QDir::tempPath();
    return base + QStringLiteral("/styles.json");
}

} // namespace

StyleLibrary::StyleLibrary(const QString &filePath, QObject *parent)
    : QObject(parent), m_filePath(filePath.isEmpty() ? defaultFilePath() : filePath) {}

StyleLibrary *StyleLibrary::shared() {
    static StyleLibrary instance;
    return &instance;
}

QMap<QString, ParagraphStyle> StyleLibrary::load() {
    const QFileInfo info(m_filePath);
    if (!info.exists()) {
        // No file yet: a legitimately empty library, not a failure.
        m_loadFailure = LoadFailure::None;
        m_cache = QMap<QString, ParagraphStyle>();
        m_cacheModDate = QDateTime();
        return {};
    }
    const QDateTime modDate = info.lastModified();
    if (m_cache && m_cacheModDate == modDate) return *m_cache;

    QFile file(m_filePath);
    if (!file.open(QIODevice::ReadOnly)) {
        if (m_loadFailure != LoadFailure::Unreadable)
            qWarning("Lucerne: could not read style library at %s; refusing to "
                     "overwrite it until it loads cleanly", qPrintable(m_filePath));
        m_loadFailure = LoadFailure::Unreadable;
        m_cache = QMap<QString, ParagraphStyle>();
        m_cacheModDate = modDate;
        return {};
    }
    try {
        const auto styles = decode(file.readAll());
        m_cache = styles;
        m_cacheModDate = modDate;
        m_loadFailure = LoadFailure::None;
        return styles;
    } catch (const std::exception &error) {
        if (m_loadFailure != LoadFailure::Undecodable)
            qWarning("Lucerne: could not decode style library at %s (%s); refusing "
                     "to overwrite it until it loads cleanly",
                     qPrintable(m_filePath), error.what());
        m_loadFailure = LoadFailure::Undecodable;
        m_cache = QMap<QString, ParagraphStyle>();
        m_cacheModDate = modDate;
        return {};
    }
}

void StyleLibrary::save(const QMap<QString, ParagraphStyle> &styles) {
    if (m_loadFailure != LoadFailure::None) {
        qWarning("Lucerne: refusing to overwrite the style library while it is in "
                 "a load-failure state; leaving it untouched");
        return;
    }
    QDir().mkpath(QFileInfo(m_filePath).absolutePath());
    QSaveFile file(m_filePath);
    if (!file.open(QIODevice::WriteOnly) || file.write(encode(styles)) < 0
        || !file.commit()) {
        // Preferences-grade file: failing to persist must never take the app
        // down; the next save retries.
        qWarning("Lucerne: could not write style library: %s",
                 qPrintable(file.errorString()));
        return;
    }
    m_cache = styles;
    m_cacheModDate = QFileInfo(m_filePath).lastModified();
    emit changed();
}

void StyleLibrary::saveStyle(const ParagraphStyle &def, const QString &key) {
    auto library = load();
    ParagraphStyle merged = def;
    const auto existing = library.constFind(key);
    if (existing != library.constEnd() && existing->order) {
        merged.order = existing->order;   // pushing a definition shouldn't reshuffle
    } else if (!merged.order) {
        double maxOrder = -std::numeric_limits<double>::infinity();
        for (const auto &s : library)
            if (s.order) maxOrder = std::max(maxOrder, *s.order);
        merged.order = (std::isfinite(maxOrder) ? maxOrder : library.size() - 1) + 1;
    }
    library.insert(key, merged);
    save(library);
}

void StyleLibrary::removeStyle(const QString &key) {
    auto library = load();
    if (library.remove(key) == 0) return;
    save(library);
}

void StyleLibrary::seedStarterLibraryIfNeeded() {
    if (QFileInfo::exists(m_filePath)) return;
    save(DefaultDocuments::starterLibraryStyles());
}

QMap<QString, ParagraphStyle> StyleLibrary::seededStyles(
    const QMap<QString, ParagraphStyle> &base) {
    auto library = load();
    if (library.isEmpty()) return base;
    const QString bodyRole = DocumentModel::defaultStyleRole();
    if (!library.contains(bodyRole)) {
        ParagraphStyle body = base.value(bodyRole, ParagraphStyle::fallbackBody());
        double minOrder = std::numeric_limits<double>::infinity();
        for (const auto &s : library)
            if (s.order) minOrder = std::min(minOrder, *s.order);
        body.order = (std::isfinite(minOrder) ? minOrder : 0) - 1;
        library.insert(bodyRole, body);
    }
    return library;
}

QMap<QString, ParagraphStyle> StyleLibrary::seededStyles() {
    return seededStyles(DefaultDocuments::defaultStyles());
}

QByteArray StyleLibrary::encode(const QMap<QString, ParagraphStyle> &styles) {
    QJsonObject root;
    root.insert(QLatin1String("format"), canonicalFormat());
    root.insert(QLatin1String("formatVersion"), currentFormatVersion());
    root.insert(QLatin1String("styles"), Coding::encodeStyleTable(styles));
    return Coding::stableJson(root);
}

QMap<QString, ParagraphStyle> StyleLibrary::decode(const QByteArray &data) {
    QJsonParseError parseError;
    const QJsonDocument doc = QJsonDocument::fromJson(data, &parseError);
    if (doc.isNull() || !doc.isObject())
        throw CodingError(CodingError::Kind::Malformed,
                          QStringLiteral("styles.json is not a JSON object (%1)")
                              .arg(parseError.errorString()));
    const QJsonObject root = doc.object();
    if (root.value(QLatin1String("format")).toString() != canonicalFormat())
        throw CodingError(CodingError::Kind::WrongFormat,
                          QStringLiteral("not a lucerne-styles file"));
    // formatVersion is REQUIRED and must be a whole number (the Swift
    // reference declares it as a required Int): a malformed file must enter
    // the load-failure state so saves refuse to clobber it — accepting it as
    // "version 0" would defeat exactly that guard.
    const QJsonValue version = root.value(QLatin1String("formatVersion"));
    const double versionValue = version.toDouble(-1);
    if (!version.isDouble() || versionValue != std::floor(versionValue))
        throw CodingError(CodingError::Kind::Malformed,
                          QStringLiteral("styles.json has no integer formatVersion"));
    if (versionValue > currentFormatVersion())
        throw CodingError(CodingError::Kind::FormatTooNew,
                          QStringLiteral("styles.json is from a newer Lucerne"));
    if (!root.value(QLatin1String("styles")).isObject())
        throw CodingError(CodingError::Kind::Malformed,
                          QStringLiteral("styles.json has no styles table"));
    return Coding::decodeStyleTable(root.value(QLatin1String("styles")).toObject());
}

} // namespace lucerne
