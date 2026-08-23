// Page/exclusion geometry (C++) — mirrors Swift's ExclusionRectsTests and the
// PageMetrics coverage, plus the band→segments subtraction that is new on the
// Qt side (TextKit did it internally on the Mac).

#include "core/PageMetrics.h"

#include <QtTest>

using namespace lucerne;
using ExclusionPathController::Segment;
using ExclusionPathController::availableSegments;
using ExclusionPathController::exclusionRects;

namespace {

PlacedObject object(const QString &id, std::optional<int> page,
                    const QString &wrap = QStringLiteral("rectangular"), int z = 0,
                    std::optional<RectModel> frame = RectModel{200, 200, 100, 80}) {
    PlacedObject o;
    o.id = id;
    o.page = page;
    o.frame = frame;
    o.wrap = wrap;
    o.standoff = 12;
    o.z = z;
    return o;
}

} // namespace

class tst_metrics : public QObject {
    Q_OBJECT

    PageMetrics metrics = PageMetrics(PageConfig::a4());

private slots:
    void contentSizeSubtractsMargins() {
        QCOMPARE(metrics.contentSize().width, 595.28 - 144);
        QCOMPARE(metrics.contentSize().height, 841.89 - 144);
    }

    void exclusionRectShiftsByMarginsAndInflatesByStandoff() {
        const RectModel rect = metrics.exclusionRect({200, 200, 100, 80}, 12);
        QCOMPARE(rect.x, 200.0 - 72 - 12);
        QCOMPARE(rect.y, 200.0 - 72 - 12);
        QCOMPARE(rect.width, 100.0 + 24);
        QCOMPARE(rect.height, 80.0 + 24);
    }

    void narrowMarginSliverSnapsToTheMargin() {
        // An object 30 pt from the left margin: the 30-pt sliver is below the
        // 72-pt minimum column, so the exclusion extends to the margin.
        const RectModel rect = metrics.exclusionRect({72 + 30, 200, 100, 80}, 0);
        QCOMPARE(rect.x, 0.0);
        // …and similarly on the right.
        const double contentW = metrics.contentSize().width;
        const RectModel right = metrics.exclusionRect({595.28 - 72 - 100 - 30, 200, 100, 80}, 0);
        QCOMPARE(right.maxX(), contentW);
        // Standoff inflation counts toward the minimum-column check: a 96-pt
        // gap is wide enough on its own, but the 30-pt standoff shrinks it to
        // 66 pt (< 72) → still snaps.
        const RectModel inflated = metrics.exclusionRect({72 + 96, 200, 100, 80}, 30);
        QCOMPARE(inflated.x, 0.0);
    }

    void exclusionBeyondTheRightEdgeDoesNotWidenTheLine() {
        // An object dragged into the right page margin yields a span starting
        // beyond maxX; the emitted segment must still stop at maxX instead of
        // overshooting into the margin.
        const QVector<RectModel> exclusions = {{471, 0, 64, 100}};
        QCOMPARE(availableSegments(0, 14, 0, 451, exclusions),
                 (QVector<Segment>{{0, 451}}));
    }

    void rectsCoverOnlyWrappingObjectsOnThePage() {
        const QVector<PlacedObject> objects = {
            object("a", 0),                                   // on page → included
            object("b", 1),                                   // other page → excluded
            object("c", 0, "none"),                           // overlay → excluded
            object("d", 0, "rectangular", 0, std::nullopt),   // no frame → excluded
        };
        const auto rects = exclusionRects(0, objects, metrics);
        QCOMPARE(rects.size(), 1);
        QCOMPARE(rects.first(), metrics.exclusionRect({200, 200, 100, 80}, 12));
    }

    void rectsAreZSorted() {
        QVector<PlacedObject> objects = {
            object("front", 0, "rectangular", 2, RectModel{300, 300, 10, 10}),
            object("back", 0, "rectangular", 1, RectModel{100, 100, 10, 10}),
        };
        const auto rects = exclusionRects(0, objects, metrics);
        QCOMPARE(rects.size(), 2);
        QCOMPARE(rects.first().y, 100.0 - 72 - 12);   // z=1 first
    }

    void irregularWrapFallsBackToTheBoundingRect() {
        const auto rects = exclusionRects(0, {object("a", 0, "irregular")}, metrics);
        QCOMPARE(rects.size(), 1);
        QCOMPARE(rects.first(), metrics.exclusionRect({200, 200, 100, 80}, 12));
    }

    void clampKeepsObjectOnThePage() {
        const RectModel clamped = metrics.clampObjectFrame({-50, 900, 200, 100});
        QCOMPARE(clamped.x, 0.0);
        QCOMPARE(clamped.maxY(), metrics.pageSize.height);
    }

    void aspectFitScalesDownOnly() {
        const SizeModel fitted = aspectFitSize({100, 2000}, {250, 800});
        QCOMPARE(fitted.width, 40.0);
        QCOMPARE(fitted.height, 800.0);
        const SizeModel untouched = aspectFitSize({50, 50}, {100, 100});
        QCOMPARE(untouched.width, 50.0);
    }

    // MARK: - Band subtraction (the per-line flow step)

    void unobstructedBandIsOneFullSegment() {
        const auto segments = availableSegments(0, 14, 0, 451, {});
        QCOMPARE(segments, (QVector<Segment>{{0, 451}}));
    }

    void bandMissingTheRectIsUnaffected() {
        const QVector<RectModel> exclusions = {{100, 200, 120, 100}};
        QCOMPARE(availableSegments(0, 14, 0, 451, exclusions),
                 (QVector<Segment>{{0, 451}}));
        QCOMPARE(availableSegments(300, 14, 0, 451, exclusions),
                 (QVector<Segment>{{0, 451}}));
    }

    void intersectingBandSplitsAroundTheRect() {
        const QVector<RectModel> exclusions = {{100, 0, 120, 100}};
        QCOMPARE(availableSegments(50, 14, 0, 451, exclusions),
                 (QVector<Segment>{{0, 100}, {220, 231}}));
    }

    void sliversNarrowerThanMinimumAreDropped() {
        const QVector<RectModel> exclusions = {{8, 0, 120, 100}};
        // Left gap of 8 pt < 12 pt minimum → only the right side remains.
        QCOMPARE(availableSegments(0, 14, 0, 451, exclusions),
                 (QVector<Segment>{{128, 323}}));
    }

    void overlappingRectsMerge() {
        const QVector<RectModel> exclusions = {{100, 0, 120, 100}, {180, 0, 120, 100}};
        QCOMPARE(availableSegments(0, 14, 0, 451, exclusions),
                 (QVector<Segment>{{0, 100}, {300, 151}}));
    }

    void fullWidthRectLeavesNothing() {
        const QVector<RectModel> exclusions = {{-10, 0, 500, 100}};
        QVERIFY(availableSegments(0, 14, 0, 451, exclusions).isEmpty());
    }
};

QTEST_GUILESS_MAIN(tst_metrics)
#include "tst_metrics.moc"
