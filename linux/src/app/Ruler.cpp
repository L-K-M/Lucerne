#include "app/Ruler.h"

#include <QMouseEvent>
#include <QPainter>
#include <QPainterPath>
#include <QTextBlock>

#include <cmath>

namespace lucerne {

namespace {
constexpr double hitTolerance = 7;
constexpr double markerHalf = 5;
}

Ruler::Ruler(PageCanvas *canvas, QWidget *parent) : QWidget(parent), m_canvas(canvas) {
    setMouseTracking(true);
    connect(canvas, &PageCanvas::zoomChanged, this, [this](double) { update(); });
    connect(canvas, &PageCanvas::viewScrolled, this, [this] { update(); });
    connect(canvas, &PageCanvas::cursorChanged, this, [this] { update(); });
}

void Ruler::setUnit(Unit unit) {
    if (m_unit == unit) return;
    m_unit = unit;
    update();
}

double Ruler::toWidgetX(double documentX) const {
    const double viewportLeft =
        m_canvas->viewport()->mapTo(window(), QPoint(0, 0)).x()
        - mapTo(window(), QPoint(0, 0)).x();
    return viewportLeft + m_canvas->canvasToViewport(QPointF(documentX, 0)).x();
}

double Ruler::fromWidgetX(double widgetX) const {
    const double viewportLeft =
        m_canvas->viewport()->mapTo(window(), QPoint(0, 0)).x()
        - mapTo(window(), QPoint(0, 0)).x();
    return m_canvas->viewportToCanvas(QPointF(widgetX - viewportLeft, 0)).x();
}

QTextBlockFormat Ruler::currentBlockFormat() const {
    return m_canvas->textCursor().blockFormat();
}

QVector<TabStopModel> Ruler::currentTabs() const {
    QVector<TabStopModel> tabs;
    for (const QTextOption::Tab &tab : currentBlockFormat().tabPositions()) {
        QString type = QStringLiteral("left");
        switch (tab.type) {
        case QTextOption::CenterTab: type = QStringLiteral("center"); break;
        case QTextOption::RightTab: type = QStringLiteral("right"); break;
        case QTextOption::DelimiterTab: type = QStringLiteral("decimal"); break;
        default: break;
        }
        tabs.append({tab.position, type});
    }
    return tabs;
}

void Ruler::beginCoalescedEdit(QTextCursor &cursor) {
    // Every application during one drag joins the previous one, so a whole
    // indent/tab drag is a single undo step instead of one per mouse-move.
    if (m_dragEdits++ > 0)
        cursor.joinPreviousEditBlock();
    else
        cursor.beginEditBlock();
}

void Ruler::applyTabs(const QVector<TabStopModel> &tabs) {
    QList<QTextOption::Tab> list;
    for (const TabStopModel &stop : tabs) {
        QTextOption::Tab tab;
        tab.position = stop.pos;
        if (stop.type == QLatin1String("center")) tab.type = QTextOption::CenterTab;
        else if (stop.type == QLatin1String("right")) tab.type = QTextOption::RightTab;
        else if (stop.type == QLatin1String("decimal")) tab.type = QTextOption::DelimiterTab;
        else tab.type = QTextOption::LeftTab;
        if (tab.type == QTextOption::DelimiterTab)
            tab.delimiter = QLocale().decimalPoint().isEmpty()
                ? QLatin1Char('.') : QLocale().decimalPoint().at(0);
        list.append(tab);
    }
    QTextBlockFormat format;
    format.setTabPositions(list);
    QTextCursor cursor = m_canvas->textCursor();
    beginCoalescedEdit(cursor);
    cursor.mergeBlockFormat(format);
    cursor.endEditBlock();
    update();
}

void Ruler::applyIndent(std::optional<double> left, std::optional<double> right,
                        std::optional<double> firstLine) {
    QTextBlockFormat format;
    if (left) format.setLeftMargin(std::max(0.0, *left));
    if (right) format.setRightMargin(std::max(0.0, *right));
    if (firstLine) format.setTextIndent(*firstLine);
    QTextCursor cursor = m_canvas->textCursor();
    beginCoalescedEdit(cursor);
    cursor.mergeBlockFormat(format);
    cursor.endEditBlock();
    update();
}

void Ruler::paintEvent(QPaintEvent *) {
    QPainter painter(this);
    painter.setRenderHint(QPainter::Antialiasing, true);

    const QColor windowColor = palette().color(QPalette::Window);
    painter.fillRect(rect(), windowColor);

    const PageConfig &page = m_canvas->editor()->model().page;
    auto x = [&](double documentX) { return toWidgetX(documentX); };

    const double left = x(0);
    const double marginLeft = x(page.margins.left);
    const double marginRight = x(page.width - page.margins.right);
    const double rightEdge = x(page.width);
    const double h = height();

    // The page's footprint, with the writable column highlighted.
    const bool dark = windowColor.lightness() < 128;
    painter.fillRect(QRectF(left, 0, rightEdge - left, h - 1),
                     dark ? windowColor.lighter(112) : windowColor.darker(104));
    painter.fillRect(QRectF(marginLeft, 0, marginRight - marginLeft, h - 1),
                     palette().color(QPalette::Base));

    // Unit ticks, rising from the bottom; labelled every whole unit.
    const double pointsPerUnit = m_unit == Unit::Centimeters ? 72.0 / 2.54 : 72.0;
    const int subdivisions = m_unit == Unit::Centimeters ? 4 : 8;
    const QColor tick = palette().color(QPalette::Mid);
    QFont labelFont = font();
    labelFont.setPointSizeF(7);
    painter.setFont(labelFont);
    const double contentWidth = page.width - page.margins.left - page.margins.right;
    for (int unitIndex = 0; unitIndex * pointsPerUnit <= contentWidth; ++unitIndex) {
        const double base = unitIndex * pointsPerUnit;
        for (int sub = 0; sub < subdivisions; ++sub) {
            const double documentX = page.margins.left + base
                + sub * pointsPerUnit / subdivisions;
            if (documentX > page.width - page.margins.right + 0.5) break;
            double tickHeight = 4;
            if (sub == 0) tickHeight = 9;
            else if (subdivisions % 2 == 0 && sub == subdivisions / 2) tickHeight = 6;
            painter.setPen(QPen(tick, 1));
            const double wx = x(documentX);
            painter.drawLine(QPointF(wx, h - 2 - tickHeight), QPointF(wx, h - 2));
        }
        if (unitIndex > 0) {
            painter.setPen(palette().color(QPalette::Text));
            painter.drawText(QRectF(x(page.margins.left + base) - 20, 1, 40, 10),
                             Qt::AlignCenter, QString::number(unitIndex));
        }
    }
    painter.setPen(QPen(tick, 1));
    painter.drawLine(QPointF(0, h - 1), QPointF(width(), h - 1));

    // Indent triangles (accent-tinted) + tab pennants for the caret paragraph.
    const QTextBlockFormat bf = currentBlockFormat();
    const QColor accent = palette().color(QPalette::Highlight);
    auto triangle = [&](double wx, bool pointsDown) {
        QPainterPath path;
        if (pointsDown) {
            path.moveTo(wx - markerHalf, 1);
            path.lineTo(wx + markerHalf, 1);
            path.lineTo(wx, 1 + markerHalf * 1.6);
        } else {
            path.moveTo(wx - markerHalf, h - 2);
            path.lineTo(wx + markerHalf, h - 2);
            path.lineTo(wx, h - 2 - markerHalf * 1.6);
        }
        path.closeSubpath();
        painter.fillPath(path, accent);
    };
    triangle(x(page.margins.left + bf.leftMargin() + bf.textIndent()), true);
    triangle(x(page.margins.left + bf.leftMargin()), false);
    triangle(x(page.width - page.margins.right - bf.rightMargin()), false);

    painter.setPen(Qt::NoPen);
    painter.setBrush(palette().color(QPalette::Text));
    for (const TabStopModel &tab : currentTabs()) {
        const double wx = x(page.margins.left + tab.pos);
        painter.drawRect(QRectF(wx - 1, 3, 2, 9));
        if (tab.type == QLatin1String("left"))
            painter.drawRect(QRectF(wx - 1, 10, 7, 2));
        else if (tab.type == QLatin1String("right"))
            painter.drawRect(QRectF(wx - 5, 10, 7, 2));
        else
            painter.drawRect(QRectF(wx - 5, 10, 10, 2));
        if (tab.type == QLatin1String("decimal"))
            painter.drawRect(QRectF(wx + 3, 5, 3, 3));
    }
}

void Ruler::mousePressEvent(QMouseEvent *event) {
    m_dragEdits = 0;
    const PageConfig &page = m_canvas->editor()->model().page;
    const double documentX = fromWidgetX(event->position().x());
    const double fromMargin = documentX - page.margins.left;
    const QTextBlockFormat bf = currentBlockFormat();
    const double contentWidth = page.width - page.margins.left - page.margins.right;

    auto near = [&](double a, double b) {
        return std::abs(a - b) * m_canvas->zoom() <= hitTolerance;
    };

    // Upper half: first-line indent; lower half: left/right indents, then tabs.
    if (event->position().y() < height() / 2.0) {
        if (near(fromMargin, bf.leftMargin() + bf.textIndent())) {
            m_drag = DragTarget::FirstLineIndent;
            return;
        }
    } else {
        if (near(fromMargin, bf.leftMargin())) {
            m_drag = DragTarget::LeftIndent;
            return;
        }
        if (near(fromMargin, contentWidth - bf.rightMargin())) {
            m_drag = DragTarget::RightIndent;
            return;
        }
    }
    m_dragTabs = currentTabs();
    for (int i = 0; i < m_dragTabs.size(); ++i) {
        if (near(fromMargin, m_dragTabs[i].pos)) {
            m_drag = DragTarget::Tab;
            m_dragTabIndex = i;
            m_dragTabRemoving = false;
            return;
        }
    }
    // Click on empty band: create a left tab there and start dragging it.
    if (fromMargin >= 0 && fromMargin <= contentWidth) {
        m_dragTabs.append({std::round(fromMargin), QStringLiteral("left")});
        m_drag = DragTarget::Tab;
        m_dragTabIndex = int(m_dragTabs.size()) - 1;
        m_dragTabRemoving = false;
        applyTabs(m_dragTabs);
    }
}

void Ruler::mouseMoveEvent(QMouseEvent *event) {
    const PageConfig &page = m_canvas->editor()->model().page;
    const double contentWidth = page.width - page.margins.left - page.margins.right;
    const double documentX = fromWidgetX(event->position().x());
    const double fromMargin = std::clamp(documentX - page.margins.left, 0.0, contentWidth);
    const QTextBlockFormat bf = currentBlockFormat();

    switch (m_drag) {
    case DragTarget::None:
        emit statusMessage(tr("Ruler — drag the triangles for indents; click the white "
                              "band to add a tab stop, double-click a tab to change its "
                              "type, drag it off the ruler to delete"));
        return;
    case DragTarget::LeftIndent:
        applyIndent(std::min(fromMargin, contentWidth - bf.rightMargin() - 12),
                    std::nullopt, std::nullopt);
        return;
    case DragTarget::FirstLineIndent:
        applyIndent(std::nullopt, std::nullopt, fromMargin - bf.leftMargin());
        return;
    case DragTarget::RightIndent:
        applyIndent(std::nullopt,
                    std::min(contentWidth - fromMargin,
                             contentWidth - bf.leftMargin() - 12),
                    std::nullopt);
        return;
    case DragTarget::Tab: {
        if (m_dragTabIndex < 0 || m_dragTabIndex >= m_dragTabs.size()) return;
        m_dragTabRemoving = event->position().y() < -hitTolerance
            || event->position().y() > height() + hitTolerance;
        m_dragTabs[m_dragTabIndex].pos = std::round(fromMargin);
        QVector<TabStopModel> effective = m_dragTabs;
        if (m_dragTabRemoving) effective.remove(m_dragTabIndex);
        applyTabs(effective);
        return;
    }
    }
}

void Ruler::mouseReleaseEvent(QMouseEvent *event) {
    Q_UNUSED(event);
    if (m_drag == DragTarget::Tab && m_dragTabRemoving
        && m_dragTabIndex >= 0 && m_dragTabIndex < m_dragTabs.size()) {
        m_dragTabs.remove(m_dragTabIndex);
        applyTabs(m_dragTabs);
    }
    m_drag = DragTarget::None;
    m_dragTabIndex = -1;
    m_dragTabRemoving = false;
    m_dragEdits = 0;
}

void Ruler::mouseDoubleClickEvent(QMouseEvent *event) {
    m_dragEdits = 0;
    const PageConfig &page = m_canvas->editor()->model().page;
    const double fromMargin = fromWidgetX(event->position().x()) - page.margins.left;
    QVector<TabStopModel> tabs = currentTabs();
    for (TabStopModel &tab : tabs) {
        if (std::abs(tab.pos - fromMargin) * m_canvas->zoom() > hitTolerance) continue;
        // left → center → right → decimal → left
        if (tab.type == QLatin1String("left")) tab.type = QStringLiteral("center");
        else if (tab.type == QLatin1String("center")) tab.type = QStringLiteral("right");
        else if (tab.type == QLatin1String("right")) tab.type = QStringLiteral("decimal");
        else tab.type = QStringLiteral("left");
        applyTabs(tabs);
        return;
    }
}

} // namespace lucerne
