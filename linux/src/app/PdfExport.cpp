#include "app/PdfExport.h"
#include "app/Editor.h"

#include <QPageSize>
#include <QPainter>
#include <QPdfWriter>
#include <QSaveFile>

namespace lucerne {
namespace PdfExport {

namespace {

class PdfFile final : public QSaveFile {
public:
    using QSaveFile::QSaveFile;

private:
    qint64 writeData(const char *data, qint64 size) override {
        const qint64 written = QSaveFile::writeData(data, size);
        if (written == size) return written;

        // QPdfWriter ignores short writes; make them abort the replacement.
        cancelWriting();
        if (written >= 0)
            setErrorString(QObject::tr("The PDF could not be written completely. "
                                      "Check available storage."));
        return -1;
    }
};

} // namespace

bool writeFile(const Editor &editor, const QString &path, QString *error) {
    auto fail = [&](const QString &message) {
        if (error) *error = message;
        return false;
    };

    PdfFile file(path);
    // Expose short writes before commit rather than hiding them in a buffer.
    if (!file.open(QIODevice::WriteOnly | QIODevice::Unbuffered))
        return fail(file.errorString());

    // Finalize the writer before committing; partial output must not replace a PDF.
    {
        const PageConfig &page = editor.model().page;
        constexpr int pointsPerInch = 72;
        QPdfWriter writer(&file);
        writer.setPageSize(QPageSize(QSizeF(page.width, page.height), QPageSize::Point,
                                     QString(), QPageSize::ExactMatch));
        writer.setPageMargins(QMarginsF(0, 0, 0, 0));
        writer.setResolution(pointsPerInch);
        writer.setTitle(editor.displayName());

        QPainter painter;
        if (!painter.begin(&writer))
            return fail(QObject::tr("The PDF could not be started."));

        const int pages = editor.layout()->pageCount();
        for (int i = 0; i < pages; ++i) {
            if (i > 0 && !writer.newPage())
                return fail(QObject::tr("A PDF page could not be written."));
            editor.renderPage(&painter, i);
        }
        if (!painter.end()) return fail(QObject::tr("The PDF could not be finished."));
    }

    if (file.error() != QFileDevice::NoError) return fail(file.errorString());
    if (!file.commit()) return fail(file.errorString());
    return true;
}

} // namespace PdfExport
} // namespace lucerne
