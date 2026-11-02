#include "app/DocumentBridge.h"
#include "app/Editor.h"
#include "core/DefaultDocuments.h"

#include <QFontMetricsF>
#include <QImage>
#include <QPainter>
#include <QTextBlock>
#include <QtTest>

#include <cmath>
#include <cstring>

using namespace lucerne;

namespace {

constexpr double pointsPerInch = 72.0;
constexpr double metersPerInch = 0.0254;

QImage imageAtDpi(const QSize &size, double dpi) {
    QImage image(size, QImage::Format_ARGB32_Premultiplied);
    const int dotsPerMeter = qRound(dpi / metersPerInch);
    image.setDotsPerMeterX(dotsPerMeter);
    image.setDotsPerMeterY(dotsPerMeter);
    image.fill(Qt::white);
    return image;
}

DocumentModel letter() {
    DocumentModel model = DefaultDocuments::empty();
    model.styles["body"].font = QStringLiteral("DejaVu Sans");
    model.styles["body"].size = 12.5;
    model.body.first().runs = {Run{QStringLiteral("MMMMMMMM")}};
    return model;
}

bool rendersIdenticallyAcrossDpis(const Editor &editor) {
    const PageConfig &page = editor.model().page;
    const QSize size(qCeil(page.width), qCeil(page.height));
    QImage pointImage = imageAtDpi(size, pointsPerInch);
    QImage highDpiImage = imageAtDpi(size, 2 * pointsPerInch);
    for (QImage *image : {&pointImage, &highDpiImage}) {
        QPainter painter(image);
        editor.renderPage(&painter, 0);
    }
    return pointImage.sizeInBytes() == highDpiImage.sizeInBytes()
        && std::memcmp(pointImage.constBits(), highDpiImage.constBits(),
                       size_t(pointImage.sizeInBytes())) == 0;
}

} // namespace

class tst_document_units : public QObject {
    Q_OBJECT

private slots:
    void textLayoutUsesDocumentPoints() {
        Editor editor;
        const DocumentModel model = letter();
        editor.loadModel(model, {});
        const QTextLine line = editor.document()->begin().layout()->lineAt(0);
        QVERIFY(line.isValid());

        QImage device = imageAtDpi(QSize(1, 1), pointsPerInch);
        const QFont font = DocumentBridge::displayFont("DejaVu Sans", 12.5, false, false);
        const QFontMetricsF metrics(font, &device);
        const double expected = metrics.horizontalAdvance(model.body.first().plainText());
        QVERIFY2(std::abs(line.naturalTextWidth() - expected) < 0.01,
                 "font metrics must use 72-DPI points, not screen pixels");

        const DocumentModel snapshot = editor.snapshotModel();
        QCOMPARE(snapshot.styles["body"].size, std::optional<double>(12.5));
        QVERIFY(!snapshot.body.first().runs.first().size);
    }

    void furnitureAndMarkersUseTheSameUnitsAtAnyDpi() {
        DocumentModel model = letter();
        PageFurniture header;
        header.left = QStringLiteral("Header");
        model.header = header;
        PageFurniture footer;
        footer.right = QStringLiteral("Footer");
        model.footer = footer;
        ListItemModel item;
        item.list = "L";
        item.ordered = true;
        item.marker = "decimal";
        model.body.first().list = item;
        Editor editor;
        editor.loadModel(model, {});

        QVERIFY2(rendersIdenticallyAcrossDpis(editor),
                 "page text, furniture and markers must not change with device DPI");
    }

    void imagePlaceholderUsesDocumentUnits() {
        DocumentModel model = letter();
        PlacedObject object;
        object.id = "missing";
        object.page = 0;
        object.frame = RectModel{100, 200, 100, 50};
        object.src = QStringLiteral("images/missing.png");
        model.objects = {object};
        Editor editor;
        editor.loadModel(model, {});

        QVERIFY2(rendersIdenticallyAcrossDpis(editor),
                 "image placeholders must not inherit an unscaled ambient font");
    }
};

QTEST_MAIN(tst_document_units)
#include "tst_document_units.moc"
