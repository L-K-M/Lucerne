#pragma once

// Derives `content.md` from the canonical model — the C++ mirror of Swift
// LucerneCore's MarkdownExporter.swift (spec §8). Write-only escape hatch:
// regenerated on every save, never read back as authority.

#include "core/Model.h"

#include <QString>

namespace lucerne {
namespace MarkdownExporter {

QString exportModel(const DocumentModel &model);

} // namespace MarkdownExporter
} // namespace lucerne
