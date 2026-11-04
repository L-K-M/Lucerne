// PDF export is transactional: the destination is replaced only after every
// page and the trailer are on disk, and a write failure — even one QPdfWriter
// does not report — must leave a previous export untouched.

#include "app/MainWindow.h"
#include "app/PdfExport.h"
#include "core/DefaultDocuments.h"

#include <QAction>
#include <QApplication>
#include <QFile>
#include <QFileDialog>
#include <QMessageBox>
#include <QScopeGuard>
#include <QSettings>
#include <QStatusBar>
#include <QTemporaryDir>
#include <QTimer>
#include <QtTest>

#ifdef Q_OS_UNIX
#include <csignal>
#include <sys/resource.h>
#endif

using namespace lucerne;

class tst_pdf : public QObject {
    Q_OBJECT

    // Redirected in initTestCase so the window's persisted state stays isolated.
    QTemporaryDir m_settings;

private slots:
    void initTestCase() {
        QVERIFY(m_settings.isValid());
        QApplication::setAttribute(Qt::AA_DontUseNativeDialogs);
        QCoreApplication::setOrganizationName(QStringLiteral("LucernePdfTests"));
        QSettings::setDefaultFormat(QSettings::IniFormat);
        QSettings::setPath(QSettings::IniFormat, QSettings::UserScope,
                           m_settings.path());
    }

    void completeMultipagePdfReplacesExistingFile() {
        QTemporaryDir directory;
        QVERIFY(directory.isValid());
        const QString path = directory.filePath(QStringLiteral("letter.pdf"));
        QFile file(path);
        QVERIFY(file.open(QIODevice::WriteOnly));
        file.write("old PDF");
        file.close();

        Editor editor;
        auto model = DefaultDocuments::sampleLetter();
        QVERIFY2(model.body.size() > 1,
                 "The sample letter needs a second paragraph to break onto a page.");
        model.body[1].pageBreakBefore = true;
        editor.loadModel(model, DefaultDocuments::sampleLetterImages());
        QCOMPARE(editor.layout()->pageCount(), 2);
        QString error;
        QVERIFY2(PdfExport::write(editor, path, &error), qPrintable(error));
        QVERIFY(file.open(QIODevice::ReadOnly));
        const QByteArray pdf = file.readAll();
        QVERIFY(pdf.startsWith("%PDF-"));
        QVERIFY(pdf.trimmed().endsWith("%%EOF"));
        // Qt has serialized page objects with both separators; the /Pages tree
        // root matches neither pattern.
        QCOMPARE(pdf.count("/Type /Page\n") + pdf.count("/Type /Page "), 2);
        QVERIFY(!editor.isModified());
        QVERIFY(editor.filePath().isEmpty());
    }

    void invalidDestinationReturnsAnError() {
        Editor editor;
        QTemporaryDir directory;
        QString error;
        QVERIFY(!PdfExport::write(editor,
            directory.filePath(QStringLiteral("missing/letter.pdf")), &error));
        QVERIFY(!error.isEmpty());
    }

