#include "app/PageLayout.h"
#include "app/DocumentBridge.h"
#include "core/Lists.h"

#include <QFontMetricsF>
#include <QPainter>
#include <QTextBlock>
#include <QTextLayout>

#include <cmath>

namespace lucerne {

namespace {

/// A line narrower than this is not worth typesetting into (the sliver rule).
constexpr double minSegmentWidth = 12;
/// Runaway guard for one line's placement search (bands + page hops).
constexpr int maxPlacementSteps = 4000;

double lineSpacingMultiple(const QTextBlockFormat &bf) {
    if (bf.lineHeightType() == QTextBlockFormat::ProportionalHeight && bf.lineHeight() > 0)
        return bf.lineHeight() / 100.0;
    return 1.0;
}

} // namespace

PageLayout::PageLayout(QTextDocument *doc) : QAbstractTextDocumentLayout(doc) {}

void PageLayout::setPage(const PageConfig &page) {
    m_page = page;
    relayoutFromBlock(0);
}

void PageLayout::setObjects(const QVector<PlacedObject> &objects) {
    // Relayout only when the flow-relevant geometry actually changed — the
    // Mac's exclusion dirty-check (3.1): reassigning identical exclusions must
    // not trigger a re-paginate on every image sync.
    const PageMetrics m = metrics();
    auto flowRects = [&](const QVector<PlacedObject> &objs) {
        QVector<RectModel> rects;
        for (int p = 0; p <= m_pageCount; ++p)
            rects += ExclusionPathController::exclusionRects(p, objs, m);
        return rects;
    };
    auto maxPage = [](const QVector<PlacedObject> &objs) {
        int page = 0;
        for (const PlacedObject &o : objs)
            if (o.anchorMode() == PlacedObject::Anchor::Page && o.page)
                page = std::max(page, *o.page);
        return page;
    };
    const bool changed = flowRects(m_objects) != flowRects(objects)
        || maxPage(m_objects) != maxPage(objects);
    m_objects = objects;
    if (changed) relayoutFromBlock(0);
}

QRectF PageLayout::pageRect(int index) const {
    return {0, pageTop(index), m_page.width, m_page.height};
}

QRectF PageLayout::textAreaRect(int index) const {
    const RectModel frame = metrics().textFrameInPage();
    return {frame.x, pageTop(index) + frame.y, frame.width, frame.height};
}

int PageLayout::pageIndexForPoint(const QPointF &canvasPoint) const {
    const double stride = m_page.height + pageGap;
    const int index = int(std::floor(canvasPoint.y() / stride));
    return std::clamp(index, 0, std::max(0, m_pageCount - 1));
}

QPointF PageLayout::canvasPoint(int page, double x, double y) const {
    const PageMetrics m = metrics();
    return {m.marginLeft + x, pageTop(page) + m.marginTop + y};
}

QVector<RectModel> PageLayout::exclusionsForPage(int page) const {
    return ExclusionPathController::exclusionRects(page, m_objects, metrics());
}

void PageLayout::documentChanged(int from, int charsRemoved, int charsAdded) {
    Q_UNUSED(charsRemoved);
    Q_UNUSED(charsAdded);
    const QTextBlock dirty = document()->findBlock(std::max(0, from));
    // Blocks before the edit keep their geometry (their recorded band starts
    // still hold); everything from the dirty block onward re-lays.
    relayoutFromBlock(dirty.isValid() ? dirty.blockNumber() : 0);
}

void PageLayout::relayoutFromBlock(int startBlockNumber) {
    if (m_inLayout) return;   // no reentrancy: this function never edits the doc
    m_inLayout = true;

    QTextDocument *doc = document();
    const double contentW = metrics().contentSize().width;
    const double contentH = std::max(1.0, metrics().contentSize().height);
    const int blockCount = doc->blockCount();
    const int oldPageCount = m_pageCount;
    const QSizeF oldSize = documentSize();

    m_blockBounds.resize(blockCount);
    m_blockStart.resize(blockCount);

    BandCursor cursor;
    if (startBlockNumber > 0 && startBlockNumber < m_blockStart.size()) {
        cursor = m_blockStart[startBlockNumber];
    } else {
        startBlockNumber = 0;
    }

    for (QTextBlock block = doc->findBlockByNumber(startBlockNumber); block.isValid();
         block = block.next()) {
        const int number = block.blockNumber();
        const QTextBlockFormat bf = block.blockFormat();
        const QTextCharFormat bcf = block.charFormat();
        const double multiple = lineSpacingMultiple(bf);

        // Record where the block was ARRIVED at — before the page-break hop and
        // space-before are applied — so a partial relayout resuming here replays
        // those adjustments exactly once instead of stacking them per keystroke.
        m_blockStart[number] = cursor;

        // Forced page break (unless already at the top of a fresh page).
        if (bcf.boolProperty(Props::PageBreakBefore) && cursor.y > 0.001) {
            cursor.page += 1;
            cursor.y = 0;
        }
        // Space before, skipped at the top of a page (TextKit convention).
        if (cursor.y > 0.001) cursor.y += bf.topMargin();

        // List items get the hanging gutter on top of their own indent.
        double listIndent = 0;
        if (bcf.hasProperty(Props::ListItem)) {
            if (const auto item =
                    DocumentBridge::decodeListItem(bcf.stringProperty(Props::ListItem)))
                listIndent = ListGeometry::contentIndent(item->level);
        }
        const double blockLeft = bf.leftMargin() + listIndent;
        const double blockRight = std::max(blockLeft + minSegmentWidth,
                                           contentW - bf.rightMargin());

        QTextLayout *layout = block.layout();
        QTextOption option = doc->defaultTextOption();
        option.setWrapMode(QTextOption::WrapAtWordBoundaryOrAnywhere);
        option.setAlignment(bf.alignment());
        if (!bf.tabPositions().isEmpty()) option.setTabs(bf.tabPositions());
        layout->setTextOption(option);
        layout->setCacheEnabled(true);

        // Band state: lines fill a band's segments left→right; the band then
        // advances by its tallest line (× the paragraph's spacing multiple).
        int page = cursor.page;
        double bandTop = cursor.y;
        double bandAdvance = 0;
        int segmentIndex = 0;
        int segmentsInBand = 1;   // refreshed at each placement
        QRectF bounds;
        int lineIndex = 0;

        layout->beginLayout();
        for (;;) {
            QTextLine line = layout->createLine();
            if (!line.isValid()) break;

            const bool firstLine = (lineIndex == 0);
            double lineLeft = blockLeft + (firstLine ? bf.textIndent() : 0);
            // Guard the clamp bounds: schema-valid negative indents combined
            // with a large right indent can push hi below lo (UB otherwise).
            lineLeft = std::clamp(lineLeft, 0.0,
                                  std::max(0.0, blockRight - minSegmentWidth));

            const QFontMetricsF fm(bcf.font());
            double estimate = std::max(4.0, fm.lineSpacing());
            bool placed = false;

            for (int step = 0; step < maxPlacementSteps && !placed; ++step) {
                // A band that starts below the page's text area flows to the
                // next page. (bandTop == 0 always fits: a line taller than a
                // page clips rather than looping.)
                if (bandTop > 0.001 && bandTop + estimate > contentH) {
                    page += 1;
                    bandTop = 0;
                    bandAdvance = 0;
                    segmentIndex = 0;
                }

                const auto exclusions = exclusionsForPage(page);
                const auto segments = ExclusionPathController::availableSegments(
                    bandTop, estimate, lineLeft, blockRight, exclusions, minSegmentWidth);
                segmentsInBand = int(segments.size());

                if (segmentIndex >= segments.size()) {
                    // Band exhausted (or fully blocked). Advance: past the
                    // lines already placed, or past the shallowest obstacle
                    // bottom when the band was blocked outright.
                    double nextTop = bandTop + std::max(1.0, bandAdvance);
                    if (segments.isEmpty()) {
                        double obstacleBottom = 0;
                        for (const RectModel &rect : exclusions)
                            if (rect.maxY() > bandTop && rect.minY() < bandTop + estimate)
                                obstacleBottom = std::max(obstacleBottom, rect.maxY());
                        if (obstacleBottom > bandTop)
                            nextTop = std::max(nextTop, obstacleBottom);
                    }
                    bandTop = nextTop;
                    bandAdvance = 0;
                    segmentIndex = 0;
                    continue;
                }

                const auto segment = segments[segmentIndex];
                line.setLineWidth(segment.width);
                const double lineHeight = std::max(4.0, line.height());

                // The estimate drove the segment choice; re-verify with the
                // real height (a taller line can hit a lower obstacle corner).
                if (lineHeight > estimate + 0.001) {
                    estimate = lineHeight;
                    continue;
                }
                // Band no longer fits on the page with the real height.
                if (bandTop > 0.001 && bandTop + lineHeight > contentH) {
                    estimate = lineHeight;
                    continue;   // the fit check at the top hops the page
                }

                line.setPosition(canvasPoint(page, segment.x, bandTop));
                bounds = bounds.united(QRectF(line.position(),
                                              QSizeF(segment.width, lineHeight)));
                bandAdvance = std::max(bandAdvance, lineHeight * multiple);
                segmentIndex += 1;
                placed = true;
            }
            if (!placed) {
                // The placement guard exhausted (pathological geometry) — park
                // the line at the current band's full width rather than leaving
                // it unpositioned at the canvas origin.
                line.setLineWidth(std::max(minSegmentWidth, blockRight - lineLeft));
                line.setPosition(canvasPoint(page, lineLeft, bandTop));
                const double h = std::max(4.0, line.height());
                bounds = bounds.united(QRectF(line.position(),
                                              QSizeF(line.width(), h)));
                bandAdvance = std::max(bandAdvance, h * multiple);
                segmentIndex = segmentsInBand;   // band is spent
            }
            lineIndex += 1;

            if (segmentIndex >= segmentsInBand) {
                bandTop += std::max(1.0, bandAdvance);
                bandAdvance = 0;
                segmentIndex = 0;
            }
        }
        layout->endLayout();

        if (!bounds.isValid())
            bounds = QRectF(canvasPoint(page, blockLeft, bandTop), QSizeF(1, 1));
        m_blockBounds[number] = bounds;

        // The block ends after its last (possibly still-open) band, plus the
        // paragraph's space-after. Page overflow is resolved when the next
        // block's first line is placed — never here, so a document can't end
        // with a phantom empty page.
        cursor.page = page;
        cursor.y = bandTop + (segmentIndex > 0 ? std::max(1.0, bandAdvance) : 0);
        cursor.y += bf.bottomMargin();
    }

    // Page count: the text's extent, grown to cover page-anchored objects (the
    // Mac's grow rule), floored at 1, capped at the format's safety limit.
    int pages = cursor.page + 1;
    for (const PlacedObject &object : m_objects)
        if (object.anchorMode() == PlacedObject::Anchor::Page && object.page)
            pages = std::max(pages, *object.page + 1);
    m_pageCount = std::clamp(pages, 1, DocumentModel::maximumPageCount());

    rebuildMarkers();

    m_inLayout = false;
    if (m_pageCount != oldPageCount) emit pageCountChanged(m_pageCount);
    const QSizeF newSize = documentSize();
    if (newSize != oldSize) emit documentSizeChanged(newSize);
    emit update(QRectF(QPointF(0, 0), newSize));
    emit layoutChanged();
}

void PageLayout::rebuildMarkers() {
    m_markers.clear();
    QTextDocument *doc = document();
    QVector<std::optional<ListItemModel>> items;
    QVector<QTextBlock> blocks;
    for (QTextBlock block = doc->begin(); block.isValid(); block = block.next()) {
        const QTextCharFormat bcf = block.charFormat();
        std::optional<ListItemModel> item;
        if (bcf.hasProperty(Props::ListItem))
            item = DocumentBridge::decodeListItem(bcf.stringProperty(Props::ListItem));
        items.append(item);
        blocks.append(block);
    }
    const auto resolved = ListMarkers::resolve(items);
    for (int i = 0; i < blocks.size(); ++i) {
        if (!resolved[i] || !items[i]) continue;
        QTextLayout *layout = blocks[i].layout();
        if (layout->lineCount() == 0) continue;
        const QTextLine first = layout->lineAt(0);
        const QPointF baselineRight(first.position().x() - ListGeometry::markerGap,
                                    first.position().y() + first.ascent());
        m_markers.append({blocks[i].blockNumber(), baselineRight, resolved[i]->text});
    }
}

void PageLayout::draw(QPainter *painter, const PaintContext &context) {
    QTextDocument *doc = document();
    for (QTextBlock block = doc->begin(); block.isValid(); block = block.next()) {
        const int number = block.blockNumber();
        if (number < m_blockBounds.size() && context.clip.isValid()
            && !m_blockBounds[number].intersects(context.clip.adjusted(-8, -8, 8, 8)))
            continue;

        QTextLayout *layout = block.layout();
        const int blockPos = block.position();
        const int blockLen = block.length();

        QVector<QTextLayout::FormatRange> ranges;
        for (const Selection &selection : context.selections) {
            const int selStart = selection.cursor.selectionStart() - blockPos;
            const int selEnd = selection.cursor.selectionEnd() - blockPos;
            if (selEnd <= 0 || selStart >= blockLen || selStart == selEnd) continue;
            QTextLayout::FormatRange range;
            range.start = std::max(0, selStart);
            range.length = std::min(blockLen, selEnd) - range.start;
            range.format = selection.format;
            ranges.append(range);
        }
        layout->draw(painter, QPointF(0, 0), ranges,
                     context.clip.isValid() ? context.clip : QRectF());

        if (context.cursorPosition >= blockPos
            && context.cursorPosition < blockPos + blockLen)
            layout->drawCursor(painter, QPointF(0, 0), context.cursorPosition - blockPos, 1);
    }

    // List markers, in each block's own font and color.
    for (const Marker &marker : m_markers) {
        const QTextBlock block = doc->findBlockByNumber(marker.blockNumber);
        if (!block.isValid()) continue;
        const QTextCharFormat bcf = block.charFormat();
        if (context.clip.isValid()
            && !context.clip.adjusted(-40, -40, 40, 40).contains(marker.baselineRight))
            continue;
        painter->save();
        painter->setFont(bcf.font());
        painter->setPen(bcf.foreground().style() == Qt::NoBrush
                            ? QColor(Qt::black) : bcf.foreground().color());
        const QFontMetricsF fm(bcf.font());
        painter->drawText(QPointF(marker.baselineRight.x()
                                      - fm.horizontalAdvance(marker.text),
                                  marker.baselineRight.y()),
                          marker.text);
        painter->restore();
    }
}

int PageLayout::hitTest(const QPointF &point, Qt::HitTestAccuracy accuracy) const {
    QTextDocument *doc = document();
    QTextBlock best;
    double bestDistance = std::numeric_limits<double>::max();

    for (QTextBlock block = doc->begin(); block.isValid(); block = block.next()) {
        const int number = block.blockNumber();
        if (number >= m_blockBounds.size()) break;
        const QRectF bounds = m_blockBounds[number];
        double distance = 0;
        if (point.y() < bounds.top()) distance = bounds.top() - point.y();
        else if (point.y() > bounds.bottom()) distance = point.y() - bounds.bottom();
        if (distance < bestDistance) {
            bestDistance = distance;
            best = block;
        }
    }
    if (!best.isValid()) return accuracy == Qt::ExactHit ? -1 : 0;
    if (accuracy == Qt::ExactHit && bestDistance > 1.0) return -1;

    const QTextLayout *layout = best.layout();
    QTextLine chosen;
    double bestLineDistance = std::numeric_limits<double>::max();
    for (int i = 0; i < layout->lineCount(); ++i) {
        const QTextLine line = layout->lineAt(i);
        const QRectF rect(line.position(), QSizeF(line.width(), line.height()));
        double distance = 0;
        if (point.y() < rect.top()) distance = rect.top() - point.y();
        else if (point.y() > rect.bottom()) distance = point.y() - rect.bottom();
        // Same-band segments: prefer the horizontally nearest one.
        if (point.x() < rect.left()) distance += (rect.left() - point.x()) / 1e6;
        else if (point.x() > rect.right()) distance += (point.x() - rect.right()) / 1e6;
        if (distance < bestLineDistance) {
            bestLineDistance = distance;
            chosen = line;
        }
    }
    if (!chosen.isValid()) return best.position();
    return best.position() + chosen.xToCursor(point.x());
}

QSizeF PageLayout::documentSize() const {
    return {m_page.width, m_pageCount * (m_page.height + pageGap) - pageGap};
}

QRectF PageLayout::frameBoundingRect(QTextFrame *frame) const {
    Q_UNUSED(frame);
    return QRectF(QPointF(0, 0), documentSize());
}

QRectF PageLayout::blockBoundingRect(const QTextBlock &block) const {
    const int number = block.blockNumber();
    if (number >= 0 && number < m_blockBounds.size()) return m_blockBounds[number];
    return {};
}

} // namespace lucerne
