#include "app/MainWindow.h"
#include "app/Dialogs.h"
#include "app/DocumentBridge.h"
#include "app/PageCanvas.h"
#include "app/Ruler.h"
#include "app/WelcomeDialog.h"
#include "core/DefaultDocuments.h"
#include "core/Markdown.h"

#include <QActionGroup>
#include <QApplication>
#include <QClipboard>
#include <QDate>
#include <QHBoxLayout>
#include <QVBoxLayout>
#include <QCloseEvent>
#include <QColorDialog>
#include <QComboBox>
#include <QDesktopServices>
#include <QDockWidget>
#include <QFileDialog>
#include <QFontComboBox>
#include <QLabel>
#include <QLineEdit>
#include <QListWidget>
#include <QMenuBar>
#include <QMessageBox>
#include <QPageSize>
#include <QPainter>
#include <QPdfWriter>
#include <QPrintDialog>
#include <QPrinter>
#include <QSaveFile>
#include <QSettings>
#include <QStatusBar>
#include <QTextBlock>
#include <QTimer>
#include <QToolBar>
#include <QToolButton>
#include <QUrl>

namespace lucerne {

namespace {
QVector<MainWindow *> &openWindows() {
    static QVector<MainWindow *> windows;
    return windows;
}
} // namespace

MainWindow *MainWindow::newWindow() {
    auto *window = new MainWindow;
    window->setAttribute(Qt::WA_DeleteOnClose);
    window->show();
    return window;
}

MainWindow::MainWindow(QWidget *parent) : QMainWindow(parent) {
    openWindows().append(this);
    m_editor = new Editor(this);

    auto *central = new QWidget(this);
    auto *column = new QVBoxLayout(central);
    column->setContentsMargins(0, 0, 0, 0);
    column->setSpacing(0);

    m_canvas = new PageCanvas(m_editor, central);
    m_ruler = new Ruler(m_canvas, central);
    buildFindBar();
    column->addWidget(m_findBar);
    column->addWidget(m_ruler);
    column->addWidget(m_canvas, 1);
    setCentralWidget(central);

    buildMenus();
    buildToolbar();
    buildStatusBar();
    buildNavigator();

    // Ruler unit preference.
    const QString unit =
        QSettings().value(QStringLiteral("rulerUnit"), QStringLiteral("centimeters")).toString();
    m_ruler->setUnit(unit == QLatin1String("inches") ? Ruler::Unit::Inches
                                                     : Ruler::Unit::Centimeters);

    connect(m_canvas, &PageCanvas::cursorChanged, this, &MainWindow::syncFormatControls);
    connect(m_canvas, &PageCanvas::selectionStateChanged, this, &MainWindow::updateStatus);
    connect(m_canvas, &PageCanvas::statusMessage, this, [this](const QString &message) {
        statusBar()->showMessage(message, 4000);
    });
    connect(m_ruler, &Ruler::statusMessage, this, [this](const QString &message) {
        statusBar()->showMessage(message, 4000);
    });
    connect(m_canvas, &PageCanvas::zoomChanged, this, [this](double) { updateStatus(); });
    connect(m_canvas, &PageCanvas::viewScrolled, this, [this] { updateStatus(); });
    connect(m_editor, &Editor::modifiedChanged, this, &MainWindow::updateTitle);
    connect(m_editor->layout(), &PageLayout::layoutChanged, this, [this] {
        updateStatus();
        rebuildNavigator();
    });
    connect(m_editor->document(), &QTextDocument::contentsChanged, this,
            &MainWindow::scheduleWordCount);

    m_wordCountTimer = new QTimer(this);
    m_wordCountTimer->setSingleShot(true);
    m_wordCountTimer->setInterval(300);
    connect(m_wordCountTimer, &QTimer::timeout, this, [this] {
        QString text = m_editor->document()->toPlainText();
        m_wordCount = 0;
        bool inWord = false;
        for (const QChar ch : text) {
            const bool wordChar = ch.isLetterOrNumber();
            if (wordChar && !inWord) ++m_wordCount;
            inWord = wordChar;
        }
        updateStatus();
    });

    resize(980, 760);
    updateTitle();
    syncFormatControls();
    rebuildStyleControls();
    scheduleWordCount();
    m_canvas->setFocus();
}

// MARK: - Menus

void MainWindow::buildMenus() {
    // File
    QMenu *file = menuBar()->addMenu(tr("&File"));
    file->addAction(tr("&New"), this, &MainWindow::newDocument, QKeySequence::New);
    file->addAction(tr("&Open…"), this, &MainWindow::openDocument, QKeySequence::Open);
    m_recentMenu = file->addMenu(tr("Open &Recent"));
    connect(m_recentMenu, &QMenu::aboutToShow, this, [this] {
        m_recentMenu->clear();
        const QStringList recents = WelcomeDialog::recentFiles();
        for (const QString &path : recents) {
            m_recentMenu->addAction(QFileInfo(path).completeBaseName(), this,
                                    [this, path] { openPath(path); });
        }
        if (recents.isEmpty()) m_recentMenu->addAction(tr("No recent letters"))->setEnabled(false);
    });
    file->addSeparator();
    file->addAction(tr("&Save"), this, &MainWindow::saveDocument, QKeySequence::Save);
    file->addAction(tr("Save &As…"), this, &MainWindow::saveDocumentAs, QKeySequence::SaveAs);
    file->addSeparator();
    file->addAction(tr("Export as &PDF…"), this, &MainWindow::exportPdf);
    file->addAction(tr("Export as &Markdown…"), this, &MainWindow::exportMarkdown);
    file->addSeparator();
    file->addAction(tr("Document Set&up…"), this, &MainWindow::documentSetup);
    file->addAction(tr("&Print…"), this, &MainWindow::printDocument, QKeySequence::Print);
    file->addSeparator();
    file->addAction(tr("&Close"), this, &QWidget::close, QKeySequence::Close);
    file->addAction(tr("&Quit"), qApp, &QApplication::closeAllWindows, QKeySequence::Quit);

    // Edit
    QMenu *edit = menuBar()->addMenu(tr("&Edit"));
    QAction *undo = m_editor->undoStack()->createUndoAction(this, tr("&Undo"));
    undo->setShortcut(QKeySequence::Undo);
    QAction *redo = m_editor->undoStack()->createRedoAction(this, tr("&Redo"));
    redo->setShortcut(QKeySequence::Redo);
    edit->addAction(undo);
    edit->addAction(redo);
    edit->addSeparator();
    edit->addAction(tr("Cu&t"), m_canvas, &PageCanvas::cutSelection, QKeySequence::Cut);
    edit->addAction(tr("&Copy"), m_canvas, &PageCanvas::copySelection, QKeySequence::Copy);
    edit->addAction(tr("&Paste"), m_canvas, &PageCanvas::paste, QKeySequence::Paste);
    edit->addAction(tr("Select &All"), m_canvas, &PageCanvas::selectAllText,
                    QKeySequence::SelectAll);
    edit->addSeparator();
    edit->addAction(tr("Copy as &Markdown"), this, [this] {
        QGuiApplication::clipboard()->setText(
            MarkdownExporter::exportModel(m_editor->snapshotModel()));
        statusBar()->showMessage(tr("Copied the whole letter as Markdown"), 3000);
    });
    edit->addSeparator();
    edit->addAction(tr("&Find…"), this, [this] {
        m_findBar->setVisible(true);
        m_findField->setFocus();
        m_findField->selectAll();
    }, QKeySequence::Find);
    edit->addAction(tr("Find &Next"), this, [this] { findNext(false); },
                    QKeySequence::FindNext);
    edit->addAction(tr("Find Pre&vious"), this, [this] { findNext(true); },
                    QKeySequence::FindPrevious);
    edit->addSeparator();
    edit->addAction(tr("Pr&eferences…"), this,
                    [this] {
        PreferencesDialog dialog(this);
        connect(&dialog, &PreferencesDialog::rulerUnitChanged, this, [this] {
            const QString unit = QSettings()
                .value(QStringLiteral("rulerUnit"), QStringLiteral("centimeters")).toString();
            m_ruler->setUnit(unit == QLatin1String("inches") ? Ruler::Unit::Inches
                                                             : Ruler::Unit::Centimeters);
        });
        dialog.exec();
    }, QKeySequence(Qt::CTRL | Qt::Key_Comma));

    // Format
    QMenu *format = menuBar()->addMenu(tr("F&ormat"));
    m_boldAction = format->addAction(tr("&Bold"), this, [this] {
        QTextCharFormat fmt;
        fmt.setFontWeight(m_boldAction->isChecked() ? QFont::Bold : QFont::Normal);
        m_canvas->mergeCharFormat(fmt);
    }, QKeySequence::Bold);
    m_boldAction->setCheckable(true);
    m_italicAction = format->addAction(tr("&Italic"), this, [this] {
        QTextCharFormat fmt;
        fmt.setFontItalic(m_italicAction->isChecked());
        m_canvas->mergeCharFormat(fmt);
    }, QKeySequence::Italic);
    m_italicAction->setCheckable(true);
    m_underlineAction = format->addAction(tr("&Underline"), this, [this] {
        QTextCharFormat fmt;
        fmt.setFontUnderline(m_underlineAction->isChecked());
        m_canvas->mergeCharFormat(fmt);
    }, QKeySequence::Underline);
    m_underlineAction->setCheckable(true);
    format->addAction(tr("Text &Color…"), this, &MainWindow::chooseColor);
    format->addSeparator();

    QMenu *align = format->addMenu(tr("&Alignment"));
    struct AlignSpec {
        const char *name;
        QKeySequence shortcut;
        Qt::Alignment value;
    };
    const AlignSpec aligns[4] = {
        {QT_TR_NOOP("Align &Left"), QKeySequence(Qt::CTRL | Qt::Key_BraceLeft), Qt::AlignLeft},
        {QT_TR_NOOP("&Center"), QKeySequence(Qt::CTRL | Qt::Key_Bar), Qt::AlignHCenter},
        {QT_TR_NOOP("Align &Right"), QKeySequence(Qt::CTRL | Qt::Key_BraceRight), Qt::AlignRight},
        {QT_TR_NOOP("&Justify"), QKeySequence(), Qt::AlignJustify},
    };
    auto *alignGroup = new QActionGroup(this);
    for (int i = 0; i < 4; ++i) {
        QAction *action = align->addAction(tr(aligns[i].name));
        action->setShortcut(aligns[i].shortcut);
        action->setCheckable(true);
        alignGroup->addAction(action);
        const Qt::Alignment value = aligns[i].value;
        connect(action, &QAction::triggered, this,
                [this, value] { m_canvas->setBlockAlignment(value); });
        m_alignActions[i] = action;
    }

    QMenu *spacing = format->addMenu(tr("Line &Spacing"));
    for (const double multiple : {1.0, 1.15, 1.5, 2.0}) {
        spacing->addAction(QString::number(multiple), this,
                           [this, multiple] { m_canvas->setBlockLineSpacing(multiple); });
    }

    m_styleMenu = format->addMenu(tr("Paragraph &Style"));
    connect(m_styleMenu, &QMenu::aboutToShow, this, [this] {
        m_styleMenu->clear();
        const QString current = m_editor->styleRoleAt(m_canvas->textCursor());
        int index = 0;
        for (const QString &role : m_editor->model().orderedStyleRoles()) {
            const ParagraphStyle style = m_editor->styles().value(role);
            QAction *action = m_styleMenu->addAction(style.name, this,
                                                     [this, role] { applyCurrentStyle(role); });
            action->setCheckable(true);
            action->setChecked(role == current);
            if (index < 9)
                action->setShortcut(QKeySequence(Qt::CTRL | Qt::ALT
                                                 | (Qt::Key_1 + index)));
            ++index;
        }
    });

    QMenu *list = format->addMenu(tr("&List"));
    list->addAction(tr("&Bulleted List"), this, [this] {
        m_editor->toggleList(m_canvas->textCursor(), false, QString());
    }, QKeySequence(Qt::CTRL | Qt::SHIFT | Qt::Key_8));
    list->addAction(tr("&Numbered List"), this, [this] {
        m_editor->toggleList(m_canvas->textCursor(), true, QString());
    }, QKeySequence(Qt::CTRL | Qt::SHIFT | Qt::Key_7));
    list->addSeparator();
    list->addAction(tr("&Increase List Level"), this,
                    [this] { m_editor->changeListLevel(m_canvas->textCursor(), +1); },
                    QKeySequence(Qt::CTRL | Qt::Key_BracketRight));
    list->addAction(tr("&Decrease List Level"), this,
                    [this] { m_editor->changeListLevel(m_canvas->textCursor(), -1); },
                    QKeySequence(Qt::CTRL | Qt::Key_BracketLeft));

    // Insert
    QMenu *insert = menuBar()->addMenu(tr("&Insert"));
    insert->addAction(tr("&Image…"), this, &MainWindow::insertImageFromFile,
                      QKeySequence(Qt::CTRL | Qt::SHIFT | Qt::Key_I));
    insert->addAction(tr("Page &Break"), this, [this] {
        m_editor->insertPageBreak(m_canvas->textCursor());
    }, QKeySequence(Qt::CTRL | Qt::SHIFT | Qt::Key_Return));
    insert->addAction(tr("&Header && Footer…"), this, &MainWindow::editHeaderFooter);
    insert->addAction(tr("&Date"), this, &MainWindow::insertDate);
    insert->addSeparator();
    QMenu *wrap = insert->addMenu(tr("Image Text &Wrap"));
    auto *wrapGroup = new QActionGroup(this);
    m_wrapNone = wrap->addAction(tr("&None (Overlay)"));
    m_wrapRectangular = wrap->addAction(tr("&Rectangular"));
    for (QAction *action : {m_wrapNone, m_wrapRectangular}) {
        action->setCheckable(true);
        wrapGroup->addAction(action);
    }
    connect(m_wrapNone, &QAction::triggered, this, [this] {
        m_editor->setObjectWrap(m_canvas->selectedObjectId(), QStringLiteral("none"));
    });
    connect(m_wrapRectangular, &QAction::triggered, this, [this] {
        m_editor->setObjectWrap(m_canvas->selectedObjectId(), QStringLiteral("rectangular"));
    });
    insert->addAction(tr("Increase Standof&f"), this, [this] {
        m_editor->adjustObjectStandoff(m_canvas->selectedObjectId(), 4);
    }, QKeySequence(Qt::CTRL | Qt::ALT | Qt::Key_BracketRight));
    insert->addAction(tr("Decrease Standoff"), this, [this] {
        m_editor->adjustObjectStandoff(m_canvas->selectedObjectId(), -4);
    }, QKeySequence(Qt::CTRL | Qt::ALT | Qt::Key_BracketLeft));
    insert->addSeparator();
    insert->addAction(tr("Delete Image"), this, [this] {
        if (!m_canvas->selectedObjectId().isEmpty())
            m_editor->deleteObject(m_canvas->selectedObjectId());
    });

    // View
    QMenu *view = menuBar()->addMenu(tr("&View"));
    QAction *navigator = view->addAction(tr("Show &Navigator"));
    navigator->setCheckable(true);
    navigator->setShortcut(QKeySequence(Qt::CTRL | Qt::ALT | Qt::Key_0));
    connect(navigator, &QAction::toggled, this, [this](bool visible) {
        m_navigatorDock->setVisible(visible);
        if (visible) rebuildNavigator();
    });
    view->addSeparator();
    view->addAction(tr("Zoom &In"), m_canvas, &PageCanvas::zoomIn, QKeySequence::ZoomIn);
    view->addAction(tr("Zoom &Out"), m_canvas, &PageCanvas::zoomOut, QKeySequence::ZoomOut);
    view->addAction(tr("&Actual Size"), this, [this] { m_canvas->setZoom(1.0); },
                    QKeySequence(Qt::CTRL | Qt::Key_0));
    view->addAction(tr("Fit &Page"), m_canvas, &PageCanvas::fitPage,
                    QKeySequence(Qt::CTRL | Qt::SHIFT | Qt::Key_0));
    view->addAction(tr("Fit &Width"), m_canvas, &PageCanvas::fitWidth);

    // Help
    QMenu *help = menuBar()->addMenu(tr("&Help"));
    help->addAction(tr("Lucerne &Help"), this, [] {
        QDesktopServices::openUrl(
            QUrl(QStringLiteral("https://github.com/L-K-M/Lucerne#readme")));
    }, QKeySequence::HelpContents);
    help->addAction(tr("&About Lucerne"), this, [this] {
        QMessageBox::about(this, tr("About Lucerne"),
            tr("<h3>Lucerne</h3>"
               "<p>A ClarisWorks-style word editor.</p>"
               "<p>Letters with rulers, tabs, and genuine free placement of "
               "images. Documents are saved as “.luce” — a ZIP package you can "
               "always open.</p>"
               "<p>Version %1</p>").arg(QCoreApplication::applicationVersion()));
    });
}

// MARK: - Toolbar

void MainWindow::buildToolbar() {
    QToolBar *bar = addToolBar(tr("Format"));
    bar->setMovable(false);
    bar->setFloatable(false);
    bar->setToolButtonStyle(Qt::ToolButtonIconOnly);

    m_styleCombo = new QComboBox(bar);
    m_styleCombo->setMinimumWidth(130);
    m_styleCombo->setToolTip(tr("Paragraph style"));
    bar->addWidget(m_styleCombo);
    connect(m_styleCombo, QOverload<int>::of(&QComboBox::activated), this, [this](int index) {
        applyCurrentStyle(m_styleCombo->itemData(index).toString());
    });

    bar->addSeparator();

    m_fontCombo = new QFontComboBox(bar);
    m_fontCombo->setMinimumWidth(150);
    m_fontCombo->setToolTip(tr("Typeface"));
    bar->addWidget(m_fontCombo);
    connect(m_fontCombo, &QFontComboBox::currentFontChanged, this, [this](const QFont &font) {
        if (m_syncingControls) return;
        QTextCharFormat fmt;
        fmt.setFontFamilies({font.family()});
        fmt.setProperty(Props::ModelFont, font.family());
        m_canvas->mergeCharFormat(fmt);
    });

    m_sizeCombo = new QComboBox(bar);
    m_sizeCombo->setEditable(true);
    m_sizeCombo->setMinimumWidth(64);
    m_sizeCombo->setToolTip(tr("Font size in points"));
    for (const int size : {9, 10, 11, 12, 14, 18, 24, 36, 48, 72})
        m_sizeCombo->addItem(QString::number(size));
    bar->addWidget(m_sizeCombo);
    connect(m_sizeCombo, &QComboBox::textActivated, this, [this](const QString &text) {
        if (m_syncingControls) return;
        bool ok = false;
        const double size = QLocale().toDouble(text, &ok);
        if (!ok || size <= 0) return;
        QTextCharFormat fmt;
        fmt.setFontPointSize(size);
        m_canvas->mergeCharFormat(fmt);
    });

    bar->addSeparator();
    m_boldAction->setIcon(QIcon::fromTheme(QStringLiteral("format-text-bold")));
    m_italicAction->setIcon(QIcon::fromTheme(QStringLiteral("format-text-italic")));
    m_underlineAction->setIcon(QIcon::fromTheme(QStringLiteral("format-text-underline")));
    bar->addAction(m_boldAction);
    bar->addAction(m_italicAction);
    bar->addAction(m_underlineAction);

    m_colorButton = new QToolButton(bar);
    m_colorButton->setToolTip(tr("Text color"));
    m_colorButton->setIcon(QIcon::fromTheme(QStringLiteral("color-select-symbolic"),
                                            QIcon::fromTheme(QStringLiteral("applications-graphics"))));
    connect(m_colorButton, &QToolButton::clicked, this, &MainWindow::chooseColor);
    bar->addWidget(m_colorButton);

    bar->addSeparator();
    const char *alignIcons[4] = {"format-justify-left", "format-justify-center",
                                 "format-justify-right", "format-justify-fill"};
    for (int i = 0; i < 4; ++i) {
        m_alignActions[i]->setIcon(QIcon::fromTheme(QLatin1String(alignIcons[i])));
        bar->addAction(m_alignActions[i]);
    }

    bar->addSeparator();
    auto *bulletButton = new QToolButton(bar);
    bulletButton->setIcon(QIcon::fromTheme(QStringLiteral("view-list-bullet"),
                                           QIcon::fromTheme(QStringLiteral("format-list-unordered"))));
    bulletButton->setToolTip(tr("Bulleted list"));
    connect(bulletButton, &QToolButton::clicked, this, [this] {
        m_editor->toggleList(m_canvas->textCursor(), false, QString());
    });
    bar->addWidget(bulletButton);
    auto *numberButton = new QToolButton(bar);
    numberButton->setIcon(QIcon::fromTheme(QStringLiteral("view-list-ordered"),
                                           QIcon::fromTheme(QStringLiteral("format-list-ordered"))));
    numberButton->setToolTip(tr("Numbered list"));
    connect(numberButton, &QToolButton::clicked, this, [this] {
        m_editor->toggleList(m_canvas->textCursor(), true, QString());
    });
    bar->addWidget(numberButton);

    bar->addSeparator();
    m_spacingCombo = new QComboBox(bar);
    m_spacingCombo->setToolTip(tr("Line spacing"));
    for (const double multiple : {1.0, 1.15, 1.5, 2.0})
        m_spacingCombo->addItem(QString::number(multiple), multiple);
    bar->addWidget(m_spacingCombo);
    connect(m_spacingCombo, QOverload<int>::of(&QComboBox::activated), this, [this](int index) {
        if (m_syncingControls) return;
        m_canvas->setBlockLineSpacing(m_spacingCombo->itemData(index).toDouble());
    });
}

// MARK: - Status bar / find bar / navigator

void MainWindow::buildStatusBar() {
    m_statusLabel = new QLabel(this);
    statusBar()->addWidget(m_statusLabel, 1);

    m_pageLabel = new QLabel(this);
    statusBar()->addPermanentWidget(m_pageLabel);

    auto *zoomOut = new QToolButton(this);
    zoomOut->setText(QStringLiteral("−"));
    zoomOut->setAutoRaise(true);
    connect(zoomOut, &QToolButton::clicked, m_canvas, &PageCanvas::zoomOut);
    m_zoomLabel = new QToolButton(this);
    m_zoomLabel->setAutoRaise(true);
    m_zoomLabel->setToolTip(tr("Click to reset to 100%"));
    connect(m_zoomLabel, &QToolButton::clicked, this, [this] { m_canvas->setZoom(1.0); });
    auto *zoomIn = new QToolButton(this);
    zoomIn->setText(QStringLiteral("+"));
    zoomIn->setAutoRaise(true);
    connect(zoomIn, &QToolButton::clicked, m_canvas, &PageCanvas::zoomIn);
    statusBar()->addPermanentWidget(zoomOut);
    statusBar()->addPermanentWidget(m_zoomLabel);
    statusBar()->addPermanentWidget(zoomIn);
    updateStatus();
}

void MainWindow::buildFindBar() {
    m_findBar = new QWidget(this);
    auto *row = new QHBoxLayout(m_findBar);
    row->setContentsMargins(8, 4, 8, 4);
    row->setSpacing(6);

    m_findField = new QLineEdit(m_findBar);
    m_findField->setPlaceholderText(tr("Find"));
    m_findField->setClearButtonEnabled(true);
    row->addWidget(m_findField, 2);
    connect(m_findField, &QLineEdit::returnPressed, this, [this] { findNext(false); });

    auto *previous = new QToolButton(m_findBar);
    previous->setIcon(QIcon::fromTheme(QStringLiteral("go-up")));
    previous->setToolTip(tr("Find previous"));
    connect(previous, &QToolButton::clicked, this, [this] { findNext(true); });
    row->addWidget(previous);
    auto *next = new QToolButton(m_findBar);
    next->setIcon(QIcon::fromTheme(QStringLiteral("go-down")));
    next->setToolTip(tr("Find next"));
    connect(next, &QToolButton::clicked, this, [this] { findNext(false); });
    row->addWidget(next);

    auto *caseButton = new QToolButton(m_findBar);
    caseButton->setText(tr("Aa"));
    caseButton->setCheckable(true);
    caseButton->setToolTip(tr("Match case"));
    m_findCaseAction = new QAction(this);
    m_findCaseAction->setCheckable(true);
    connect(caseButton, &QToolButton::toggled, m_findCaseAction, &QAction::setChecked);
    row->addWidget(caseButton);

    m_replaceField = new QLineEdit(m_findBar);
    m_replaceField->setPlaceholderText(tr("Replace with"));
    m_replaceField->setClearButtonEnabled(true);
    row->addWidget(m_replaceField, 2);
    auto *replace = new QToolButton(m_findBar);
    replace->setText(tr("Replace"));
    connect(replace, &QToolButton::clicked, this, [this] { replaceCurrent(); });
    row->addWidget(replace);
    auto *replaceAllButton = new QToolButton(m_findBar);
    replaceAllButton->setText(tr("All"));
    replaceAllButton->setToolTip(tr("Replace all"));
    connect(replaceAllButton, &QToolButton::clicked, this, [this] { replaceAll(); });
    row->addWidget(replaceAllButton);

    m_findStatus = new QLabel(m_findBar);
    row->addWidget(m_findStatus);

    auto *closeButton = new QToolButton(m_findBar);
    closeButton->setIcon(QIcon::fromTheme(QStringLiteral("window-close")));
    closeButton->setAutoRaise(true);
    connect(closeButton, &QToolButton::clicked, this, [this] {
        m_findBar->setVisible(false);
        m_canvas->setFocus();
    });
    row->addWidget(closeButton);

    m_findBar->setVisible(false);
    // Esc anywhere in the bar closes it.
    auto *escape = new QAction(m_findBar);
    escape->setShortcut(QKeySequence(Qt::Key_Escape));
    escape->setShortcutContext(Qt::WidgetWithChildrenShortcut);
    connect(escape, &QAction::triggered, this, [this] {
        m_findBar->setVisible(false);
        m_canvas->setFocus();
    });
    m_findBar->addAction(escape);
}

void MainWindow::buildNavigator() {
    m_navigatorDock = new QDockWidget(tr("Contents"), this);
    m_navigatorDock->setAllowedAreas(Qt::LeftDockWidgetArea | Qt::RightDockWidgetArea);
    m_navigator = new QListWidget(m_navigatorDock);
    m_navigator->setFrameShape(QFrame::NoFrame);
    m_navigatorDock->setWidget(m_navigator);
    addDockWidget(Qt::LeftDockWidgetArea, m_navigatorDock);
    m_navigatorDock->setVisible(false);
    connect(m_navigator, &QListWidget::itemActivated, this, [this](QListWidgetItem *item) {
        m_canvas->revealPosition(item->data(Qt::UserRole).toInt());
    });
    connect(m_navigator, &QListWidget::itemClicked, this, [this](QListWidgetItem *item) {
        m_canvas->revealPosition(item->data(Qt::UserRole).toInt());
    });
}

void MainWindow::rebuildNavigator() {
    if (!m_navigatorDock || !m_navigatorDock->isVisible()) return;
    m_navigator->clear();
    for (QTextBlock block = m_editor->document()->begin(); block.isValid();
         block = block.next()) {
        const QString role = block.charFormat().stringProperty(Props::StyleRole);
        const QString hint = m_editor->model().resolvedStyle(role).markdown;
        int level = 0;
        if (hint == QLatin1String("h1")) level = 1;
        else if (hint == QLatin1String("h2")) level = 2;
        else if (hint == QLatin1String("h3")) level = 3;
        else if (hint == QLatin1String("h4")) level = 4;
        if (level == 0) continue;
        const QString title = block.text().trimmed();
        if (title.isEmpty()) continue;
        auto *item = new QListWidgetItem(
            QString(3 * (level - 1), QLatin1Char(' ')) + title, m_navigator);
        item->setData(Qt::UserRole, block.position());
        if (level == 1) {
            QFont font = item->font();
            font.setBold(true);
            item->setFont(font);
        }
    }
}

// MARK: - File

bool MainWindow::openPath(const QString &path) {
    // Route into an empty untitled window, else a fresh one.
    MainWindow *target = this;
    if (!m_editor->filePath().isEmpty() || m_editor->isModified()
        || !m_editor->document()->isEmpty())
        target = newWindow();
    QString error;
    if (!target->m_editor->loadFile(path, &error)) {
        QMessageBox::warning(this, tr("Couldn’t open the letter"),
                             tr("%1\n\n%2").arg(path, error));
        if (target != this) target->close();
        return false;
    }
    WelcomeDialog::addRecentFile(path);
    target->updateTitle();
    target->syncFormatControls();
    target->rebuildStyleControls();
    target->scheduleWordCount();
    target->m_canvas->revealPosition(0);
    return true;
}

void MainWindow::loadSampleLetter() {
    m_editor->loadModel(DefaultDocuments::sampleLetter(),
                        DefaultDocuments::sampleLetterImages());
    updateTitle();
    rebuildStyleControls();
    scheduleWordCount();
}

void MainWindow::newDocument() {
    MainWindow *window = newWindow();
    window->m_editor->loadModel(DefaultDocuments::empty(), {});
    window->updateTitle();
}

void MainWindow::openDocument() {
    const QString path = QFileDialog::getOpenFileName(
        this, tr("Open Letter"), QString(), tr("Lucerne letters (*.luce)"));
    if (!path.isEmpty()) openPath(path);
}

bool MainWindow::saveDocument() {
    if (m_editor->filePath().isEmpty()) return saveDocumentAs();
    QString error;
    if (!m_editor->saveFile(m_editor->filePath(), &error)) {
        QMessageBox::warning(this, tr("Couldn’t save the letter"), error);
        return false;
    }
    WelcomeDialog::addRecentFile(m_editor->filePath());
    updateTitle();
    return true;
}

bool MainWindow::saveDocumentAs() {
    QString path = QFileDialog::getSaveFileName(
        this, tr("Save Letter"), m_editor->displayName() + QStringLiteral(".luce"),
        tr("Lucerne letters (*.luce)"));
    if (path.isEmpty()) return false;
    if (!path.endsWith(QLatin1String(".luce"))) path += QLatin1String(".luce");
    QString error;
    if (!m_editor->saveFile(path, &error)) {
        QMessageBox::warning(this, tr("Couldn’t save the letter"), error);
        return false;
    }
    WelcomeDialog::addRecentFile(path);
    updateTitle();
    return true;
}

bool MainWindow::maybeSave() {
    if (!m_editor->isModified()) return true;
    const auto answer = QMessageBox::warning(
        this, tr("Save changes?"),
        tr("“%1” has unsaved changes. Save them before closing?").arg(m_editor->displayName()),
        QMessageBox::Save | QMessageBox::Discard | QMessageBox::Cancel, QMessageBox::Save);
    if (answer == QMessageBox::Save) return saveDocument();
    return answer == QMessageBox::Discard;
}

void MainWindow::closeEvent(QCloseEvent *event) {
    if (!maybeSave()) {
        event->ignore();
        return;
    }
    openWindows().removeAll(this);
    event->accept();
}

void MainWindow::exportPdf() {
    QString path = QFileDialog::getSaveFileName(
        this, tr("Export as PDF"), m_editor->displayName() + QStringLiteral(".pdf"),
        tr("PDF (*.pdf)"));
    if (path.isEmpty()) return;
    if (!path.endsWith(QLatin1String(".pdf"))) path += QLatin1String(".pdf");

    const PageConfig &page = m_editor->model().page;
    QPdfWriter writer(path);
    writer.setPageSize(QPageSize(QSizeF(page.width, page.height), QPageSize::Point,
                                 QString(), QPageSize::ExactMatch));
    writer.setPageMargins(QMarginsF(0, 0, 0, 0));
    writer.setResolution(72);
    writer.setTitle(m_editor->displayName());

    QPainter painter;
    if (!painter.begin(&writer)) {
        QMessageBox::warning(this, tr("Couldn’t export"),
                             tr("The PDF file couldn’t be created at %1.").arg(path));
        return;
    }
    const int pages = m_editor->layout()->pageCount();
    for (int i = 0; i < pages; ++i) {
        if (i > 0) writer.newPage();
        m_editor->renderPage(&painter, i);
    }
    painter.end();
    if (!QFileInfo::exists(path) || QFileInfo(path).size() == 0) {
        QMessageBox::warning(this, tr("Couldn’t export"),
                             tr("The PDF file couldn’t be written at %1.").arg(path));
        return;
    }
    statusBar()->showMessage(tr("Exported %1").arg(path), 4000);
}

void MainWindow::exportMarkdown() {
    QString path = QFileDialog::getSaveFileName(
        this, tr("Export as Markdown"), m_editor->displayName() + QStringLiteral(".md"),
        tr("Markdown (*.md)"));
    if (path.isEmpty()) return;
    QSaveFile file(path);
    if (!file.open(QIODevice::WriteOnly)
        || file.write(MarkdownExporter::exportModel(m_editor->snapshotModel()).toUtf8()) < 0
        || !file.commit()) {
        QMessageBox::warning(this, tr("Couldn’t export"), file.errorString());
        return;
    }
    statusBar()->showMessage(tr("Exported %1").arg(path), 4000);
}

void MainWindow::printDocument() {
    QPrinter printer(QPrinter::HighResolution);
    const PageConfig &page = m_editor->model().page;
    printer.setPageSize(QPageSize(QSizeF(page.width, page.height), QPageSize::Point,
                                  QString(), QPageSize::ExactMatch));
    printer.setPageMargins(QMarginsF(0, 0, 0, 0));
    // Paint in full-page coordinates: without this the painter's origin sits at
    // the printer's hardware margins and every page renders offset.
    printer.setFullPage(true);
    printer.setDocName(m_editor->displayName());
    QPrintDialog dialog(&printer, this);
    if (dialog.exec() != QDialog::Accepted) return;

    QPainter painter(&printer);
    // Scale from points to the printer's device resolution.
    const double scale = printer.resolution() / 72.0;
    painter.scale(scale, scale);
    const int pages = m_editor->layout()->pageCount();
    for (int i = 0; i < pages; ++i) {
        if (i > 0) printer.newPage();
        m_editor->renderPage(&painter, i);
    }
    painter.end();
}

void MainWindow::documentSetup() {
    const bool metric = QSettings().value(QStringLiteral("rulerUnit"),
                                          QStringLiteral("centimeters"))
                            .toString() != QLatin1String("inches");
    DocumentSetupDialog dialog(m_editor->model().page, metric, this);
    if (dialog.exec() != QDialog::Accepted) return;
    m_editor->setPageConfig(dialog.pageConfig());
}

// MARK: - Format plumbing

void MainWindow::applyCurrentStyle(const QString &role) {
    m_editor->applyStyle(m_canvas->textCursor(), role);
    syncFormatControls();
    m_canvas->setFocus();
}

void MainWindow::chooseColor() {
    const QColor current = m_canvas->currentCharFormat().foreground().color();
    const QColor color = QColorDialog::getColor(current.isValid() ? current : Qt::black,
                                                this, tr("Text Color"));
    if (!color.isValid()) return;
    QTextCharFormat fmt;
    fmt.setForeground(color);
    fmt.setProperty(Props::ModelColor, DocumentBridge::colorToHex(color));
    m_canvas->mergeCharFormat(fmt);
}

void MainWindow::rebuildStyleControls() {
    if (!m_styleCombo) return;
    m_syncingControls = true;
    m_styleCombo->clear();
    for (const QString &role : m_editor->model().orderedStyleRoles())
        m_styleCombo->addItem(m_editor->styles().value(role).name, role);
    m_syncingControls = false;
    syncFormatControls();
}

void MainWindow::syncFormatControls() {
    if (!m_styleCombo) return;
    m_syncingControls = true;

    const QString role = m_editor->styleRoleAt(m_canvas->textCursor());
    const int styleIndex = m_styleCombo->findData(role);
    if (styleIndex >= 0) m_styleCombo->setCurrentIndex(styleIndex);

    const QTextCharFormat format = m_canvas->currentCharFormat();
    const QFont font = format.font();
    m_fontCombo->setCurrentFont(QFont(
        format.hasProperty(Props::ModelFont) ? format.stringProperty(Props::ModelFont)
                                             : font.family()));
    m_sizeCombo->setCurrentText(QString::number(font.pointSizeF()));
    m_boldAction->setChecked(font.bold());
    m_italicAction->setChecked(font.italic());
    m_underlineAction->setChecked(format.fontUnderline());

    const Qt::Alignment alignment = m_canvas->textCursor().blockFormat().alignment();
    int alignIndex = 0;
    if (alignment & Qt::AlignHCenter) alignIndex = 1;
    else if (alignment & Qt::AlignRight) alignIndex = 2;
    else if (alignment & Qt::AlignJustify) alignIndex = 3;
    for (int i = 0; i < 4; ++i) m_alignActions[i]->setChecked(i == alignIndex);

    const QTextBlockFormat bf = m_canvas->textCursor().blockFormat();
    const double spacing = bf.lineHeightType() == QTextBlockFormat::ProportionalHeight
        ? bf.lineHeight() / 100.0 : 1.0;
    const int spacingIndex = m_spacingCombo->findData(spacing);
    if (spacingIndex >= 0) m_spacingCombo->setCurrentIndex(spacingIndex);

    // Wrap radios follow the selected image.
    const QString selected = m_canvas->selectedObjectId();
    const PlacedObject *object = selected.isEmpty() ? nullptr
                                                    : m_editor->objectById(selected);
    m_wrapNone->setEnabled(object != nullptr);
    m_wrapRectangular->setEnabled(object != nullptr);
    if (object) {
        m_wrapNone->setChecked(object->wrapMode() == PlacedObject::Wrap::None);
        m_wrapRectangular->setChecked(object->wrapMode() != PlacedObject::Wrap::None);
    }

    m_syncingControls = false;
    updateStatus();
}

// MARK: - Insert

void MainWindow::insertImageFromFile() {
    const QString path = QFileDialog::getOpenFileName(
        this, tr("Insert Image"), QString(),
        tr("Images (*.png *.jpg *.jpeg *.gif *.bmp *.webp *.tiff)"));
    if (path.isEmpty()) return;
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly)) return;
    const int page = m_canvas->currentPage() - 1;
    const PageConfig &config = m_editor->model().page;
    const QString id = m_editor->insertImage(
        file.readAll(), QFileInfo(path).fileName(), page,
        QPointF(config.width / 2, config.height / 2.5));
    if (id.isEmpty()) {
        QMessageBox::warning(this, tr("Couldn’t insert the image"),
                             tr("The file doesn’t look like a readable image."));
        return;
    }
    m_canvas->selectObject(id);
}

