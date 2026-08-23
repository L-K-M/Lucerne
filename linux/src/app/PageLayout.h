#pragma once

// The paginated layout engine with live text flow around freely placed
// objects — the heart of the port (docs/ubuntu-port.md §2, Qt entry). On the
// Mac, TextKit's NSLayoutManager flows text around NSTextContainer exclusion
// paths; here the same geometry runs through QTextLayout's manual line API:
// for every line we subtract the page's exclusion rects from its band
// (ExclusionPathController::availableSegments) and hand each remaining span a
// QTextLine via setLineWidth/setPosition. Shaping, bidi, and font fallback
// stay Qt/HarfBuzz's problem.
//
// Coordinates: lines are positioned in canvas space — page i's sheet spans
// y = i * (pageHeight + pageGap), and its text area starts at the margins.
// That keeps hit-testing, caret geometry, and QTextCursor's vertical movement
// consistent across page boundaries with no per-block transforms.

#include "core/Model.h"
#include "core/PageMetrics.h"

#include <QAbstractTextDocumentLayout>
#include <QVector>

namespace lucerne {

class PageLayout : public QAbstractTextDocumentLayout {
    Q_OBJECT
public:
    explicit PageLayout(QTextDocument *doc);

    static constexpr double pageGap = 24;

    /// Page geometry (rebuilds metrics; full relayout).
    void setPage(const PageConfig &page);
    const PageConfig &page() const { return m_page; }
    PageMetrics metrics() const { return PageMetrics(m_page); }

    /// The placed objects whose wrap punches holes in the flow. Cheap when the
    /// resulting exclusion rects are unchanged (the Mac's dirty-check, 3.1).
    void setObjects(const QVector<PlacedObject> &objects);

    int pageCount() const override { return m_pageCount; }
    QRectF pageRect(int index) const;          // the white sheet, canvas coords
    QRectF textAreaRect(int index) const;      // inside the margins
    int pageIndexForPoint(const QPointF &canvasPoint) const;

    /// Resolved list markers for painting: (canvas position baseline-right,
    /// text, block number). Recomputed on every relayout.
    struct Marker {
        int blockNumber;
        QPointF baselineRight;   // right edge of the marker, baseline y
        QString text;
    };
    const QVector<Marker> &listMarkers() const { return m_markers; }

    // QAbstractTextDocumentLayout
    void draw(QPainter *painter, const PaintContext &context) override;
    int hitTest(const QPointF &point, Qt::HitTestAccuracy accuracy) const override;
    QSizeF documentSize() const override;
    QRectF frameBoundingRect(QTextFrame *frame) const override;
    QRectF blockBoundingRect(const QTextBlock &block) const override;

signals:
    /// Emitted after any relayout completes (page count may or may not change).
    void layoutChanged();

protected:
    void documentChanged(int from, int charsRemoved, int charsAdded) override;

private:
    struct BandCursor {
        int page = 0;
        double y = 0;             // container-local, within the page's text area
    };

    void relayoutFromBlock(int blockNumber);
    QVector<RectModel> exclusionsForPage(int page) const;
    void rebuildMarkers();
    double pageTop(int index) const { return index * (m_page.height + pageGap); }
    /// Container-local → canvas.
    QPointF canvasPoint(int page, double x, double y) const;

    PageConfig m_page = PageConfig::a4();
    QVector<PlacedObject> m_objects;
    int m_pageCount = 1;
    QVector<QRectF> m_blockBounds;      // canvas coords, indexed by block number
    QVector<BandCursor> m_blockStart;   // where each block began (for partial relayout)
    QVector<Marker> m_markers;
    bool m_inLayout = false;
};

} // namespace lucerne
