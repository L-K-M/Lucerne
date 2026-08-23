#include "core/Furniture.h"

#include <algorithm>

namespace lucerne {
namespace Furniture {

QString resolveTemplate(const QString &templateText, std::optional<int> page,
                        int pages, const QString &date, const QString &title) {
    if (templateText.isEmpty()) return {};
    if (!page && (templateText.contains(QLatin1String("{page}"))
                  || templateText.contains(QLatin1String("{pages}"))))
        return {};
    QString out = templateText;
    out.replace(QLatin1String("{page}"), page ? QString::number(*page) : QString());
    out.replace(QLatin1String("{pages}"), QString::number(pages));
    out.replace(QLatin1String("{date}"), date);
    out.replace(QLatin1String("{title}"), title);
    return out;
}

std::optional<int> displayedPageNumber(int physicalPage, int pageCount,
                                       std::optional<int> pageNumberStart) {
    Q_UNUSED(pageCount);
    const int start = std::max(1, pageNumberStart.value_or(1));
    const int oneBased = physicalPage + 1;
    if (oneBased < start) return std::nullopt;
    return oneBased - start + 1;
}

int numberedPageCount(int pageCount, std::optional<int> pageNumberStart) {
    const int start = std::max(1, pageNumberStart.value_or(1));
    return std::max(0, pageCount - (start - 1));
}

} // namespace Furniture
} // namespace lucerne
