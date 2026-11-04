#include "app/PdfExport.h"
#include "app/Editor.h"

#include <QCoreApplication>
#include <QPageSize>
#include <QPainter>
#include <QPdfWriter>
#include <QSaveFile>

namespace lucerne {
namespace {

constexpr int pointsPerInch = 72;

// QSaveFile that also refuses to commit after an incomplete write. In Qt 6.2
// through at least 6.8, commit() only aborts on an error recorded by writeData
// (later Qt checks the close too, but CI ships 6.2 and 6.4): a short write
// sets no error at all, and a failure in the final buffered flush inside
// commit() is recorded but never checked — either way the truncated temporary
// file would replace the destination. Opened Unbuffered, every write surfaces
// here instead, where a short or failed write arms the refusal via
// cancelWriting(). The real reason is kept separately because cancelWriting()
// rewrites errorString() to "Writing canceled by application".
class PdfSaveFile final : public QSaveFile {
public:
    using QSaveFile::QSaveFile;

    /// The write error that aborts this file; empty while every write succeeds.
    QString writeFailure() const { return m_writeFailure; }

private:
    qint64 writeData(const char *data, qint64 len) override {
        const qint64 written = QSaveFile::writeData(data, len);
        if (written == len)
            return written;
        if (m_writeFailure.isEmpty()) {
            m_writeFailure = written < 0 ? errorString() : QString();
            if (m_writeFailure.isEmpty())
                m_writeFailure = QCoreApplication::translate("PdfExport",
                    "Could not write the whole PDF. "
                    "Check that the disk has enough free space.");
        }
        cancelWriting();
        return -1;
    }

    QString m_writeFailure;
};

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
        if (error) *error = QCoreApplication::translate("PdfExport",
            "The PDF could not be started.");
        return false;
    }
    for (int i = 0; i < editor.layout()->pageCount(); ++i) {
        if (i > 0 && !writer.newPage()) {
            if (error) *error = QCoreApplication::translate("PdfExport",
                "A PDF page could not be written.");
            return false;
        }
        editor.renderPage(&painter, i);
    }
    if (!painter.end()) {
        if (error) *error = QCoreApplication::translate("PdfExport",
            "The PDF could not be completed.");
        return false;
    }
    return true;
}

} // namespace

bool PdfExport::write(const Editor &editor, const QString &path, QString *error) {
    PdfSaveFile file(path);
    if (!file.open(QIODevice::WriteOnly | QIODevice::Unbuffered)) {
        if (error) *error = file.errorString();
        return false;
    }
    // Destroy the PDF writer before commit so its final writes stay transactional.
    if (!renderPages(editor, &file, error)) {
        if (error && !file.writeFailure().isEmpty()) *error = file.writeFailure();
        file.cancelWriting();
        return false;
    }
    // QPdfWriter does not propagate device failures — a write that failed while
    // painting can still "finish", so the file's own state is the only reliable
    // signal. Surface the recorded reason: after cancelWriting(), errorString()
    // only reports "Writing canceled by application".
    QString failure = file.writeFailure();
    if (failure.isEmpty() && file.error() != QFileDevice::NoError)
        failure = file.errorString();
    if (!failure.isEmpty()) {
        if (error) *error = failure;
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
