#pragma once

// Factory helpers for new documents and the default style table — the C++
// mirror of Swift LucerneCore's DefaultDocuments.swift, so a letter started on
// Ubuntu carries exactly the stylesheet a Mac-started letter does.

#include "core/Model.h"

#include <QByteArray>

namespace lucerne {
namespace DefaultDocuments {

/// The standard ClarisWorks-ish stylesheet: Body, two headings, a list item,
/// and a block quote — each with its markdown export hint and explicit order.
QMap<QString, ParagraphStyle> defaultStyles();

/// The traditional menu order of the classic five roles (for files that
/// predate the per-style `order` member).
QStringList styleRoleOrder();

/// The starter collection a brand-new style library is seeded with: the
/// classic five plus Heading 3, Title, Subtitle, Code, Pull Quote, Caption,
/// and Fine Print.
QMap<QString, ParagraphStyle> starterLibraryStyles();

/// A blank document with a single empty Body paragraph (File ▸ New).
DocumentModel empty(const PageConfig &page = PageConfig::a4());

/// The demo letter with one page-anchored image, so the app demonstrates live
/// reflow the moment it launches.
DocumentModel sampleLetter(const PageConfig &page = PageConfig::a4());

/// Original bytes for the sample letter's small lake illustration, keyed by
/// its archive path ("images/lake.png").
QMap<QString, QByteArray> sampleLetterImages();

} // namespace DefaultDocuments
} // namespace lucerne
