#pragma once

#include <QString>

namespace lucerne {

class Editor;

namespace PdfExport {

/// Replace the destination only after every page is written successfully.
bool writeFile(const Editor &editor, const QString &path, QString *error = nullptr);

} // namespace PdfExport
} // namespace lucerne
