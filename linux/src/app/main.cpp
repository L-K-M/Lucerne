// Lucerne for Linux — application bootstrap. Native Qt 6 widgets, following
// the system theme (light or dark) so the app feels at home on Ubuntu; the
// document pages themselves stay paper-white.

#include "app/MainWindow.h"
#include "app/WelcomeDialog.h"
#include "core/StyleLibrary.h"

#include <QApplication>
#include <QCommandLineParser>
#include <QFileDialog>
#include <QFont>
#include <QIcon>

int main(int argc, char **argv) {
    QApplication app(argc, argv);
    QCoreApplication::setOrganizationName(QStringLiteral("Lucerne"));
    QCoreApplication::setApplicationName(QStringLiteral("Lucerne"));
    QCoreApplication::setApplicationVersion(QStringLiteral(LUCERNE_VERSION));
    QGuiApplication::setApplicationDisplayName(QStringLiteral("Lucerne"));
    // Ties the Wayland/X11 window to the installed .desktop entry (icon, dock).
    QGuiApplication::setDesktopFileName(QStringLiteral("ch.lkmc.Lucerne"));
    QGuiApplication::setWindowIcon(QIcon(QStringLiteral(":/icons/lucerne.png")));

    // Mac documents name Mac faces; map them onto their metric-compatible
    // Linux substitutes so letters look right without editing the file (the
    // file keeps its original font names — see DocumentBridge Props::ModelFont).
    QFont::insertSubstitutions(QStringLiteral("Helvetica"),
                               {QStringLiteral("Liberation Sans"),
                                QStringLiteral("Nimbus Sans"),
                                QStringLiteral("DejaVu Sans")});
    QFont::insertSubstitutions(QStringLiteral("Menlo"),
                               {QStringLiteral("Liberation Mono"),
                                QStringLiteral("DejaVu Sans Mono")});
    QFont::insertSubstitutions(QStringLiteral("Georgia"),
                               {QStringLiteral("Liberation Serif"),
                                QStringLiteral("DejaVu Serif")});

    QCommandLineParser parser;
    parser.setApplicationDescription(
        QStringLiteral("A ClarisWorks-style word editor with genuine free "
                       "placement of images and live text flow."));
    parser.addHelpOption();
    parser.addVersionOption();
    parser.addPositionalArgument(QStringLiteral("files"),
                                 QStringLiteral("Letters (.luce) to open."),
                                 QStringLiteral("[files…]"));
    const QCommandLineOption sampleOption(
        QStringLiteral("sample"),
        QStringLiteral("Open the built-in sample letter (used by tests and demos)."));
    parser.addOption(sampleOption);
    parser.process(app);

    // The style library seeds new letters; first launch stocks the shelf.
    lucerne::StyleLibrary::shared()->seedStarterLibraryIfNeeded();

    const QStringList files = parser.positionalArguments();
    if (parser.isSet(sampleOption)) {
        lucerne::MainWindow::newWindow()->loadSampleLetter();
    } else if (!files.isEmpty()) {
        lucerne::MainWindow *window = lucerne::MainWindow::newWindow();
        bool openedAny = false;
        for (const QString &path : files)
            openedAny = window->openPath(path) || openedAny;
        if (!openedAny) window->show();
    } else {
        // The welcome screen is the start experience (no auto-blank document).
        lucerne::WelcomeDialog welcome;
        if (welcome.exec() != QDialog::Accepted) return 0;
        lucerne::MainWindow *window = lucerne::MainWindow::newWindow();
        switch (welcome.choice()) {
        case lucerne::WelcomeDialog::Choice::Open: {
            const QString path = QFileDialog::getOpenFileName(
                window, QObject::tr("Open Letter"), QString(),
                QObject::tr("Lucerne letters (*.luce)"));
            if (!path.isEmpty()) window->openPath(path);
            break;
        }
        case lucerne::WelcomeDialog::Choice::OpenRecent:
            window->openPath(welcome.recentPath());
            break;
        case lucerne::WelcomeDialog::Choice::SampleLetter:
            window->loadSampleLetter();
            break;
        default:
            break;   // New Letter: the fresh window already is one
        }
    }

    return app.exec();
}
