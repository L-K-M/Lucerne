#include "core/PageMetrics.h"

#include <algorithm>
#include <cmath>

namespace lucerne {

SizeModel aspectFitSize(const SizeModel &sourceSize, const SizeModel &maximumSize) {
    if (!std::isfinite(sourceSize.width) || !std::isfinite(sourceSize.height)
        || !std::isfinite(maximumSize.width) || !std::isfinite(maximumSize.height)
        || sourceSize.width <= 0 || sourceSize.height <= 0
        || maximumSize.width <= 0 || maximumSize.height <= 0)
        return {0, 0};
    const double scale = std::min(1.0, std::min(maximumSize.width / sourceSize.width,
                                                maximumSize.height / sourceSize.height));
    return {sourceSize.width * scale, sourceSize.height * scale};
}

QVector<double> PageMetrics::din5008FoldMarkOffsetsFromTop() {
    const double pointsPerMillimetre = 72.0 / 25.4;
    return {105 * pointsPerMillimetre, 210 * pointsPerMillimetre};
}

RectModel PageMetrics::exclusionRect(const RectModel &objectFrame, double standoff,
                                     double minColumn) const {
    const double s = standoff;
    double left = objectFrame.minX() - marginLeft - s;
    double right = objectFrame.maxX() - marginLeft + s;
    const double top = objectFrame.minY() - marginTop - s;
    const double height = objectFrame.height + 2 * s;
    const double width = contentSize().width;

    if (left > 0 && left < minColumn) left = 0;
    if (right < width && width - right < minColumn) right = width;

    return {left, top, right - left, height};
}

RectModel PageMetrics::clampObjectFrame(const RectModel &frame) const {
    RectModel f = frame;
    f.width = std::min(f.width, pageSize.width);
    f.height = std::min(f.height, pageSize.height);
    f.x = std::min(std::max(0.0, f.x), pageSize.width - f.width);
    f.y = std::min(std::max(0.0, f.y), pageSize.height - f.height);
    return f;
}

namespace ExclusionPathController {

QVector<RectModel> exclusionRects(int pageIndex, const QVector<PlacedObject> &objects,
                                  const PageMetrics &metrics) {
    QVector<const PlacedObject *> wrapping;
    for (const PlacedObject &object : objects) {
        if (object.anchorMode() != PlacedObject::Anchor::Page) continue;
        if (object.page != std::optional<int>(pageIndex)) continue;
        if (object.wrapMode() == PlacedObject::Wrap::None) continue;
        if (!object.frame) continue;
        wrapping.append(&object);
    }
    std::stable_sort(wrapping.begin(), wrapping.end(),
                     [](const PlacedObject *a, const PlacedObject *b) { return a->z < b->z; });
    QVector<RectModel> rects;
    for (const PlacedObject *object : wrapping)
        rects.append(metrics.exclusionRect(*object->frame, object->standoff));
    return rects;
}

QVector<Segment> availableSegments(double bandTop, double bandHeight,
                                   double minX, double maxX,
                                   const QVector<RectModel> &exclusions,
                                   double minWidth) {
    // Collect the [left, right] spans of every exclusion that vertically
    // intersects the band, then sweep left→right merging overlaps.
    struct Span {
        double left, right;
    };
    QVector<Span> blocked;
    const double bandBottom = bandTop + bandHeight;
    for (const RectModel &rect : exclusions) {
        if (rect.maxY() <= bandTop || rect.minY() >= bandBottom) continue;
        blocked.append({rect.minX(), rect.maxX()});
    }
    std::sort(blocked.begin(), blocked.end(),
              [](const Span &a, const Span &b) { return a.left < b.left; });

    QVector<Segment> segments;
    double cursor = minX;
    for (const Span &span : blocked) {
        const double left = std::max(span.left, minX);
        const double right = std::min(span.right, maxX);
        if (right <= cursor) continue;
        if (left > cursor && left - cursor >= minWidth)
            segments.append({cursor, left - cursor});
        cursor = std::max(cursor, right);
        if (cursor >= maxX) break;
    }
    if (maxX - cursor >= minWidth) segments.append({cursor, maxX - cursor});
    return segments;
}

} // namespace ExclusionPathController

} // namespace lucerne
