#include "core/Model.h"
#include "core/DefaultDocuments.h"

#include <QRandomGenerator>

#include <algorithm>
#include <atomic>
#include <limits>

namespace lucerne {

PageConfig PageConfig::a4() {
    return {QStringLiteral("A4"), 595.28, 841.89, EdgeInsetsModel::uniform(72), std::nullopt};
}

PageConfig PageConfig::usLetter() {
    return {QStringLiteral("Letter"), 612, 792, EdgeInsetsModel::uniform(72), std::nullopt};
}

ParagraphStyle ParagraphStyle::fallbackBody() {
    ParagraphStyle s;
    s.name = QStringLiteral("Body");
    s.font = QStringLiteral("Helvetica");
    s.size = 12;
    s.lineSpacing = 1.2;
    s.spaceAfter = 6;
    s.markdown = QStringLiteral("p");
    return s;
}

ParagraphStyle DocumentModel::resolvedStyle(const QString &role) const {
    auto it = styles.constFind(role);
    if (it != styles.constEnd()) return *it;
    it = styles.constFind(defaultStyleRole());
    if (it != styles.constEnd()) return *it;
    return ParagraphStyle::fallbackBody();
}

QStringList DocumentModel::orderedStyleRoles() const { return orderedStyleRoles(styles); }

QStringList DocumentModel::orderedStyleRoles(const QMap<QString, ParagraphStyle> &styles) {
    const QStringList legacy = DefaultDocuments::styleRoleOrder();
    struct Rank {
        double order;
        int legacyIndex;
        QString name;
    };
    auto rank = [&](const QString &key) -> Rank {
        const ParagraphStyle &s = styles[key];
        if (s.order) return {*s.order, -1, QString()};
        const int index = int(legacy.indexOf(key));
        if (index >= 0) return {std::numeric_limits<double>::max(), index, QString()};
        return {std::numeric_limits<double>::max(), int(legacy.size()),
                s.name.isEmpty() ? key : s.name};
    };
    QStringList keys = styles.keys();
    std::sort(keys.begin(), keys.end(), [&](const QString &a, const QString &b) {
        const Rank ra = rank(a), rb = rank(b);
        if (ra.order != rb.order) return ra.order < rb.order;
        if (ra.legacyIndex != rb.legacyIndex) return ra.legacyIndex < rb.legacyIndex;
        const int byName = QString::compare(ra.name, rb.name, Qt::CaseInsensitive);
        if (byName != 0) return byName < 0;
        return a < b;   // deterministic tiebreak
    });
    return keys;
}

namespace IDGenerator {

QString next(const QString &prefix) {
    // A monotonic counter gives readable ids; a random suffix guarantees
    // uniqueness even when new paragraphs are minted into a document that
    // already loaded ids from disk (the counter restarts every launch).
    static std::atomic<quint64> counter{0};
    const quint64 n = ++counter;
    const quint64 r = QRandomGenerator::global()->generate64();
    return prefix + QString::number(n, 36) + QLatin1Char('-') + QString::number(r, 36);
}

} // namespace IDGenerator

} // namespace lucerne
