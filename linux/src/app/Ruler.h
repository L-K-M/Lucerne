#pragma once

// The horizontal ruler: unit-aware ticks over the writable column, draggable
// indent triangles, and tab-stop pennants — the Qt analogue of the Mac's
// LucerneRulerView, restyled with palette colors so it sits naturally in a
// Yaru/Adwaita window. Same interactions: click the band to add a tab, drag to
// move it, drag off the ruler to delete it, double-click to cycle its type
// (left → center → right → decimal), drag the triangles to set the selected
// paragraphs' indents.

#include "app/PageCanvas.h"

#include <QWidget>

namespace lucerne {

class Ruler : public QWidget {
    Q_OBJECT
public:
    enum class Unit { Centimeters, Inches };

    explicit Ruler(PageCanvas *canvas, QWidget *parent = nullptr);

    Unit unit() const { return m_unit; }
    void setUnit(Unit unit);

    QSize sizeHint() const override { return {100, 26}; }

signals:
    void statusMessage(const QString &message);

protected:
    void paintEvent(QPaintEvent *event) override;
    void mousePressEvent(QMouseEvent *event) override;
    void mouseMoveEvent(QMouseEvent *event) override;
    void mouseReleaseEvent(QMouseEvent *event) override;
    void mouseDoubleClickEvent(QMouseEvent *event) override;

private:
    enum class DragTarget { None, LeftIndent, FirstLineIndent, RightIndent, Tab };

    // Document x (points from page left) ↔ widget x, tracking canvas scroll/zoom.
    double toWidgetX(double documentX) const;
    double fromWidgetX(double widgetX) const;
    QTextBlockFormat currentBlockFormat() const;
    QVector<TabStopModel> currentTabs() const;
    void beginCoalescedEdit(QTextCursor &cursor);
    void applyTabs(const QVector<TabStopModel> &tabs);
    void applyIndent(std::optional<double> left, std::optional<double> right,
                     std::optional<double> firstLine);

    PageCanvas *m_canvas;
    Unit m_unit = Unit::Centimeters;

    DragTarget m_drag = DragTarget::None;
    int m_dragTabIndex = -1;
    bool m_dragTabRemoving = false;
    QVector<TabStopModel> m_dragTabs;
    int m_dragEdits = 0;   // block-format edits in the current gesture
};

} // namespace lucerne
