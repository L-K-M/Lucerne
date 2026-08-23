// The paginated exclusion-flow layout engine — the port's risk center
// (docs/ubuntu-port.md Phase 1 step 1: "one page of editable text … with a
// draggable rectangle that text flows around live … then across a page
// boundary"). Headless (offscreen QPA): real fonts, real shaping.

#include "app/DocumentBridge.h"
#include "app/PageLayout.h"
#include "core/DefaultDocuments.h"

#include <QTextBlock>
#include <QTextDocument>
#include <QtTest>

#include <cmath>

using namespace lucerne;

namespace {

DocumentModel longDocument(int paragraphs) {
    DocumentModel model;
    model.page = PageConfig::a4();
    model.styles = DefaultDocuments::defaultStyles();
    for (int i = 0; i < paragraphs; ++i) {
        Paragraph p;
        p.id = QStringLiteral("p%1").arg(i);
        p.style = QStringLiteral("body");
        p.runs.append(Run{QStringLiteral(
            "Paragraph %1: lorem ipsum dolor sit amet, consectetur adipiscing "
            "elit, sed do eiusmod tempor incididunt ut labore et dolore magna "
            "aliqua ut enim ad minim veniam quis nostrud exercitation.").arg(i)});
        model.body.append(p);
    }
    return model;
}

struct Editor {
    QTextDocument doc;
    PageLayout *layout;   // owned by doc

    explicit Editor(const DocumentModel &model) {
        layout = new PageLayout(&doc);
        doc.setDocumentLayout(layout);
        layout->setPage(model.page);
        DocumentBridge::build(&doc, model);
        layout->setObjects(model.objects);
    }

    // Every laid-out line rect, canvas coordinates.
    QVector<QRectF> lineRects() const {
        QVector<QRectF> rects;
        for (QTextBlock block = doc.begin(); block.isValid(); block = block.next()) {
            QTextLayout *l = block.layout();
            for (int i = 0; i < l->lineCount(); ++i) {
                const QTextLine line = l->lineAt(i);
                rects.append(QRectF(line.position(), QSizeF(line.width(), line.height())));
            }
        }
        return rects;
    }
};

} // namespace

class tst_layout : public QObject {
    Q_OBJECT

private slots:
    void shortDocumentIsOnePage() {
        Editor e(longDocument(2));
        QCOMPARE(e.layout->pageCount(), 1);
        // Text starts inside the margins.
        const QVector<QRectF> rects = e.lineRects();
        QVERIFY(!rects.isEmpty());
        QVERIFY(std::abs(rects.first().topLeft().x() - 72.0) < 1.0 / 32);
        QVERIFY(std::abs(rects.first().topLeft().y() - 72.0) < 1.0 / 32);
    }

    void longDocumentPaginates() {
        Editor e(longDocument(60));
        QVERIFY2(e.layout->pageCount() >= 2,
                 qPrintable(QString::number(e.layout->pageCount())));
        // No line may sit inside a bottom margin or the inter-page gap: every
        // line's band must fall inside some page's text area.
        for (const QRectF &rect : e.lineRects()) {
            const int page = e.layout->pageIndexForPoint(rect.center());
            const QRectF area = e.layout->textAreaRect(page);
            QVERIFY2(rect.top() >= area.top() - 0.5 && rect.bottom() <= area.bottom() + 0.5,
                     qPrintable(QStringLiteral("line %1..%2 outside text area %3..%4")
                                    .arg(rect.top()).arg(rect.bottom())
                                    .arg(area.top()).arg(area.bottom())));
        }
    }

    void exclusionRectPushesTextAside() {
        DocumentModel model = longDocument(6);
        PlacedObject image;
        image.id = "img";
        image.page = 0;
        // Mid-column so BOTH side gaps are wide enough to keep text (no
        // minColumn snapping): x 200..350 inside a 72..523 text column.
        image.frame = RectModel{200, 200, 150, 150};
        image.standoff = 12;
        model.objects.append(image);
        Editor e(model);

        // The exclusion zone (frame + standoff) must contain no text.
        const QRectF forbidden(200 - 12, 200 - 12, 150 + 24, 150 + 24);
        bool sawLeftNeighbor = false, sawRightNeighbor = false;
        for (const QRectF &rect : e.lineRects()) {
            QVERIFY2(!rect.intersects(forbidden),
                     qPrintable(QStringLiteral("line %1,%2 %3x%4 intersects the exclusion")
                                    .arg(rect.x()).arg(rect.y())
                                    .arg(rect.width()).arg(rect.height())));
            if (rect.top() >= forbidden.top() && rect.bottom() <= forbidden.bottom()) {
                if (rect.right() <= forbidden.left() + 0.5) sawLeftNeighbor = true;
                if (rect.left() >= forbidden.right() - 0.5) sawRightNeighbor = true;
            }
        }
        // Text flows on BOTH sides of a mid-column obstacle.
        QVERIFY(sawLeftNeighbor);
        QVERIFY(sawRightNeighbor);
    }

    void draggingTheImageReflowsLive() {
        DocumentModel model = longDocument(6);
        PlacedObject image;
        image.id = "img";
        image.page = 0;
        image.frame = RectModel{200, 200, 150, 150};
        model.objects.append(image);
        Editor e(model);
        const QVector<QRectF> before = e.lineRects();

        // Drag the image lower: the exclusion moves, so lines must re-place.
        model.objects[0].frame = RectModel{200, 420, 150, 150};
        e.layout->setObjects(model.objects);
        const QVector<QRectF> after = e.lineRects();
        QVERIFY(before != after);
        const QRectF forbidden(200 - 12, 420 - 12, 150 + 24, 150 + 24);
        for (const QRectF &rect : after) QVERIFY(!rect.intersects(forbidden));

        // And unchanged exclusions must NOT trigger a reflow (dirty-check).
        // Observe relayout ACTIVITY, not output — a redundant full re-layout
        // would reproduce identical rects, so only the update() emission that
        // relayoutFromBlock always ends with can betray it.
        QSignalSpy spy(e.layout, &QAbstractTextDocumentLayout::update);
        e.layout->setObjects(model.objects);
        QCOMPARE(e.lineRects(), after);
        QCOMPARE(spy.count(), 0);
    }

