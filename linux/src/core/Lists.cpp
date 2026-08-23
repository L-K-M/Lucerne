#include "core/Lists.h"

namespace lucerne {
namespace ListMarkers {

QVector<std::optional<ResolvedMarker>> resolve(
    const QVector<std::optional<ListItemModel>> &items) {
    QVector<std::optional<ResolvedMarker>> result(items.size());
    QVector<qint64> counters;              // counters[level]; 0 == not yet started
    std::optional<QString> previousID;     // id of the immediately preceding item

    for (int index = 0; index < items.size(); ++index) {
        const auto &maybe = items[index];
        if (!maybe) {
            counters.clear();
            previousID.reset();
            continue;
        }
        const ListItemModel &item = *maybe;
        const int level = ListGeometry::clampedLevel(item.level);
        if (previousID != std::optional<QString>(item.list)) counters.clear();

        if (level >= counters.size()) {
            while (counters.size() <= level) counters.append(0);   // descend: new slots
        } else if (level < counters.size() - 1) {
            counters.resize(level + 1);                            // ascend: forget deeper
        }

        if (item.ordered) {
            if (counters[level] == 0) {
                counters[level] = std::max(1, item.start.value_or(1));
            } else {
                counters[level] += 1;
            }
            const int n = int(std::min<qint64>(counters[level],
                                               std::numeric_limits<int>::max()));
            result[index] = ResolvedMarker{orderedLabel(n, item.marker) + QLatin1Char('.'), n};
        } else {
            // A bullet doesn't count: the counter is untouched, so an ordered
            // item that follows keeps counting from where the numbers left off.
            result[index] = ResolvedMarker{bulletGlyph(item.marker, level), std::nullopt};
        }
        previousID = item.list;
    }
    return result;
}

QString bulletGlyph(const QString &marker, int level) {
    if (marker == QLatin1String("disc")) return QStringLiteral("•");
    if (marker == QLatin1String("circle")) return QStringLiteral("◦");
    if (marker == QLatin1String("square")) return QStringLiteral("▪");
    if (marker == QLatin1String("dash")) return QStringLiteral("–");
    // Unknown / "auto": cycle by depth like CSS's default bullet ramp.
    static const QString cycle[] = {QStringLiteral("•"), QStringLiteral("◦"),
                                    QStringLiteral("▪")};
    return cycle[ListGeometry::clampedLevel(level) % 3];
}

QString orderedLabel(int n, const QString &style) {
    if (style == QLatin1String("lower-alpha")) return alpha(n, false);
    if (style == QLatin1String("upper-alpha")) return alpha(n, true);
    if (style == QLatin1String("lower-roman")) return roman(n, false);
    if (style == QLatin1String("upper-roman")) return roman(n, true);
    return QString::number(std::max(1, n));   // "decimal" and anything unknown
}

QString alpha(int n, bool uppercase) {
    if (n < 1) return uppercase ? QStringLiteral("A") : QStringLiteral("a");
    const char base = uppercase ? 'A' : 'a';
    QString out;
    int value = n;
    while (value > 0) {
        value -= 1;
        out.prepend(QChar(base + value % 26));
        value /= 26;
    }
    return out;
}

QString roman(int n, bool uppercase) {
    if (n < 1 || n >= 4000) return QString::number(n);
    static const struct { int amount; const char *symbol; } table[] = {
        {1000, "M"}, {900, "CM"}, {500, "D"}, {400, "CD"}, {100, "C"}, {90, "XC"},
        {50, "L"}, {40, "XL"}, {10, "X"}, {9, "IX"}, {5, "V"}, {4, "IV"}, {1, "I"},
    };
    QString out;
    int value = n;
    for (const auto &row : table) {
        while (value >= row.amount) {
            out += QLatin1String(row.symbol);
            value -= row.amount;
        }
    }
    return uppercase ? out : out.toLower();
}

} // namespace ListMarkers
} // namespace lucerne