void MainWindow::insertDate() {
    QTextCursor cursor = m_canvas->textCursor();
    cursor.insertText(QLocale().toString(QDate::currentDate(), QLocale::LongFormat));
    m_canvas->setTextCursor(cursor);
}

void MainWindow::editHeaderFooter() {
    const DocumentModel &model = m_editor->model();
    HeaderFooterDialog dialog(model.header, model.footer, model.pageNumberStart, this);
    if (dialog.exec() != QDialog::Accepted) return;
    m_editor->setFurniture(dialog.header(), dialog.footer(), dialog.pageNumberStart());
}

// MARK: - Find

void MainWindow::findNext(bool backwards) {
    const QString needle = m_findField ? m_findField->text() : QString();
    if (needle.isEmpty()) return;
    QTextDocument *doc = m_editor->document();
    QTextDocument::FindFlags flags;
    if (backwards) flags |= QTextDocument::FindBackward;
    if (m_findCaseAction->isChecked()) flags |= QTextDocument::FindCaseSensitively;

    QTextCursor from = m_canvas->textCursor();
    QTextCursor found = doc->find(needle, from, flags);
    if (found.isNull()) {
        // Wrap around.
        QTextCursor wrapped(doc);
        if (backwards) wrapped.movePosition(QTextCursor::End);
        found = doc->find(needle, wrapped, flags);
    }
    if (found.isNull()) {
        m_findStatus->setText(tr("Not found"));
        QApplication::beep();
        return;
    }
    m_findStatus->clear();
    m_canvas->setTextCursor(found);
    m_canvas->ensureCursorVisible();
}

