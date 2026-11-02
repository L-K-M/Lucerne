#include "app/PdfExport.h"
#include "app/Editor.h"

#include <QPageSize>
#include <QPainter>
#include <QPdfWriter>
#include <QSaveFile>

namespace lucerne {
namespace {

constexpr int pointsPerInch = 72;

bool renderPages(const Editor &editor, QIODevice *device, QString *error) {
    const PageConfig &page = editor.model().page;
    QPdfWriter writer(device);
    writer.setPageSize(QPageSize(QSizeF(page.width, page.height), QPageSize::Point,
                                 QString(), QPageSize::ExactMatch));
    writer.setPageMargins(QMarginsF(0, 0, 0, 0));
    writer.setResolution(pointsPerInch);
    writer.setTitle(editor.displayName());

    QPainter painter;
    if (!painter.begin(&writer)) {
        if (error) *error = QObject::tr("The PDF could not be started.");
        return false;
    }
    for (int i = 0; i < editor.layout()->pageCount(); ++i) {
        if (i > 0 && !writer.newPage()) {
            if (error) *error = QObject::tr("A PDF page could not be written.");
            return false;
        }
        editor.renderPage(&painter, i);
    }
    if (!painter.end()) {
        if (error) *error = QObject::tr("The PDF could not be completed.");
        return false;
    }
    return true;
}

} // namespace

bool PdfExport::write(const Editor &editor, const QString &path, QString *error) {
    QSaveFile file(path);
    if (!file.open(QIODevice::WriteOnly)) {
        if (error) *error = file.errorString();
        return false;
    }
    // Destroy the PDF writer before commit so its final writes stay transactional.
    if (!renderPages(editor, &file, error)) {
        file.cancelWriting();
        return false;
    }
    if (!file.commit()) {
        if (error) *error = file.errorString();
        return false;
    }
    return true;
}

} // namespace lucerne
