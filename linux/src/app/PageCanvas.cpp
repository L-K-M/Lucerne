#include "app/PageCanvas.h"
#include "app/DocumentBridge.h"
#include "core/Furniture.h"

#include <QApplication>
#include <QBuffer>
#include <QClipboard>
#include <QDateTime>
#include <QGuiApplication>
#include <QMimeData>
#include <QPainter>
#include <QPaintEvent>
#include <QScrollBar>
#include <QStyleHints>
#include <QTextBlock>

#include <cmath>

namespace lucerne {

PageCanvas::PageCanvas(Editor *editor, QWidget *parent)
    : QAbstractScrollArea(parent), m_editor(editor), m_cursor(editor->document()) {
    setFocusPolicy(Qt::StrongFocus);
    setAttribute(Qt::WA_InputMethodEnabled, true);
    setMouseTracking(true);
    viewport()->setAttribute(Qt::WA_OpaquePaintEvent, true);
    horizontalScrollBar()->setSingleStep(20);
    verticalScrollBar()->setSingleStep(20);

    connect(m_editor->layout(), &PageLayout::layoutChanged, this, [this] {
        updateScrollBars();
        viewport()->update();
        emit viewScrolled();
    });
    connect(m_editor->layout(), &QAbstractTextDocumentLayout::update, this,
            [this](const QRectF &) { viewport()->update(); });
    connect(m_editor, &Editor::objectsChanged, this, [this] {
        // A deleted object must not stay "selected".
        if (!m_selectedObject.isEmpty() && !m_editor->objectById(m_selectedObject)) {
            m_selectedObject.clear();
            emit selectionStateChanged();
        }
        viewport()->update();
    });
    connect(m_editor, &Editor::pageSetupChanged, this, [this] {
        updateScrollBars();
        viewport()->update();
    });
    connect(m_editor->document(), &QTextDocument::contentsChanged, this, [this] {
        // Keep the caret's pending format in step while typing.
        refreshCurrentFormat();
        viewport()->update();
    });
    connect(m_editor, &Editor::undoCoalescingBreak, this, [this] {
        // A different format index stops QTextDocument merging the next
        // insertion into the pre-object-edit text command (undo ordering).
        static int salt = 0;
        m_currentFormat.setProperty(Props::MergeSalt, ++salt);
    });

    refreshCurrentFormat();
    restartCaretBlink();
}

// MARK: - Geometry

QSizeF PageCanvas::canvasSize() const {
    const QSizeF doc = m_editor->layout()->documentSize();
    return {doc.width() + 2 * canvasInset, doc.height() + 2 * canvasInset};
}

QPointF PageCanvas::canvasOrigin() const {
    const QSizeF size = canvasSize();
    const double deviceW = size.width() * m_zoom;
    const double ox = std::max((viewport()->width() - deviceW) / 2.0, 0.0)
        - horizontalScrollBar()->value() + canvasInset * m_zoom;
    const double oy = canvasInset * m_zoom - verticalScrollBar()->value();
    return {ox, oy};
}

QPointF PageCanvas::toCanvas(const QPointF &viewportPoint) const {
    return (viewportPoint - canvasOrigin()) / m_zoom;
}

QPointF PageCanvas::fromCanvas(const QPointF &canvasPoint) const {
    return canvasPoint * m_zoom + canvasOrigin();
}

void PageCanvas::updateScrollBars() {
    const QSizeF size = canvasSize();
    horizontalScrollBar()->setRange(
        0, std::max(0, int(size.width() * m_zoom) - viewport()->width()));
    horizontalScrollBar()->setPageStep(viewport()->width());
    verticalScrollBar()->setRange(
        0, std::max(0, int(size.height() * m_zoom) - viewport()->height()));
    verticalScrollBar()->setPageStep(viewport()->height());
}

QRectF PageCanvas::cursorRect(const QTextCursor &cursor) const {
    const QTextBlock block = cursor.block();
    const QTextLayout *layout = block.layout();
    if (layout->lineCount() == 0) return {};
    const int posInBlock = cursor.position() - block.position();
    QTextLine line = layout->lineForTextPosition(posInBlock);
    if (!line.isValid()) line = layout->lineAt(layout->lineCount() - 1);
    // cursorToX is layout-relative, which in this engine IS canvas-relative
    // (lines are positioned in canvas coordinates).
    const double x = line.cursorToX(posInBlock);
    return {x - 0.5, line.position().y(), 1.0, line.height()};
}

// MARK: - Painting

void PageCanvas::paintEvent(QPaintEvent *event) {
    QPainter painter(viewport());
    painter.setRenderHint(QPainter::Antialiasing, true);
    painter.setRenderHint(QPainter::SmoothPixmapTransform, true);

    // Desk background: theme-aware (the paper stays paper-white; the desk
    // around it follows the palette so dark mode looks at home).
    const QColor window = palette().color(QPalette::Window);
    const QColor desk = window.lightness() > 128 ? window.darker(125) : window.darker(105);
    painter.fillRect(event->rect(), desk);

    painter.translate(canvasOrigin());
    painter.scale(m_zoom, m_zoom);
    const QRectF visibleCanvas(toCanvas(QPointF(0, 0)),
                               toCanvas(QPointF(viewport()->width(), viewport()->height())));

    PageLayout *layout = m_editor->layout();
    const PageConfig &page = m_editor->model().page;
    const PageMetrics metrics = layout->metrics();

    const int pageCount = layout->pageCount();
    for (int i = 0; i < pageCount; ++i) {
        const QRectF sheet = layout->pageRect(i);
        if (!sheet.adjusted(-30, -30, 30, 30).intersects(visibleCanvas)) continue;

        // Soft shadow, then the sheet. Paper is always white: the document's
        // colors are calibrated against paper, not against the desk theme.
        painter.setPen(Qt::NoPen);
        painter.setBrush(QColor(0, 0, 0, 34));
        painter.drawRoundedRect(sheet.translated(0, 2.5).adjusted(-1, 0, 1, 3), 3, 3);
        painter.setBrush(QColor(0, 0, 0, 16));
        painter.drawRoundedRect(sheet.translated(0, 5).adjusted(-2.5, 0, 2.5, 6), 5, 5);
        painter.setBrush(Qt::white);
        painter.drawRect(sheet);
        painter.setPen(QPen(QColor(0, 0, 0, 40), 1.0 / m_zoom));
        painter.setBrush(Qt::NoBrush);
        painter.drawRect(sheet);

        // DIN 5008 fold marks in the outer left margin.
        if (page.foldMarks.value_or(false)) {
            painter.setPen(QPen(QColor(0, 0, 0, 64), 0.5));
            for (const double offset : PageMetrics::din5008FoldMarkOffsetsFromTop()) {
                if (offset < page.height)
                    painter.drawLine(QPointF(sheet.left() + 6, sheet.top() + offset),
                                     QPointF(sheet.left() + 18, sheet.top() + offset));
            }
        }

        // Header/footer furniture: three zones per band, Body face at 80%.
        const auto &model = m_editor->model();
        const bool hasHeader = model.header && !model.header->isEmpty();
        const bool hasFooter = model.footer && !model.footer->isEmpty();
        if (hasHeader || hasFooter) {
            const ParagraphStyle body =
                model.resolvedStyle(DocumentModel::defaultStyleRole());
            const double size =
                std::max(8.0, body.size.value_or(12.0) * 0.8);
            QFont font = DocumentBridge::displayFont(
                body.font.value_or(QStringLiteral("Helvetica")), size, false, false);
            painter.setFont(font);
            painter.setPen(QColor(0, 0, 0, 150));
            const QRectF textArea = layout->textAreaRect(i);
            auto drawBand = [&](const PageFurniture &furniture, const QRectF &band) {
                const QString left = m_editor->furnitureZoneText(furniture.left, i);
                const QString center = m_editor->furnitureZoneText(furniture.center, i);
                const QString right = m_editor->furnitureZoneText(furniture.right, i);
                if (!left.isEmpty())
                    painter.drawText(band, Qt::AlignLeft | Qt::AlignVCenter, left);
                if (!center.isEmpty())
                    painter.drawText(band, Qt::AlignHCenter | Qt::AlignVCenter, center);
                if (!right.isEmpty())
                    painter.drawText(band, Qt::AlignRight | Qt::AlignVCenter, right);
            };
            if (hasHeader)
                drawBand(*model.header, QRectF(textArea.left(), sheet.top(),
                                               textArea.width(), metrics.marginTop));
            if (hasFooter)
                drawBand(*model.footer,
                         QRectF(textArea.left(), sheet.bottom() - metrics.marginBottom,
                                textArea.width(), metrics.marginBottom));
        }
    }

    // Text (with selection + caret) across all pages in one pass.
    QAbstractTextDocumentLayout::PaintContext context;
    context.clip = visibleCanvas;
    context.palette = palette();
    context.palette.setColor(QPalette::Text, Qt::black);
    if (m_cursor.hasSelection()) {
        QAbstractTextDocumentLayout::Selection selection;
        selection.cursor = m_cursor;
        selection.format.setBackground(palette().brush(QPalette::Highlight));
        selection.format.setForeground(palette().brush(QPalette::HighlightedText));
        context.selections.append(selection);
    }
    context.cursorPosition =
        (hasFocus() && m_caretVisible && m_selectedObject.isEmpty() && m_preedit.isEmpty())
            ? m_cursor.position() : -1;
    layout->draw(&painter, context);

    // Floating images above the text (the Mac's subview order), z ascending.
    QVector<const PlacedObject *> sorted;
    for (const PlacedObject &object : m_editor->objects())
        if (object.anchorMode() == PlacedObject::Anchor::Page && object.page && object.frame)
            sorted.append(&object);
    std::stable_sort(sorted.begin(), sorted.end(),
                     [](const PlacedObject *a, const PlacedObject *b) { return a->z < b->z; });
    for (const PlacedObject *object : sorted) {
        const QRectF rect = objectCanvasRect(*object);
        if (!rect.intersects(visibleCanvas)) continue;
        const QImage image = m_editor->imageForObject(*object);
        if (image.isNull()) {
            painter.fillRect(rect, QColor(237, 237, 237));
            QPen pen(QColor(0, 0, 0, 90), 1);
            pen.setStyle(Qt::DashLine);
            painter.setPen(pen);
            painter.setBrush(Qt::NoBrush);
            painter.drawRect(rect.adjusted(1, 1, -1, -1));
            painter.setPen(QColor(0, 0, 0, 110));
            painter.drawText(rect, Qt::AlignCenter, tr("Image"));
        } else {
            painter.drawImage(rect, image);
        }
        if (object->id == m_selectedObject) {
            const QColor accent = palette().color(QPalette::Highlight);
            painter.setPen(QPen(accent, 2.0 / m_zoom));
            painter.setBrush(Qt::NoBrush);
            painter.drawRect(rect.adjusted(1 / m_zoom, 1 / m_zoom, -1 / m_zoom, -1 / m_zoom));
            const double h = handleSize();
            painter.setBrush(Qt::white);
            painter.setPen(QPen(accent, 1.0 / m_zoom));
            for (const QPointF corner : {rect.topLeft(), rect.topRight(),
                                         rect.bottomLeft(), rect.bottomRight()})
                painter.drawRect(QRectF(corner.x() - h / 2, corner.y() - h / 2, h, h));
        }
    }
}

// MARK: - Objects

QRectF PageCanvas::objectCanvasRect(const PlacedObject &object) const {
    const QRectF sheet = m_editor->layout()->pageRect(object.page.value_or(0));
    const RectModel frame = *object.frame;
    return {sheet.left() + frame.x, sheet.top() + frame.y, frame.width, frame.height};
}

const PlacedObject *PageCanvas::objectAt(const QPointF &canvasPoint) const {
    const PlacedObject *best = nullptr;
    for (const PlacedObject &object : m_editor->objects()) {
        if (object.anchorMode() != PlacedObject::Anchor::Page || !object.page
            || !object.frame)
            continue;
        if (!objectCanvasRect(object).contains(canvasPoint)) continue;
        if (!best || object.z >= best->z) best = &object;
    }
    return best;
}

double PageCanvas::handleSize() const {
    return std::clamp(9.0 / m_zoom, 6.0, 24.0);
}

int PageCanvas::handleAt(const QPointF &canvasPoint, const QRectF &rect) const {
    const double h = handleSize();
    const QPointF corners[4] = {rect.topLeft(), rect.topRight(), rect.bottomLeft(),
                                rect.bottomRight()};
    for (int i = 0; i < 4; ++i) {
        const QRectF handle(corners[i].x() - h, corners[i].y() - h, 2 * h, 2 * h);
        if (handle.contains(canvasPoint)) return i;
    }
    return -1;
}

void PageCanvas::selectObject(const QString &id) {
    if (m_selectedObject == id) return;
    m_selectedObject = id;
    emit selectionStateChanged();
    if (!id.isEmpty())
        emit statusMessage(tr("Image selected — drag to move · drag a corner to resize "
                              "(Shift for free aspect) · arrows to nudge · Delete to remove"));
    viewport()->update();
}

void PageCanvas::nudgeSelectedObject(double dx, double dy) {
    const PlacedObject *object = m_editor->objectById(m_selectedObject);
    if (!object || !object->frame || !object->page) return;
    const RectModel before = *object->frame;
    const int page = *object->page;
    RectModel frame = before;
    frame.x += dx;
    frame.y += dy;
    m_editor->previewObjectFrame(m_selectedObject, page, frame);
    m_editor->commitObjectFrame(m_selectedObject, page, before, tr("Move Image"));
}

void PageCanvas::deleteSelectedObject() {
    if (m_selectedObject.isEmpty()) return;
    const QString id = m_selectedObject;
    selectObject(QString());
    m_editor->deleteObject(id);
    setFocus();
}

// MARK: - Mouse

void PageCanvas::mousePressEvent(QMouseEvent *event) {
    setFocus();
    clearPreedit();
    if (event->button() != Qt::LeftButton) {
        QAbstractScrollArea::mousePressEvent(event);
        return;
    }
    const QPointF canvasPoint = toCanvas(event->position());
    m_dragMoved = false;
    m_lastMouseViewport = event->position().toPoint();

    // Resize handles of the already-selected image win over everything.
    if (!m_selectedObject.isEmpty()) {
        if (const PlacedObject *selected = m_editor->objectById(m_selectedObject)) {
            if (selected->frame && selected->page) {
                const QRectF rect = objectCanvasRect(*selected);
                const int handle = handleAt(canvasPoint, rect);
                if (handle >= 0) {
                    m_drag = DragMode::ImageResize;
                    m_dragHandle = handle;
                    m_dragStartCanvas = canvasPoint;
                    m_dragStartRect = rect;
                    m_dragStartPage = *selected->page;
                    m_dragStartFrame = *selected->frame;
                    return;
                }
            }
        }
    }

    if (const PlacedObject *hit = objectAt(canvasPoint)) {
        selectObject(hit->id);
        m_drag = DragMode::ImageMove;
        m_dragStartCanvas = canvasPoint;
        m_dragStartRect = objectCanvasRect(*hit);
        m_dragStartPage = *hit->page;
        m_dragStartFrame = *hit->frame;
        return;
    }

    // Text. Track double/triple clicks manually (triple = paragraph).
    selectObject(QString());
    const quint64 now = QDateTime::currentMSecsSinceEpoch();
    const bool multi = now - m_lastClickTime
            < quint64(QApplication::styleHints()->mouseDoubleClickInterval())
        && (event->position().toPoint() - m_lastClickPos).manhattanLength() < 6;
    m_clickCount = multi ? m_clickCount + 1 : 1;
    m_lastClickTime = now;
    m_lastClickPos = event->position().toPoint();

    const int position = m_editor->layout()->hitTest(canvasPoint, Qt::FuzzyHit);
    if (position >= 0) {
        if (m_clickCount >= 3) {
            m_cursor.setPosition(position);
            m_cursor.movePosition(QTextCursor::StartOfBlock);
            m_cursor.movePosition(QTextCursor::EndOfBlock, QTextCursor::KeepAnchor);
        } else if (event->modifiers() & Qt::ShiftModifier) {
            m_cursor.setPosition(position, QTextCursor::KeepAnchor);
        } else {
            m_cursor.setPosition(position);
        }
        m_drag = DragMode::Text;
        refreshCurrentFormat();
        restartCaretBlink();
        emit cursorChanged();
        emit selectionStateChanged();
        viewport()->update();
    }
}

void PageCanvas::mouseMoveEvent(QMouseEvent *event) {
    const QPointF canvasPoint = toCanvas(event->position());
    m_lastMouseViewport = event->position().toPoint();

    if (m_drag == DragMode::None) {
        // Cursor shape: crosshair over handles, open hand over images, ibeam
        // over text areas.
        if (!m_selectedObject.isEmpty()) {
            if (const PlacedObject *selected = m_editor->objectById(m_selectedObject)) {
                if (selected->frame && selected->page
                    && handleAt(canvasPoint, objectCanvasRect(*selected)) >= 0) {
                    viewport()->setCursor(Qt::CrossCursor);
                    return;
                }
            }
        }
        if (objectAt(canvasPoint)) {
            viewport()->setCursor(Qt::OpenHandCursor);
        } else {
            viewport()->setCursor(Qt::IBeamCursor);
        }
        return;
    }

    if (!m_autoscrollTimer.isActive()) m_autoscrollTimer.start(50, this);
    m_dragMoved = true;

    switch (m_drag) {
    case DragMode::Text: {
        const int position = m_editor->layout()->hitTest(canvasPoint, Qt::FuzzyHit);
        if (position >= 0) {
            m_cursor.setPosition(position, QTextCursor::KeepAnchor);
            emit cursorChanged();
            viewport()->update();
        }
        break;
    }
    case DragMode::ImageMove: {
        viewport()->setCursor(Qt::ClosedHandCursor);
        const QPointF delta = canvasPoint - m_dragStartCanvas;
        const QRectF moved = m_dragStartRect.translated(delta);
        const int page = m_editor->layout()->pageIndexForPoint(moved.center());
        const QRectF sheet = m_editor->layout()->pageRect(page);
        m_editor->previewObjectFrame(
            m_selectedObject, page,
            {moved.left() - sheet.left(), moved.top() - sheet.top(),
             moved.width(), moved.height()});
        break;
    }
    case DragMode::ImageResize: {
        // The corner opposite the dragged handle stays anchored; aspect is
        // kept unless Shift is held. Minimum size 24 pt.
        const QPointF corners[4] = {m_dragStartRect.topLeft(), m_dragStartRect.topRight(),
                                    m_dragStartRect.bottomLeft(),
                                    m_dragStartRect.bottomRight()};
        const QPointF anchor = corners[3 - m_dragHandle];
        double w = std::max(24.0, std::abs(canvasPoint.x() - anchor.x()));
        double h = std::max(24.0, std::abs(canvasPoint.y() - anchor.y()));
        if (!(QApplication::keyboardModifiers() & Qt::ShiftModifier)
            && m_dragStartRect.width() > 0 && m_dragStartRect.height() > 0) {
            const double aspect = m_dragStartRect.width() / m_dragStartRect.height();
            if (w / aspect >= h) h = w / aspect;
            else w = h * aspect;
        }
        const QRectF resized(std::min(anchor.x(), anchor.x() + (canvasPoint.x() < anchor.x() ? -w : w)),
                             std::min(anchor.y(), anchor.y() + (canvasPoint.y() < anchor.y() ? -h : h)),
                             w, h);
        const int page = m_dragStartPage;
        const QRectF sheet = m_editor->layout()->pageRect(page);
        m_editor->previewObjectFrame(
            m_selectedObject, page,
            {resized.left() - sheet.left(), resized.top() - sheet.top(),
             resized.width(), resized.height()});
        break;
    }
    default:
        break;
    }
}

void PageCanvas::mouseReleaseEvent(QMouseEvent *event) {
    Q_UNUSED(event);
    m_autoscrollTimer.stop();
    viewport()->setCursor(Qt::IBeamCursor);
    switch (m_drag) {
    case DragMode::ImageMove:
        if (m_dragMoved)
            m_editor->commitObjectFrame(m_selectedObject, m_dragStartPage, m_dragStartFrame,
                                        tr("Move Image"));
        break;
    case DragMode::ImageResize:
        if (m_dragMoved)
            m_editor->commitObjectFrame(m_selectedObject, m_dragStartPage, m_dragStartFrame,
                                        tr("Resize Image"));
        break;
    default:
        break;
    }
    m_drag = DragMode::None;
    m_dragHandle = -1;
}

void PageCanvas::mouseDoubleClickEvent(QMouseEvent *event) {
    const QPointF canvasPoint = toCanvas(event->position());
    // Keep the multi-click chain alive: the second press is delivered here
    // (not to mousePressEvent), so the triple-click timer anchors on IT.
    m_lastClickTime = QDateTime::currentMSecsSinceEpoch();
    m_lastClickPos = event->position().toPoint();
    m_clickCount = 2;
    if (objectAt(canvasPoint)) return;   // double-click on an image: nothing extra
    const int position = m_editor->layout()->hitTest(canvasPoint, Qt::FuzzyHit);
    if (position < 0) return;
    m_cursor.setPosition(position);
    m_cursor.select(QTextCursor::WordUnderCursor);
    emit cursorChanged();
    emit selectionStateChanged();
    viewport()->update();
}

// MARK: - Keyboard

void PageCanvas::keyPressEvent(QKeyEvent *event) {
    // Image selection has its own keymap.
    if (!m_selectedObject.isEmpty()) {
        const double step = (event->modifiers() & Qt::ShiftModifier) ? 10 : 1;
        switch (event->key()) {
        case Qt::Key_Delete:
        case Qt::Key_Backspace:
            deleteSelectedObject();
            return;
        case Qt::Key_Escape:
            selectObject(QString());
            return;
        case Qt::Key_Left: nudgeSelectedObject(-step, 0); return;
        case Qt::Key_Right: nudgeSelectedObject(step, 0); return;
        case Qt::Key_Up: nudgeSelectedObject(0, -step); return;
        case Qt::Key_Down: nudgeSelectedObject(0, step); return;
        default:
            break;
        }
    }

    const bool shift = event->modifiers() & Qt::ShiftModifier;
    const bool ctrl = event->modifiers() & Qt::ControlModifier;
    const QTextCursor::MoveMode mode =
        shift ? QTextCursor::KeepAnchor : QTextCursor::MoveAnchor;
    auto move = [&](QTextCursor::MoveOperation op) {
        m_cursor.movePosition(op, mode);
        refreshCurrentFormat();
        restartCaretBlink();
        ensureCursorVisible();
        emit cursorChanged();
        emit selectionStateChanged();
        viewport()->update();
    };

    switch (event->key()) {
    case Qt::Key_Left: move(ctrl ? QTextCursor::PreviousWord : QTextCursor::Left); return;
    case Qt::Key_Right: move(ctrl ? QTextCursor::NextWord : QTextCursor::Right); return;
    case Qt::Key_Up: move(QTextCursor::Up); return;
    case Qt::Key_Down: move(QTextCursor::Down); return;
    case Qt::Key_Home: move(ctrl ? QTextCursor::Start : QTextCursor::StartOfLine); return;
    case Qt::Key_End: move(ctrl ? QTextCursor::End : QTextCursor::EndOfLine); return;
    case Qt::Key_PageUp:
    case Qt::Key_PageDown: {
        const double pageStep = viewport()->height() / m_zoom;
        const QRectF rect = cursorRect(m_cursor);
        const QPointF target(rect.center().x(),
                             rect.center().y()
                                 + (event->key() == Qt::Key_PageDown ? pageStep : -pageStep));
        const int position = m_editor->layout()->hitTest(target, Qt::FuzzyHit);
        if (position >= 0) {
            m_cursor.setPosition(position, mode);
            refreshCurrentFormat();
            ensureCursorVisible();
            emit cursorChanged();
            viewport()->update();
        }
        return;
    }
    case Qt::Key_Backspace:
        m_cursor.deletePreviousChar();
        ensureCursorVisible();
        return;
    case Qt::Key_Delete:
        m_cursor.deleteChar();
        ensureCursorVisible();
        return;
    case Qt::Key_Return:
    case Qt::Key_Enter:
        if (shift) {
            insertPlainText(QString(QChar::LineSeparator));
        } else {
            handleReturn();
        }
        return;
    case Qt::Key_Tab: {
        const auto item = DocumentBridge::decodeListItem(
            m_cursor.block().charFormat().stringProperty(Props::ListItem));
        if (item && m_cursor.positionInBlock() == 0) {
            m_editor->changeListLevel(m_cursor, +1);
        } else {
            insertPlainText(QStringLiteral("\t"));
        }
        return;
    }
    case Qt::Key_Backtab:
        m_editor->changeListLevel(m_cursor, -1);
        return;
    case Qt::Key_Escape:
        event->ignore();
        return;
    default:
        break;
    }

    const QString text = event->text();
    if (!text.isEmpty() && text.at(0).isPrint() && !ctrl) {
        insertPlainText(text);
        return;
    }
    QAbstractScrollArea::keyPressEvent(event);
}

QTextCharFormat PageCanvas::freshParagraphCharFormat(const QTextCharFormat &base,
                                                     bool clearListAndBreak) const {
    QTextCharFormat format = base;
    format.setProperty(Props::ParagraphId, IDGenerator::next(QStringLiteral("p")));
    format.clearProperty(Props::PageBreakBefore);
    if (clearListAndBreak) format.clearProperty(Props::ListItem);
    return format;
}

void PageCanvas::handleReturn() {
    m_cursor.beginEditBlock();
    const QTextBlock block = m_cursor.block();
    const QTextCharFormat bcf = block.charFormat();
    const auto item =
        DocumentBridge::decodeListItem(bcf.stringProperty(Props::ListItem));
    const bool blockEmpty = block.length() <= 1;

    if (item && blockEmpty) {
        // Return on an empty list item: outdent, or leave the list entirely.
        if (item->level > 0) {
            m_cursor.endEditBlock();
            m_editor->changeListLevel(m_cursor, -1);
            return;
        }
        QTextCharFormat cleared = bcf;
        cleared.clearProperty(Props::ListItem);
        QTextCursor blockCursor(block);
        blockCursor.setBlockCharFormat(cleared);
        m_cursor.endEditBlock();
        viewport()->update();
        return;
    }

    // At the end of a heading, the next paragraph starts in Body.
    const QString role = m_editor->styleRoleAt(m_cursor);
    const QString hint = m_editor->model().resolvedStyle(role).markdown;
    const bool headingEnd = m_cursor.atBlockEnd()
        && (hint == QLatin1String("h1") || hint == QLatin1String("h2")
            || hint == QLatin1String("h3") || hint == QLatin1String("h4"));

    m_cursor.insertBlock(m_cursor.blockFormat(),
                         freshParagraphCharFormat(bcf, /*clearListAndBreak=*/false));
    if (headingEnd
        && m_editor->styles().contains(DocumentModel::defaultStyleRole()))
        m_editor->applyStyle(m_cursor, DocumentModel::defaultStyleRole());
    m_cursor.endEditBlock();
    refreshCurrentFormat();
    ensureCursorVisible();
    emit cursorChanged();
}

void PageCanvas::insertPlainText(const QString &text) {
    m_cursor.insertText(text, m_currentFormat);
    restartCaretBlink();
    ensureCursorVisible();
}

// MARK: - Formatting

void PageCanvas::refreshCurrentFormat() {
    QTextCharFormat format = m_cursor.charFormat();
    // An empty block's cursor.charFormat can miss the block base; fall back.
    if (format.properties().isEmpty()) format = m_cursor.blockCharFormat();
    m_currentFormat = format;
}

void PageCanvas::mergeCharFormat(const QTextCharFormat &format) {
    if (m_cursor.hasSelection()) {
        m_cursor.mergeCharFormat(format);
    }
    m_currentFormat.merge(format);
    emit cursorChanged();
    viewport()->update();
    setFocus();
}

void PageCanvas::setBlockAlignment(Qt::Alignment alignment) {
    QTextBlockFormat format;
    format.setAlignment(alignment);
    m_cursor.mergeBlockFormat(format);
    emit cursorChanged();
    setFocus();
}

void PageCanvas::setBlockLineSpacing(double multiple) {
    QTextBlockFormat format;
    format.setLineHeight(multiple * 100.0, QTextBlockFormat::ProportionalHeight);
    m_cursor.mergeBlockFormat(format);
    emit cursorChanged();
    setFocus();
}

void PageCanvas::setTextCursor(const QTextCursor &cursor) {
    clearPreedit();
    m_cursor = cursor;
    refreshCurrentFormat();
    restartCaretBlink();
    emit cursorChanged();
    emit selectionStateChanged();
    viewport()->update();
}

// MARK: - Clipboard

void PageCanvas::copySelection() {
    if (!m_cursor.hasSelection()) return;
    QString text = m_cursor.selectedText();
    text.replace(QChar::ParagraphSeparator, QLatin1Char('\n'));
    text.replace(QChar::LineSeparator, QLatin1Char('\n'));
    QGuiApplication::clipboard()->setText(text);
}

void PageCanvas::cutSelection() {
    if (!m_cursor.hasSelection()) return;
    copySelection();
    m_cursor.removeSelectedText();
    ensureCursorVisible();
}

void PageCanvas::paste() {
    const QMimeData *mime = QGuiApplication::clipboard()->mimeData();
    if (!mime) return;
    if (mime->hasImage()) {
        const QImage image = qvariant_cast<QImage>(mime->imageData());
        if (!image.isNull()) {
            QByteArray payload;
            QBuffer buffer(&payload);
            buffer.open(QIODevice::WriteOnly);
            image.save(&buffer, "PNG");
            const QRectF rect = cursorRect(m_cursor);
            const int page = m_editor->layout()->pageIndexForPoint(rect.center());
            const QRectF sheet = m_editor->layout()->pageRect(page);
            const QPointF pagePoint = rect.isValid()
                ? QPointF(rect.center().x() - sheet.left(), rect.center().y() - sheet.top())
                : QPointF(sheet.width() / 2, sheet.height() / 3);
            const QString id =
                m_editor->insertImage(payload, QStringLiteral("pasted.png"), page, pagePoint);
            if (!id.isEmpty()) selectObject(id);
            return;
        }
    }
    if (mime->hasText()) {
        QString text = mime->text();
        text.replace(QStringLiteral("\r\n"), QStringLiteral("\n"));
        // Paragraph breaks stay paragraph breaks.
        const QStringList parts = text.split(QLatin1Char('\n'));
        m_cursor.beginEditBlock();
        for (int i = 0; i < parts.size(); ++i) {
            if (i > 0)
                m_cursor.insertBlock(m_cursor.blockFormat(),
                                     freshParagraphCharFormat(m_cursor.blockCharFormat(),
                                                              false));
            m_cursor.insertText(parts[i], m_currentFormat);
        }
        m_cursor.endEditBlock();
        ensureCursorVisible();
    }
}

void PageCanvas::selectAllText() {
    m_cursor.select(QTextCursor::Document);
    emit cursorChanged();
    emit selectionStateChanged();
    viewport()->update();
}

void PageCanvas::deleteSelection() {
    if (!m_selectedObject.isEmpty()) {
        deleteSelectedObject();
        return;
    }
    if (m_cursor.hasSelection()) m_cursor.removeSelectedText();
}

// MARK: - IME

void PageCanvas::clearPreedit() {
    if (m_preedit.isEmpty() && m_preeditBlock < 0) return;
    m_preedit.clear();
    QTextBlock stale = m_editor->document()->findBlockByNumber(m_preeditBlock);
    m_preeditBlock = -1;
    if (stale.isValid()) {
        stale.layout()->setPreeditArea(-1, QString());
        m_editor->document()->markContentsDirty(stale.position(), stale.length());
    }
    viewport()->update();
}

void PageCanvas::inputMethodEvent(QInputMethodEvent *event) {
    // An active selection is replaced by the composition/commit (standard
    // editor behavior); do it before anchoring the preedit.
    if (m_cursor.hasSelection()
        && (!event->commitString().isEmpty() || !event->preeditString().isEmpty()))
        m_cursor.removeSelectedText();

    if (!event->commitString().isEmpty() || event->replacementLength() > 0) {
        QTextCursor cursor = m_cursor;
        cursor.setPosition(m_cursor.position() + event->replacementStart());
        cursor.setPosition(cursor.position() + event->replacementLength(),
                           QTextCursor::KeepAnchor);
        cursor.insertText(event->commitString(), m_currentFormat);
        m_cursor.setPosition(cursor.position());
    }

    // The composition may have moved to a different block (or ended): never
    // strand ghost preedit text on the old one.
    QTextBlock block = m_cursor.block();
    if (m_preeditBlock >= 0 && m_preeditBlock != block.blockNumber()) clearPreedit();

    m_preedit = event->preeditString();
    m_preeditBlock = m_preedit.isEmpty() ? -1 : block.blockNumber();
    block.layout()->setPreeditArea(
        m_preedit.isEmpty() ? -1 : m_cursor.position() - block.position(), m_preedit);
    m_editor->document()->markContentsDirty(block.position(), block.length());
    ensureCursorVisible();
    viewport()->update();
}

QVariant PageCanvas::inputMethodQuery(Qt::InputMethodQuery query) const {
    switch (query) {
    case Qt::ImCursorRectangle: {
        const QRectF rect = cursorRect(m_cursor);
        const QPointF device = fromCanvas(rect.topLeft());
        return QRectF(device, QSizeF(rect.width() * m_zoom, rect.height() * m_zoom));
    }
    case Qt::ImSurroundingText:
        return m_cursor.block().text();
    case Qt::ImCursorPosition:
        return m_cursor.positionInBlock();
    case Qt::ImCurrentSelection:
        return m_cursor.selectedText();
    default:
        return QVariant();
    }
}

// MARK: - Zoom / scroll

void PageCanvas::setZoom(double zoom) {
    zoom = std::clamp(zoom, 0.25, 4.0);
    if (qFuzzyCompare(zoom, m_zoom)) return;
    // Keep the viewport's center stable through the zoom change.
    const QPointF centerCanvas = toCanvas(QPointF(viewport()->width() / 2.0,
                                                  viewport()->height() / 2.0));
    m_zoom = zoom;
    updateScrollBars();
    const QPointF target = centerCanvas * m_zoom;
    horizontalScrollBar()->setValue(int(target.x()
        + canvasInset * m_zoom
        + std::max((viewport()->width() - canvasSize().width() * m_zoom) / 2.0, 0.0)
        - viewport()->width() / 2.0));
    verticalScrollBar()->setValue(int(target.y() + canvasInset * m_zoom
                                      - viewport()->height() / 2.0));
    viewport()->update();
    emit zoomChanged(m_zoom);
}

void PageCanvas::fitPage() {
    const QSizeF sheet(m_editor->model().page.width, m_editor->model().page.height);
    const double zx = viewport()->width() / (sheet.width() + 2 * canvasInset);
    const double zy = viewport()->height() / (sheet.height() + 2 * canvasInset);
    setZoom(std::min(zx, zy));
}

void PageCanvas::fitWidth() {
    setZoom(viewport()->width() / (m_editor->model().page.width + 2 * canvasInset));
}

int PageCanvas::currentPage() const {
    const QPointF middle = toCanvas(QPointF(viewport()->width() / 2.0,
                                            viewport()->height() / 2.0));
    return m_editor->layout()->pageIndexForPoint(middle) + 1;
}

void PageCanvas::revealPosition(int position) {
    m_cursor.setPosition(std::clamp(position, 0,
                                    m_editor->document()->characterCount() - 1));
    refreshCurrentFormat();
    ensureCursorVisible();
    emit cursorChanged();
    viewport()->update();
    setFocus();
}

void PageCanvas::ensureCursorVisible() {
    const QRectF rect = cursorRect(m_cursor);
    if (!rect.isValid()) return;
    const QPointF topDevice = fromCanvas(rect.topLeft());
    const QPointF bottomDevice = fromCanvas(rect.bottomLeft());
    const double margin = 24;
    if (topDevice.y() < margin)
        verticalScrollBar()->setValue(verticalScrollBar()->value()
                                      + int(topDevice.y() - margin));
    else if (bottomDevice.y() > viewport()->height() - margin)
        verticalScrollBar()->setValue(verticalScrollBar()->value()
            + int(bottomDevice.y() - viewport()->height() + margin));
    if (topDevice.x() < margin)
        horizontalScrollBar()->setValue(horizontalScrollBar()->value()
                                        + int(topDevice.x() - margin));
    else if (topDevice.x() > viewport()->width() - margin)
        horizontalScrollBar()->setValue(horizontalScrollBar()->value()
            + int(topDevice.x() - viewport()->width() + margin));
}

void PageCanvas::scrollContentsBy(int dx, int dy) {
    Q_UNUSED(dx);
    Q_UNUSED(dy);
    viewport()->update();
    emit viewScrolled();
}

void PageCanvas::resizeEvent(QResizeEvent *event) {
    QAbstractScrollArea::resizeEvent(event);
    updateScrollBars();
}

void PageCanvas::wheelEvent(QWheelEvent *event) {
    if (event->modifiers() & Qt::ControlModifier) {
        const double steps = event->angleDelta().y() / 120.0;
        setZoom(m_zoom * std::pow(1.1, steps));
        event->accept();
        return;
    }
    QAbstractScrollArea::wheelEvent(event);
}

// MARK: - Timers / focus

void PageCanvas::restartCaretBlink() {
    m_caretVisible = true;
    const int flash = QApplication::styleHints()->cursorFlashTime();
    if (flash > 0) m_caretTimer.start(flash / 2, this);
}

void PageCanvas::timerEvent(QTimerEvent *event) {
    if (event->timerId() == m_caretTimer.timerId()) {
        m_caretVisible = !m_caretVisible;
        viewport()->update();
        return;
    }
    if (event->timerId() == m_autoscrollTimer.timerId()) {
        // Keep dragging while the pointer is outside the viewport.
        const QRect view = viewport()->rect();
        int dy = 0;
        if (m_lastMouseViewport.y() < view.top()) dy = m_lastMouseViewport.y() - view.top();
        else if (m_lastMouseViewport.y() > view.bottom())
            dy = m_lastMouseViewport.y() - view.bottom();
        if (dy != 0)
            verticalScrollBar()->setValue(verticalScrollBar()->value() + dy / 2);
        return;
    }
    QAbstractScrollArea::timerEvent(event);
}

void PageCanvas::focusInEvent(QFocusEvent *event) {
    QAbstractScrollArea::focusInEvent(event);
    restartCaretBlink();
    viewport()->update();
}

void PageCanvas::focusOutEvent(QFocusEvent *event) {
    QAbstractScrollArea::focusOutEvent(event);
    clearPreedit();
    m_caretTimer.stop();
    viewport()->update();
}

void PageCanvas::contextMenuEvent(QContextMenuEvent *event) {
    // The window supplies the menu (it owns the actions); we just ask for it.
    QAbstractScrollArea::contextMenuEvent(event);
}

} // namespace lucerne
