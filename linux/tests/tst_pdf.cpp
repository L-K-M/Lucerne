#include "app/MainWindow.h"
#include "app/PdfExport.h"
#include "core/DefaultDocuments.h"

#include <QAction>
#include <QApplication>
#include <QFileDialog>
#include <QMessageBox>
#include <QTemporaryDir>
#include <QTimer>
#include <QtTest>

using namespace lucerne;

class tst_pdf : public QObject {
    Q_OBJECT

private slots:
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
        model.body[1].pageBreakBefore = true;
        editor.loadModel(model, DefaultDocuments::sampleLetterImages());
        QCOMPARE(editor.layout()->pageCount(), 2);
        QString error;
        QVERIFY2(PdfExport::write(editor, path, &error), qPrintable(error));
        QVERIFY(file.open(QIODevice::ReadOnly));
        const QByteArray pdf = file.readAll();
        QVERIFY(pdf.startsWith("%PDF-"));
        QVERIFY(pdf.trimmed().endsWith("%%EOF"));
        QCOMPARE(pdf.count("/Type /Page\n"), 2);
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

        QFile probe(directory.filePath(QStringLiteral("probe")));
        if (probe.open(QIODevice::WriteOnly)) {
            probe.close();
            QFile::setPermissions(directory.path(), permissions);
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
        QTimer dialogs;
        connect(&dialogs, &QTimer::timeout, &window, [&] {
            if (auto *dialog = qobject_cast<QFileDialog *>(QApplication::activeModalWidget())) {
                dialog->setOption(QFileDialog::DontConfirmOverwrite);
                dialog->selectFile(path);
                chosePath = true;
                QMetaObject::invokeMethod(dialog, "accept", Qt::DirectConnection);
                return;
            }
            if (auto *error = qobject_cast<QMessageBox *>(QApplication::activeModalWidget())) {
                sawError = true;
                error->accept();
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
        QVERIFY(QFile::setPermissions(directory.path(), permissions));

        QVERIFY(chosePath);
        QVERIFY(file.open(QIODevice::ReadOnly));
        QCOMPARE(file.readAll(), original);
        QVERIFY(sawError);
    }
};

QTEST_MAIN(tst_pdf)
#include "tst_pdf.moc"
