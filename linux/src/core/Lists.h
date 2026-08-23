#pragma once

// List rendering support — the C++ mirror of Swift LucerneCore's
// ListSupport.swift. The marker a list item shows is *derived* from the run of
// items around it, never stored, so all of that logic lives here in one place
// and is shared by layout, Markdown export, and the editor commands.

#include "core/Model.h"

#include <QString>
#include <QVector>
#include <optional>

namespace lucerne {

// MARK: - Geometry

namespace ListGeometry {
/// Points of indent added per nesting level.
constexpr double indentStep = 24;
/// Gap between a marker's right edge and the text it labels.
constexpr double markerGap = 6;
/// The editor exposes at most nine nesting depths (levels 0 through 8).
constexpr int maximumLevelValue = 8;

inline int maximumLevel() { return maximumLevelValue; }
inline int clampedLevel(int level) { return std::min(std::max(0, level), maximumLevelValue); }
/// Where a level's text (and its wrapped lines) begin, in points from the margin.
inline double contentIndent(int level) { return indentStep * (clampedLevel(level) + 1); }
} // namespace ListGeometry

// MARK: - Marker resolution (the numbering engine)

/// The visible marker for one item, resolved against its neighbours.
struct ResolvedMarker {
    QString text;              // "•", "1.", "a." … (what layout draws)
    std::optional<int> number; // an ordered item's raw count (empty for bullets)

    friend bool operator==(const ResolvedMarker &a, const ResolvedMarker &b) {
        return a.text == b.text && a.number == b.number;
    }
};

namespace ListMarkers {

/// Resolves the marker of every paragraph in document order. Empty optionals in
/// `items` are non-list paragraphs (they break continuity and reset numbering).
/// A list is the maximal run of contiguous items sharing one `list` id.
QVector<std::optional<ResolvedMarker>> resolve(
    const QVector<std::optional<ListItemModel>> &items);

QString bulletGlyph(const QString &marker, int level);
/// The label for an ordered item (without the trailing "."): "1", "a", "IV" …
QString orderedLabel(int n, const QString &style);
/// Bijective base-26: 1→a, 26→z, 27→aa …
QString alpha(int n, bool uppercase);
/// Roman numerals for 1…3999; outside that range falls back to decimal.
QString roman(int n, bool uppercase);

inline QString defaultOrderedMarker() { return QStringLiteral("decimal"); }
inline QString defaultUnorderedMarker() { return QStringLiteral("disc"); }

} // namespace ListMarkers

} // namespace lucerne
