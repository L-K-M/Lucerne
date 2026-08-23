#pragma once

// Plain geometry value types mirroring Swift LucerneCore's Geometry.swift: the
// document model speaks points (1/72"), origin page top-left, y down. QRectF
// conversions happen at the view boundary, never inside the model.

#include <QPointF>
#include <QRectF>
#include <QSizeF>

namespace lucerne {

struct PointModel {
    double x = 0;
    double y = 0;

    QPointF toQPointF() const { return {x, y}; }
    friend bool operator==(const PointModel &a, const PointModel &b) {
        return a.x == b.x && a.y == b.y;
    }
    friend bool operator!=(const PointModel &a, const PointModel &b) { return !(a == b); }
};

struct SizeModel {
    double width = 0;
    double height = 0;

    QSizeF toQSizeF() const { return {width, height}; }
    friend bool operator==(const SizeModel &a, const SizeModel &b) {
        return a.width == b.width && a.height == b.height;
    }
    friend bool operator!=(const SizeModel &a, const SizeModel &b) { return !(a == b); }
};

struct RectModel {
    double x = 0;
    double y = 0;
    double width = 0;
    double height = 0;

    double minX() const { return x; }
    double minY() const { return y; }
    double maxX() const { return x + width; }
    double maxY() const { return y + height; }

    QRectF toQRectF() const { return {x, y, width, height}; }
    static RectModel fromQRectF(const QRectF &r) { return {r.x(), r.y(), r.width(), r.height()}; }

    friend bool operator==(const RectModel &a, const RectModel &b) {
        return a.x == b.x && a.y == b.y && a.width == b.width && a.height == b.height;
    }
    friend bool operator!=(const RectModel &a, const RectModel &b) { return !(a == b); }
};

struct EdgeInsetsModel {
    double top = 0;
    double left = 0;
    double bottom = 0;
    double right = 0;

    static EdgeInsetsModel uniform(double v) { return {v, v, v, v}; }
    friend bool operator==(const EdgeInsetsModel &a, const EdgeInsetsModel &b) {
        return a.top == b.top && a.left == b.left && a.bottom == b.bottom && a.right == b.right;
    }
    friend bool operator!=(const EdgeInsetsModel &a, const EdgeInsetsModel &b) { return !(a == b); }
};

} // namespace lucerne
