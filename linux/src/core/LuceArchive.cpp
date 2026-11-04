#include "core/LuceArchive.h"
#include "core/Coding.h"
#include "core/Markdown.h"
#include "core/MiniZip.h"

#include <QFileInfo>
#include <QSet>

#include <algorithm>

namespace lucerne {
namespace LuceArchive {

namespace {

bool isFlatImageSource(const QString &src) {
    if (!src.startsWith(imagesPrefix())) return false;
    const QString filename = src.mid(imagesPrefix().size());
    return !filename.isEmpty() && filename != QLatin1String(".")
        && filename != QLatin1String("..") && !filename.contains(QLatin1Char('/'))
        && !filename.contains(QLatin1Char('\\')) && !filename.contains(QChar::Null);
}

QSet<QString> referencedImageSources(const DocumentModel &model) {
    QSet<QString> referenced;
    for (const PlacedObject &object : model.objects)
        if (object.type == QLatin1String("image") && object.src)
            referenced.insert(*object.src);
    return referenced;
}

/// NSString.lastPathComponent — the Swift reference's basename: trailing
/// slashes are ignored, then the substring after the last '/' is taken
/// ("a/b" → "b", "a/b/" → "b", "images/" → "images", "/" → "/").
QString lastPathComponent(const QString &path) {
    qsizetype end = path.size();
    while (end > 0 && path.at(end - 1) == QLatin1Char('/')) --end;
    if (end == 0) return path;   // nothing but slashes, e.g. "/" → "/"
    const qsizetype slash = path.lastIndexOf(QLatin1Char('/'), end - 1);
    return path.mid(slash + 1, end - slash - 1);
}

} // namespace

QByteArray write(const DocumentModel &model, const QMap<QString, QByteArray> &images,
                 const QVector<HistorySnapshot> &history) {
    // Entry names go into the ZIP verbatim, so a model `src` that isn't a flat
    // "images/<file>" name (traversal, absolute path, "document.json") must not
    // be written as-is. Normalize such sources to "images/<basename>" — the
    // payload is preserved, the archive stays safe — and refuse when that
    // isn't possible (no usable filename, or a collision).
    DocumentModel normalized = model;
    QMap<QString, QByteArray> payloads = images;
    QMap<QString, QString> renamed;
    // Every final entry name, including sources that were already flat — a
    // rename must not collide with a kept images/ key either.
    QSet<QString> takenNames;
    for (const PlacedObject &object : normalized.objects)
        if (object.type == QLatin1String("image") && object.src
            && isFlatImageSource(*object.src))
            takenNames.insert(*object.src);
    for (const PlacedObject &object : normalized.objects) {
        if (object.type != QLatin1String("image") || !object.src
            || isFlatImageSource(*object.src))
            continue;
        const QString src = *object.src;
        // Several objects may place the same picture; it is renamed once.
        if (renamed.contains(src)) continue;
        const QString filename = lastPathComponent(src)
            .replace(QLatin1Char('\\'), QLatin1Char('_'))
            .replace(QChar::Null, QLatin1Char('_'));
        const QString newName = imagesPrefix() + filename;
        if (!isFlatImageSource(newName))
            throw std::runtime_error(
                QStringLiteral("Can't save the image source %1; use images/<filename>.")
                    .arg(src).toStdString());
        if (takenNames.contains(newName))
            throw std::runtime_error(
                QStringLiteral("Can't save the image source %1; it would collide "
                               "with the existing entry %2.").arg(src, newName)
                    .toStdString());
        takenNames.insert(newName);
        renamed.insert(src, newName);
    }
    if (!renamed.isEmpty()) {
        for (PlacedObject &object : normalized.objects) {
            if (!object.src) continue;
            const auto target = renamed.constFind(*object.src);
            if (target != renamed.constEnd()) object.src = *target;
        }
        // A renamed payload must win over a stale, unreferenced image already
        // stored under its new name, whatever the map's key order.
        QMap<QString, QByteArray> moved;
        for (auto it = payloads.constBegin(); it != payloads.constEnd(); ++it) {
            if (!renamed.contains(it.key())) moved.insert(it.key(), it.value());
        }
        for (auto it = renamed.constBegin(); it != renamed.constEnd(); ++it) {
            const auto payload = payloads.constFind(it.key());
            if (payload != payloads.constEnd()) moved.insert(it.value(), *payload);
        }
        payloads = moved;
    }

    QVector<MiniZip::Entry> entries;
    entries.append({documentEntryName(), Coding::encode(normalized)});

    // Only images actually referenced by the model, in a stable order.
    QStringList referenced = referencedImageSources(normalized).values();
    std::sort(referenced.begin(), referenced.end());
    for (const QString &src : referenced) {
        const auto it = payloads.constFind(src);
        if (it == payloads.constEnd())
            throw std::runtime_error(
                QStringLiteral("Can't save the document because a referenced image "
                               "is missing (%1).").arg(src).toStdString());
        entries.append({src, *it});
    }

    // Derived from the normalized model so it names entries the archive holds.
    entries.append({markdownEntryName(),
                    MarkdownExporter::exportModel(normalized).toUtf8()});

    QVector<HistorySnapshot> sortedHistory = history;
    std::sort(sortedHistory.begin(), sortedHistory.end(),
              [](const HistorySnapshot &a, const HistorySnapshot &b) {
                  return a.timestamp < b.timestamp;
              });
    for (const HistorySnapshot &snapshot : sortedHistory)
        entries.append({HistoryPruner::entryName(snapshot.timestamp),
                        snapshot.markdown.toUtf8()});

    return MiniZip::archive(entries);
}

Contents read(const QByteArray &data) {
    const auto entries = MiniZip::entries(data, [](const QString &name) {
        // Best-effort content may be dropped; the authoritative entries stay strict.
        return name != documentEntryName() && !name.startsWith(imagesPrefix());
    });

    const auto documentEntry = std::find_if(entries.begin(), entries.end(),
        [](const MiniZip::Entry &e) { return e.name == documentEntryName(); });
    if (documentEntry == entries.end())
        throw MiniZip::ZipError(MiniZip::ZipError::Kind::Corrupt,
                                QStringLiteral("The archive has no document.json."));
    Contents contents;
    contents.model = Coding::decode(documentEntry->data);

    for (const MiniZip::Entry &entry : entries) {
        if (!entry.name.startsWith(imagesPrefix()) || entry.name.endsWith(QLatin1Char('/')))
            continue;
        // Accept only flat, well-formed names ("images/<file>") — reject the
        // zip-slip shape ("images/../../x") now so a future "extract images"
        // feature can't be caught out by it.
        const QString filename = QFileInfo(entry.name).fileName();
        if (filename.isEmpty() || entry.name != imagesPrefix() + filename) continue;
        contents.images.insert(entry.name, entry.data);
    }

    // The spec only requires `src` to name an archive entry — "images/" is a
    // convention — so also collect payloads for referenced sources outside
    // images/ (exact name match; the names are map keys, never paths we
    // extract to). This keeps third-party files with e.g. src
    // "pictures/a.png" loadable instead of unsavable.
    const QSet<QString> referenced = referencedImageSources(contents.model);
    for (const MiniZip::Entry &entry : entries) {
        if (entry.name.endsWith(QLatin1Char('/'))) continue;
        if (referenced.contains(entry.name))
            contents.images.insert(entry.name, entry.data);
    }

    for (const MiniZip::Entry &entry : entries) {
        const QDateTime timestamp = HistoryPruner::timestampFromEntryName(entry.name);
        if (!timestamp.isValid()) continue;
        contents.history.append({timestamp, QString::fromUtf8(entry.data)});
    }
    return contents;
}

} // namespace LuceArchive
} // namespace lucerne
