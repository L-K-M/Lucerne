#include "app/MainWindow.h"

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

#include <csignal>
#include <sys/resource.h>

using namespace lucerne;

class tst_window : public QObject {
    Q_OBJECT

private:
    QTemporaryDir m_settings;

    static QAction *pdfAction(MainWindow &window) {
        for (QAction *action : window.findChildren<QAction *>())
            if (action->text() == QStringLiteral("Export as &PDF…")) return action;
        return nullptr;
    }

    static void exportTo(QAction *action, const QString &path) {
        // Drive the real save/error dialogs without a display or human input.
        QTimer dialogs;
        connect(&dialogs, &QTimer::timeout, [&] {
            QWidget *modal = QApplication::activeModalWidget();
            if (auto *picker = qobject_cast<QFileDialog *>(modal)) {
                picker->setOption(QFileDialog::DontConfirmOverwrite);
                picker->selectFile(path);
                QMetaObject::invokeMethod(picker, "accept", Qt::QueuedConnection);
            } else if (auto *message = qobject_cast<QMessageBox *>(modal)) {
                message->accept();
            }
        });
        dialogs.start();
        action->trigger();
    }

private slots:
    void initTestCase() {
        QVERIFY(m_settings.isValid());
        QApplication::setAttribute(Qt::AA_DontUseNativeDialogs);
        QCoreApplication::setOrganizationName(QStringLiteral("LucerneWindowTests"));
        QSettings::setDefaultFormat(QSettings::IniFormat);
        QSettings::setPath(QSettings::IniFormat, QSettings::UserScope, m_settings.path());
    }

    void pdfWriteFailurePreservesExistingFile() {
        QTemporaryDir dir;
        const QString path = dir.filePath(QStringLiteral("letter.pdf"));
        const QByteArray previous = "previous complete PDF export";
        QFile file(path);
        QVERIFY(file.open(QIODevice::WriteOnly));
        QCOMPARE(file.write(previous), previous.size());
        file.close();

        MainWindow window;
        QAction *action = pdfAction(window);
        QVERIFY(action);

        // Simulate storage exhaustion after PDF output has already begun.
        {
            struct rlimit savedLimit;
            QVERIFY(getrlimit(RLIMIT_FSIZE, &savedLimit) == 0);
            const auto savedSignal = std::signal(SIGXFSZ, SIG_IGN);
            QVERIFY(savedSignal != SIG_ERR);
            const auto restore = qScopeGuard([&] {
                setrlimit(RLIMIT_FSIZE, &savedLimit);
                std::signal(SIGXFSZ, savedSignal);
            });
            constexpr rlim_t simulatedDiskCapacity = 512;
            struct rlimit limit = savedLimit;
            limit.rlim_cur = simulatedDiskCapacity;
            QVERIFY(setrlimit(RLIMIT_FSIZE, &limit) == 0);

            exportTo(action, path);
        }
        QVERIFY(file.open(QIODevice::ReadOnly));
        const QByteArray actual = file.readAll();
        const bool reportedSuccess = window.statusBar()->currentMessage()
            .startsWith(QStringLiteral("Exported "));
        QVERIFY2(actual == previous && !reportedSuccess,
                 qPrintable(QStringLiteral("original=%1 bytes, result=%2 bytes, success=%3")
                                .arg(previous.size()).arg(actual.size()).arg(reportedSuccess)));
    }

    void pdfExportProducesCompleteOutput() {
        QTemporaryDir dir;
        const QString path = dir.filePath(QStringLiteral("letter.pdf"));
        MainWindow window;
        window.loadSampleLetter();
        const PlacedObject image = window.editor()->objects().first();
        window.editor()->previewObjectFrame(image.id, 1, *image.frame);
        QCOMPARE(window.editor()->layout()->pageCount(), 2);
        QAction *action = pdfAction(window);
        QVERIFY(action);
        exportTo(action, path);

        QFile file(path);
        QVERIFY(file.open(QIODevice::ReadOnly));
        const QByteArray pdf = file.readAll();
        QVERIFY(pdf.startsWith("%PDF-"));
        QVERIFY(pdf.contains("%%EOF"));
        QVERIFY(pdf.contains("/Count 2"));
        QVERIFY(window.statusBar()->currentMessage().startsWith(QStringLiteral("Exported ")));
    }
};

QTEST_MAIN(tst_window)
#include "tst_window.moc"
