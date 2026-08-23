#pragma once

// The editing surface: paints the stacked pages (paper, shadows, margins,
// header/footer furniture, fold marks, floating images, text, caret,
// selection) and owns every input gesture — the Qt analogue of the Mac's
// PageCanvasView + PageTextView + FloatingImageView trio, collapsed into one
// widget because here the text engine doesn't demand per-page views.
//
// Text is drawn by PageLayout in shared canvas coordinates; this widget adds
// zoom (a painter scale) and scrolling on top, so layout geometry never knows
// about either.

#include "app/Editor.h"

#include <QAbstractScrollArea>
#include <QBasicTimer>
#include <QTextCursor>

namespace lucerne {

class PageCanvas : public QAbstractScrollArea {
    Q_OBJECT
public:
    explicit PageCanvas(Editor *editor, QWidget *parent = nullptr);

    Editor *editor() const { return m_editor; }

    QTextCursor textCursor() const { return m_cursor; }
    void setTextCursor(const QTextCursor &cursor);

    // Formatting entry points (selection, or the pending typing format).
    void mergeCharFormat(const QTextCharFormat &format);
    QTextCharFormat currentCharFormat() const { return m_currentFormat; }
    void setBlockAlignment(Qt::Alignment alignment);
    void setBlockLineSpacing(double multiple);

    QString selectedObjectId() const { return m_selectedObject; }
    void selectObject(const QString &id);

    // Clipboard / selection
    void cutSelection();
    void copySelection();
    void paste();
    void selectAllText();
    void deleteSelection();

    // Zoom
    double zoom() const { return m_zoom; }
    void setZoom(double zoom);
    void zoomIn() { setZoom(m_zoom * 1.25); }
    void zoomOut() { setZoom(m_zoom / 1.25); }
    void fitPage();
    void fitWidth();

    /// 1-based page whose sheet crosses the viewport's vertical midpoint.
    int currentPage() const;

    /// Canvas ↔ viewport-device mapping for chrome that must track the page
    /// column (the ruler).
    QPointF canvasToViewport(const QPointF &canvasPoint) const { return fromCanvas(canvasPoint); }
    QPointF viewportToCanvas(const QPointF &viewportPoint) const { return toCanvas(viewportPoint); }
    /// Scrolls so `position` (a character index) is visible, caret at it.
    void revealPosition(int position);

    void ensureCursorVisible();

signals:
    void cursorChanged();            // caret moved or formatting under it changed
    void selectionStateChanged();    // text selection / image selection flipped
    void zoomChanged(double zoom);
    void viewScrolled();             // current page indicator may need refresh
    void statusMessage(const QString &message);

protected:
    void paintEvent(QPaintEvent *event) override;
    void resizeEvent(QResizeEvent *event) override;
    void scrollContentsBy(int dx, int dy) override;
    void mousePressEvent(QMouseEvent *event) override;
    void mouseMoveEvent(QMouseEvent *event) override;
    void mouseReleaseEvent(QMouseEvent *event) override;
    void mouseDoubleClickEvent(QMouseEvent *event) override;
    void keyPressEvent(QKeyEvent *event) override;
    void keyReleaseEvent(QKeyEvent *event) override;
    void inputMethodEvent(QInputMethodEvent *event) override;
    QVariant inputMethodQuery(Qt::InputMethodQuery query) const override;
    void wheelEvent(QWheelEvent *event) override;
    void timerEvent(QTimerEvent *event) override;
    void focusInEvent(QFocusEvent *event) override;
    void focusOutEvent(QFocusEvent *event) override;
    void contextMenuEvent(QContextMenuEvent *event) override;

private:
    enum class DragMode { None, Text, ImageMove, ImageResize };

    // Geometry plumbing
    static constexpr double canvasInset = 28;   // gray border around the pages
    QPointF canvasOrigin() const;               // device px of canvas (0,0)
    QPointF toCanvas(const QPointF &viewportPoint) const;
    QPointF fromCanvas(const QPointF &canvasPoint) const;
    QSizeF canvasSize() const;
    void updateScrollBars();
    QRectF cursorRect(const QTextCursor &cursor) const;   // canvas coords

    // Image plumbing
    QRectF objectCanvasRect(const PlacedObject &object) const;
    const PlacedObject *objectAt(const QPointF &canvasPoint) const;
    double handleSize() const;                  // canvas units, ≈9 device px
    int handleAt(const QPointF &canvasPoint, const QRectF &rect) const;   // 0-3 or -1
    void nudgeSelectedObject(double dx, double dy);
    /// Pushes the accumulated nudge burst as ONE undo step (see keyReleaseEvent).
    void commitPendingNudge();
    void deleteSelectedObject();
    /// Re-evaluates the active drag at a viewport position — shared by
    /// mouseMoveEvent and the autoscroll timer (which must keep the selection
    /// or image preview following while the content scrolls under a
    /// stationary pointer).
    void updateDrag(const QPointF &viewportPos);

    // Editing helpers
    void handleReturn();
    void insertPlainText(const QString &text);
    void refreshCurrentFormat();
    void restartCaretBlink();
    /// Ends any in-flight IME composition display (ghost preedit text must not
    /// be stranded when the caret leaves the composing block).
    void clearPreedit();
    QTextCharFormat freshParagraphCharFormat(const QTextCharFormat &base,
                                             bool clearListAndBreak) const;

    Editor *m_editor;
    QTextCursor m_cursor;
    QTextCharFormat m_currentFormat;
    double m_zoom = 1.0;

    QString m_selectedObject;
    DragMode m_drag = DragMode::None;
    int m_dragHandle = -1;
    QPointF m_dragStartCanvas;
    QRectF m_dragStartRect;         // canvas coords of the object at mousedown
    int m_dragStartPage = 0;
    RectModel m_dragStartFrame;     // model coords at mousedown (for undo)
    bool m_dragMoved = false;

    // Arrow-key nudge burst: previews accumulate, commitPendingNudge() pushes
    // the whole burst (auto-repeat included) as a single undo step.
    bool m_nudgePending = false;
    int m_nudgeStartPage = 0;
    RectModel m_nudgeStartFrame;

    QBasicTimer m_caretTimer;
    bool m_caretVisible = true;
    QBasicTimer m_autoscrollTimer;
    QPoint m_lastMouseViewport;

    QString m_preedit;
    int m_preeditBlock = -1;   // block number carrying the preedit area, or -1
    quint64 m_lastClickTime = 0;
    QPoint m_lastClickPos;
    int m_clickCount = 1;
};

} // namespace lucerne