    void midWriteFailurePreservesExistingFile() {
        QTemporaryDir directory;
        QVERIFY(directory.isValid());
        const QString path = directory.filePath(QStringLiteral("letter.pdf"));
        const QByteArray original("previous complete PDF export");
        QFile file(path);
        QVERIFY(file.open(QIODevice::WriteOnly));
        QCOMPARE(file.write(original), original.size());
        file.close();

        Editor editor;
        editor.loadModel(DefaultDocuments::sampleLetter(),
                         DefaultDocuments::sampleLetterImages());
        QVERIFY2(editor.layout()->pageCount() > 0,
                 "The sample letter must produce at least one page.");

#ifdef Q_OS_UNIX
        struct rlimit savedLimit;
        if (getrlimit(RLIMIT_FSIZE, &savedLimit) != 0)
            QSKIP("RLIMIT_FSIZE is not available on this system.");
        const auto savedSignal = std::signal(SIGXFSZ, SIG_IGN);
        if (savedSignal == SIG_ERR)
            QSKIP("SIGXFSZ cannot be ignored on this system.");
        const auto restore = qScopeGuard([&] {
            setrlimit(RLIMIT_FSIZE, &savedLimit);
            std::signal(SIGXFSZ, savedSignal);
        });
        // Simulate the disk filling after output began: the kernel lets at most
        // 512 bytes land in the temporary file, then writes fail or run short.
        struct rlimit limit = savedLimit;
        limit.rlim_cur = 512;
        if (setrlimit(RLIMIT_FSIZE, &limit) != 0)
            QSKIP("RLIMIT_FSIZE cannot be lowered here.");

        QString error;
        QVERIFY2(!PdfExport::write(editor, path, &error),
                 "Export must fail once the disk is full mid-write.");
        QVERIFY2(!error.isEmpty(), "A failed export must report a reason.");
#else
        QSKIP("RLIMIT_FSIZE requires a POSIX system.");
#endif

        QVERIFY(file.open(QIODevice::ReadOnly));
        QCOMPARE(file.readAll(), original);
    }

    void failedExportPreservesExistingFile() {
        QTemporaryDir directory;
        QVERIFY(directory.isValid());
        const QString path = directory.filePath(QStringLiteral("letter.pdf"));
        const QByteArray original("previous PDF");
        QFile file(path);
        QVERIFY(file.open(QIODevice::WriteOnly));
        QCOMPARE(file.write(original), original.size());
        file.close();

        const auto permissions = QFile::permissions(directory.path());
        QVERIFY(QFile::setPermissions(directory.path(),
            QFile::ReadOwner | QFile::ExeOwner));
        const auto restorePermissions = qScopeGuard([&] {
            QFile::setPermissions(directory.path(), permissions);
        });

        QFile probe(directory.filePath(QStringLiteral("probe")));
        if (probe.open(QIODevice::WriteOnly)) {
            probe.close();
            QSKIP("Directory write restrictions are not enforced for this user.");
        }

        MainWindow window;
        QAction *exportAction = nullptr;
        for (QAction *action : window.findChildren<QAction *>()) {
            if (action->text() == QStringLiteral("Export as &PDF…")) exportAction = action;
        }
        QVERIFY(exportAction);

        bool chosePath = false;
        bool sawError = false;
        QString errorText;
        QTimer dialogs;
        connect(&dialogs, &QTimer::timeout, &window, [&] {
            if (auto *dialog = qobject_cast<QFileDialog *>(QApplication::activeModalWidget())) {
                dialog->setOption(QFileDialog::DontConfirmOverwrite);
                dialog->selectFile(path);
                chosePath = true;
                QMetaObject::invokeMethod(dialog, "accept", Qt::DirectConnection);
                return;
            }
            if (auto *message = qobject_cast<QMessageBox *>(QApplication::activeModalWidget())) {
                sawError = true;
                errorText = message->text();
                message->accept();
            }
        });
        QTimer watchdog;
        watchdog.setSingleShot(true);
        connect(&watchdog, &QTimer::timeout, &window, [&] {
            dialogs.stop();
            if (auto *dialog = qobject_cast<QDialog *>(QApplication::activeModalWidget()))
                dialog->reject();
        });
        watchdog.start(10000);
        dialogs.start(20);
        exportAction->trigger();
        dialogs.stop();
        watchdog.stop();

        QVERIFY(chosePath);
        QVERIFY(file.open(QIODevice::ReadOnly));
        QCOMPARE(file.readAll(), original);
        QVERIFY(sawError);
        QVERIFY2(errorText.contains(path), qPrintable(errorText));
        QVERIFY2(!window.statusBar()->currentMessage()
                     .startsWith(QStringLiteral("Exported ")),
                 "A failed export must not be reported as exported.");
    }
};

QTEST_MAIN(tst_pdf)
#include "tst_pdf.moc"
