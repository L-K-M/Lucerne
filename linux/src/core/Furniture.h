#pragma once

// Header/footer token substitution — the C++ mirror of Swift
// EditorController.resolveFurnitureTemplate (pinned by FurnitureTokenTests).

#include <QString>
#include <optional>

namespace lucerne {
namespace Furniture {

/// Substitutes {page}, {pages}, {date}, {title}. `page` is empty on an
/// unnumbered page (before the numbering start): a zone that references a page
/// number is then blanked — you never see "Page  of 3" — while date/title-only
/// zones still render.
QString resolveTemplate(const QString &templateText, std::optional<int> page,
                        int pages, const QString &date, const QString &title);

/// The page number shown on a physical page (0-based) under `pageNumberStart`
/// (1-based; absent = every page numbered from 1), or empty when unnumbered.
std::optional<int> displayedPageNumber(int physicalPage, int pageCount,
                                       std::optional<int> pageNumberStart);

/// How many pages carry a number ({pages} counts only those).
int numberedPageCount(int pageCount, std::optional<int> pageNumberStart);

} // namespace Furniture
} // namespace lucerne