    void wrapNoneOverlaysWithoutReflow() {
        DocumentModel model = longDocument(4);
        PlacedObject overlay;
        overlay.id = "img";
        overlay.page = 0;
        overlay.frame = RectModel{200, 200, 150, 150};
        overlay.wrap = QStringLiteral("none");
        Editor plain(model);
        const QVector<QRectF> before = plain.lineRects();
        model.objects.append(overlay);
        Editor with(model);
        QCOMPARE(with.lineRects(), before);
    }

    void narrowSliverSnapsToMargin() {
        DocumentModel model = longDocument(6);
        PlacedObject image;
        image.id = "img";
        image.page = 0;
        // 30 pt from the left margin: below minColumn, so no text on the left.
        image.frame = RectModel{72 + 30, 200, 150, 150};
        image.standoff = 0;
        model.objects.append(image);
        Editor e(model);
        for (const QRectF &rect : e.lineRects()) {
            if (rect.bottom() <= 200 || rect.top() >= 350) continue;
            QVERIFY2(rect.left() >= 72 + 30 + 150 - 0.5,
                     qPrintable(QStringLiteral("line at x %1 flowed into the sliver")
                                    .arg(rect.left())));
        }
    }

    void imageAcrossPageBoundaryFlowsOnItsPageOnly() {
        DocumentModel model = longDocument(60);
        PlacedObject image;
        image.id = "img";
        image.page = 1;
        image.frame = RectModel{150, 300, 200, 150};
        model.objects.append(image);
        Editor e(model);
        QVERIFY(e.layout->pageCount() >= 2);
        const QRectF forbiddenOnPage1 =
            QRectF(150 - 12, 300 - 12, 224, 174).translated(0, e.layout->pageRect(1).top());
        for (const QRectF &rect : e.lineRects()) {
            if (e.layout->pageIndexForPoint(rect.center()) == 1)
                QVERIFY(!rect.intersects(forbiddenOnPage1));
        }
    }

    void pageAnchoredObjectGrowsThePageCount() {
        DocumentModel model = longDocument(2);
        PlacedObject image;
        image.id = "img";
        image.page = 3;
        image.frame = RectModel{100, 100, 100, 100};
        model.objects.append(image);
        Editor e(model);
        QCOMPARE(e.layout->pageCount(), 4);
    }

    void pageBreakBeforeStartsANewPage() {
        DocumentModel model = longDocument(3);
        model.body[2].pageBreakBefore = true;
        Editor e(model);
        QCOMPARE(e.layout->pageCount(), 2);
        // Block 2's first line sits at the top of page 2's text area (within
        // QTextLine's 1/64-px QFixed precision).
        const QTextBlock block = e.doc.findBlockByNumber(2);
        const QTextLine first = block.layout()->lineAt(0);
        QVERIFY(std::abs(first.position().y() - e.layout->textAreaRect(1).top()) < 1.0 / 32);
    }

    void hitTestRoundTripsThroughLines() {
        Editor e(longDocument(10));
        for (QTextBlock block = e.doc.begin(); block.isValid(); block = block.next()) {
            const QTextLine line = block.layout()->lineAt(0);
            const QPointF probe = line.position() + QPointF(2, line.height() / 2);
            const int hit = e.layout->hitTest(probe, Qt::FuzzyHit);
            QVERIFY(hit >= block.position() && hit < block.position() + block.length());
        }
    }

    void listItemsGetGutterAndMarkers() {
        DocumentModel model = longDocument(1);
        Paragraph item;
        item.id = "l1";
        item.style = "body";
        item.runs.append(Run{QStringLiteral("First item")});
        ListItemModel descriptor;
        descriptor.list = "L";
        descriptor.ordered = true;
        descriptor.marker = QStringLiteral("decimal");
        item.list = descriptor;
        model.body.append(item);
        Editor e(model);
        QCOMPARE(e.layout->listMarkers().size(), 1);
        QCOMPARE(e.layout->listMarkers().first().text, QStringLiteral("1."));
        // The item's text is indented by the level-0 gutter (24 pt).
        const QTextBlock block = e.doc.findBlockByNumber(1);
        QVERIFY(std::abs(block.layout()->lineAt(0).position().x() - (72.0 + 24.0))
                < 1.0 / 32);
    }

    void typingReflowsIncrementallyAndConsistently() {
        DocumentModel model = longDocument(20);
        Editor e(model);
        // Append text into the middle block, then verify a from-scratch layout
        // of the same content agrees (partial relayout must not drift).
        QTextCursor cursor(&e.doc);
        cursor.setPosition(e.doc.findBlockByNumber(10).position());
        cursor.insertText(QStringLiteral("Inserted words change the flow. "));
        const QVector<QRectF> incremental = e.lineRects();
        const int pages = e.layout->pageCount();

        DocumentModel rebuilt = model;
        rebuilt.body[10].runs.first().text.prepend(
            QStringLiteral("Inserted words change the flow. "));
        Editor fresh(rebuilt);
        QCOMPARE(fresh.layout->pageCount(), pages);
        QCOMPARE(fresh.lineRects(), incremental);
    }
};

QTEST_MAIN(tst_layout)
#include "tst_layout.moc"