void MainWindow::replaceCurrent() {
    QTextCursor cursor = m_canvas->textCursor();
    const QString needle = m_findField->text();
    if (needle.isEmpty()) return;
    const Qt::CaseSensitivity sensitivity =
        m_findCaseAction->isChecked() ? Qt::CaseSensitive : Qt::CaseInsensitive;
    if (cursor.hasSelection()
        && QString::compare(cursor.selectedText(), needle, sensitivity) == 0) {
        cursor.insertText(m_replaceField->text());
        m_canvas->setTextCursor(cursor);
    }
    findNext(false);
}

void MainWindow::replaceAll() {
    const QString needle = m_findField->text();
    if (needle.isEmpty()) return;
    QTextDocument *doc = m_editor->document();
    QTextDocument::FindFlags flags;
    if (m_findCaseAction->isChecked()) flags |= QTextDocument::FindCaseSensitively;

    QTextCursor sweep(doc);
    sweep.beginEditBlock();
    QTextCursor found = doc->find(needle, 0, flags);
    int count = 0;
    while (!found.isNull()) {
        found.insertText(m_replaceField->text());
        ++count;
        found = doc->find(needle, found, flags);
    }
    sweep.endEditBlock();
    m_findStatus->setText(count == 1 ? tr("Replaced 1 match")
                                     : tr("Replaced %1 matches").arg(count));
}

