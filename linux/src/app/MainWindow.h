#pragma once

// The document window: menu bar, format toolbar, ruler, canvas, navigator
// dock, find bar, and status bar — the Mac DocumentWindowController's job,
// arranged with GNOME/Ubuntu conventions (Ctrl shortcuts, standard theme
// widgets, an in-window find bar instead of a floating panel).

#include "app/Editor.h"

#include <QMainWindow>

class QComboBox;
class QFontComboBox;
class QLabel;
class QLineEdit;
class QListWidget;
class QToolButton;

namespace lucerne {

class PageCanvas;
class Ruler;

class MainWindow : public QMainWindow {
    Q_OBJECT
public:
    explicit MainWindow(QWidget *parent = nullptr);

    Editor *editor() const { return m_editor; }

    bool openPath(const QString &path);
    void loadSampleLetter();

    /// New top-level window (File ▸ New / opening a second document).
    static MainWindow *newWindow();

protected:
    void closeEvent(QCloseEvent *event) override;

private:
    void buildMenus();
    void buildToolbar();
    void buildStatusBar();
    void buildFindBar();
    void buildNavigator();

    // File
    void newDocument();
    void openDocument();
    bool saveDocument();
    bool saveDocumentAs();
    bool maybeSave();
    void exportPdf();
    void exportMarkdown();
    void printDocument();
    void documentSetup();

    // Format plumbing
    void syncFormatControls();
    void rebuildStyleControls();
    void applyCurrentStyle(const QString &role);
    void chooseColor();

    // Insert
    void insertImageFromFile();
    void insertDate();
    void editHeaderFooter();

    // View / chrome
    void rebuildNavigator();
    void updateStatus();
    void updateTitle();
    void scheduleWordCount();

    Editor *m_editor;
    PageCanvas *m_canvas;
    Ruler *m_ruler;

    // Toolbar controls
    QComboBox *m_styleCombo = nullptr;
    QFontComboBox *m_fontCombo = nullptr;
    QComboBox *m_sizeCombo = nullptr;
    QAction *m_boldAction = nullptr;
    QAction *m_italicAction = nullptr;
    QAction *m_underlineAction = nullptr;
    QToolButton *m_colorButton = nullptr;
    QAction *m_alignActions[4] = {};
    QComboBox *m_spacingCombo = nullptr;

    // Menus that follow state
    QMenu *m_styleMenu = nullptr;
    QMenu *m_recentMenu = nullptr;
    QAction *m_wrapNone = nullptr;
    QAction *m_wrapRectangular = nullptr;

    // Chrome
    QLabel *m_statusLabel = nullptr;
    QLabel *m_pageLabel = nullptr;
    QToolButton *m_zoomLabel = nullptr;
    QWidget *m_findBar = nullptr;
    QLineEdit *m_findField = nullptr;
    QLineEdit *m_replaceField = nullptr;
    QAction *m_findCaseAction = nullptr;
    QLabel *m_findStatus = nullptr;
    QDockWidget *m_navigatorDock = nullptr;
    QListWidget *m_navigator = nullptr;

    int m_wordCount = 0;
    QTimer *m_wordCountTimer = nullptr;
    bool m_syncingControls = false;

    void findNext(bool backwards);
    void replaceCurrent();
    void replaceAll();
};

} // namespace lucerne
