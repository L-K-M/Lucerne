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

QSet<QString> referencedImageSources(const DocumentModel &model) {
    QSet<QString> referenced;
    for (const PlacedObject &object : model.objects)
        if (object.type == QLatin1String("image") && object.src)
            referenced.insert(*object.src);
    return referenced;
}

} // namespace

QByteArray write(const DocumentModel &model, const QMap<QString, QByteArray> &images,
                 const QVector<HistorySnapshot> &history) {
    QVector<MiniZip::Entry> entries;
    entries.append({documentEntryName(), Coding::encode(model)});

    // Only images actually referenced by the model, in a stable order.
    QStringList referenced = referencedImageSources(model).values();
    std::sort(referenced.begin(), referenced.end());
    for (const QString &src : referenced) {
        const auto it = images.constFind(src);
        if (it == images.constEnd())
            throw std::runtime_error(
                QStringLiteral("Can't save the document because a referenced image "
                               "is missing (%1).").arg(src).toStdString());
        entries.append({src, *it});
    }

    entries.append({markdownEntryName(),
                    MarkdownExporter::exportModel(model).toUtf8()});

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

    for (const MiniZip::Entry &entry : entries) {
        const QDateTime timestamp = HistoryPruner::timestampFromEntryName(entry.name);
        if (!timestamp.isValid()) continue;
        contents.history.append({timestamp, QString::fromUtf8(entry.data)});
    }
    return contents;
}

} // namespace LuceArchive
} // namespace lucerne