// MARK: - Status

void MainWindow::updateTitle() {
    setWindowTitle(QStringLiteral("%1[*] — Lucerne").arg(m_editor->displayName()));
    setWindowModified(m_editor->isModified());
}

void MainWindow::scheduleWordCount() {
    if (m_wordCountTimer) m_wordCountTimer->start();
}

void MainWindow::updateStatus() {
    if (!m_pageLabel) return;
    const int pages = m_editor->layout()->pageCount();
    const int current = m_canvas->currentPage();
    QStringList parts;
    if (!m_canvas->selectedObjectId().isEmpty()) {
        m_statusLabel->setText(tr("Image selected — drag to move · drag a corner to "
                                  "resize (Shift for free aspect) · Delete to remove"));
    } else {
        const QString styleName =
            m_editor->styles().value(m_editor->styleRoleAt(m_canvas->textCursor())).name;
        m_statusLabel->setText(styleName);
    }
    parts << (pages == 1 ? tr("1 page") : tr("Page %1 of %2").arg(current).arg(pages));
    parts << (m_wordCount == 1 ? tr("1 word") : tr("%1 words").arg(m_wordCount));
    m_pageLabel->setText(parts.join(QStringLiteral("  ·  ")));
    m_zoomLabel->setText(QStringLiteral("%1%").arg(qRound(m_canvas->zoom() * 100)));
}

} // namespace lucerne
