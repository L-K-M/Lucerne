#pragma once

#include <QFont>
#include <QPaintDevice>

namespace lucerne::DocumentUnits {

inline constexpr double pointsPerInch = 72.0;
inline constexpr double metersPerInch = 0.0254;

// Direct text painting must use document points, not the target's DPI scale.
inline QFont fontForDevice(QFont font, const QPaintDevice &device) {
    if (font.pointSizeF() <= 0) return font;

    // DPI-less targets already use document units; avoid invalid scaling.
    const int logicalDpi = device.logicalDpiY();
    if (logicalDpi <= 0) return font;

    font.setPointSizeF(font.pointSizeF() * pointsPerInch / logicalDpi);
    return font;
}

} // namespace lucerne::DocumentUnits
