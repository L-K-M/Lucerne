#pragma once

// Reads and writes the .luce package — the C++ mirror of Swift LucerneCore's
// LuceArchive.swift: a ZIP containing document.json (canonical), loose image
// files under images/, a derived content.md, and dated history/ backups.

#include "core/History.h"
#include "core/Model.h"

#include <QByteArray>
#include <QMap>
#include <QString>
#include <QVector>

namespace lucerne {
namespace LuceArchive {

inline QString documentEntryName() { return QStringLiteral("document.json"); }
inline QString markdownEntryName() { return QStringLiteral("content.md"); }
inline QString imagesPrefix() { return QStringLiteral("images/"); }

struct Contents {
    DocumentModel model;
    QMap<QString, QByteArray> images;      // keyed by src path, e.g. "images/lake.png"
    QVector<HistorySnapshot> history;      // dated Markdown backups under history/
};

/// Serializes the package. content.md is regenerated from the model; only
/// referenced images are written (a referenced image with no bytes throws — a
/// silent unopenable-picture save is worse than an error). Throws
/// MiniZip::ZipError or std::runtime_error.
QByteArray write(const DocumentModel &model, const QMap<QString, QByteArray> &images,
                 const QVector<HistorySnapshot> &history = {});

/// Opens the package. Strict integrity for the authoritative content
/// (document.json, images/); a bit-rotted recovery entry (content.md,
/// history/*) is dropped rather than blocking the document. Throws
/// MiniZip::ZipError or CodingError.
Contents read(const QByteArray &data);

} // namespace LuceArchive
} // namespace lucerne
