#pragma once

#include <QString>

namespace lucerne {
class Editor;

namespace PdfExport {
/// Replace the destination only after all pages and the PDF trailer are written.
bool write(const Editor &editor, const QString &path, QString *error);
}
} // namespace lucerne
