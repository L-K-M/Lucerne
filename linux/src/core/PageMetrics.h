#pragma once

// All page geometry in one place — the C++ mirror of Swift LucerneCore's
// PageMetrics.swift + ExclusionRects.swift, plus the band→segments subtraction
// the Qt layout engine needs (on the Mac, TextKit performs that subtraction
// internally once exclusion paths are assigned; with QTextLayout the per-line
// geometry is ours, so it lives here where it is unit-testable headlessly).
// Units are points, origin top-left, y down.

#include "core/Model.h"

#include <QVector>

namespace lucerne {

/// Returns `sourceSize` scaled down by one factor to fit both dimensions of
/// `maximumSize`. Smaller images retain their native size.
SizeModel aspectFitSize(const SizeModel &sourceSize, const SizeModel &maximumSize);

struct PageMetrics {
    SizeModel pageSize;
    double marginTop = 0;
    double marginLeft = 0;
    double marginBottom = 0;
    double marginRight = 0;

    explicit PageMetrics(const PageConfig &page)
        : pageSize{page.width, page.height},
          marginTop(page.margins.top), marginLeft(page.margins.left),
          marginBottom(page.margins.bottom), marginRight(page.margins.right) {}

    /// DIN 5008 fold guides, measured from the top edge (105 mm and 210 mm).
    static QVector<double> din5008FoldMarkOffsetsFromTop();

    /// Size of the text area (the text container, identical on every page, D1).
    SizeModel contentSize() const {
        return {std::max(0.0, pageSize.width - marginLeft - marginRight),
                std::max(0.0, pageSize.height - marginTop - marginBottom)};
    }

    /// Frame of the text area within its page (page coordinates).
    RectModel textFrameInPage() const {
        return {marginLeft, marginTop, contentSize().width, contentSize().height};
    }

    /// The exclusion rectangle for a page-anchored object, in **text-container**
    /// coordinates: shift by the margins and inflate by the standoff gutter.
    /// A side gap narrower than `minColumn` is extended to that margin so text
    /// doesn't flow into an unusable sliver (the ClarisWorks/DTP behavior).
    RectModel exclusionRect(const RectModel &objectFrame, double standoff,
                            double minColumn = 72) const;

    /// Clamp a proposed object frame so the image stays within the page bounds.
    RectModel clampObjectFrame(const RectModel &frame) const;

    friend bool operator==(const PageMetrics &a, const PageMetrics &b) {
        return a.pageSize == b.pageSize && a.marginTop == b.marginTop
            && a.marginLeft == b.marginLeft && a.marginBottom == b.marginBottom
            && a.marginRight == b.marginRight;
    }
};

namespace ExclusionPathController {

/// Exclusion rectangles (container coordinates) for every page-anchored,
/// wrapping object on `pageIndex`, z-ascending. wrap=="none" objects are
/// overlays and contribute nothing; irregular falls back to the bounding rect.
QVector<RectModel> exclusionRects(int pageIndex, const QVector<PlacedObject> &objects,
                                  const PageMetrics &metrics);

/// A horizontal span text may occupy on one line.
struct Segment {
    double x = 0;
    double width = 0;
    friend bool operator==(const Segment &a, const Segment &b) {
        return a.x == b.x && a.width == b.width;
    }
};

/// Subtracts every exclusion rect that intersects the vertical band
/// [bandTop, bandTop+bandHeight) from the horizontal span [minX, maxX],
/// returning the left-to-right spans that remain (each at least `minWidth`
/// wide — narrower slivers are unusable and dropped). This is the per-line
/// step of the flow algorithm (ubuntu-port.md §2, Qt entry).
QVector<Segment> availableSegments(double bandTop, double bandHeight,
                                   double minX, double maxX,
                                   const QVector<RectModel> &exclusions,
                                   double minWidth = 12);

} // namespace ExclusionPathController

} // namespace lucerne
