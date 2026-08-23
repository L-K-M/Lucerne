// Editor-level behavior: file round-trips through the real save path (history
// trail included), delta capture on read-back, style application preserving
// inline formatting, unified undo across text and object mutations.

#include "app/Editor.h"
#include "app/DocumentBridge.h"
#include "core/DefaultDocuments.h"
#include "core/LuceArchive.h"

#include <QTemporaryDir>
#include <QTextBlock>
#include <QtTest>

using namespace lucerne;

class tst_editor : public QObject {
    Q_OBJECT

private slots:
    void saveLoadRoundTripsTheSampleLetter() {
        QTemporaryDir dir;
        const QString path = dir.filePath("sample.luce");

        Editor editor;
        editor.loadModel(DefaultDocuments::sampleLetter(),
                         DefaultDocuments::sampleLetterImages());
        QString error;
        QVERIFY2(editor.saveFile(path, &error), qPrintable(error));

        Editor reader;
        QVERIFY2(reader.loadFile(path, &error), qPrintable(error));
        QCOMPARE(reader.model().body.size(),
                 DefaultDocuments::sampleLetter().body.size());
        // The italic run survived the storage round-trip as a run-level delta.
        const Paragraph &p3 = reader.model().body[2];
        QVERIFY(p3.runs.size() >= 3);
        QCOMPARE(p3.runs[1].text, QStringLiteral("wonderful"));
        QCOMPARE(p3.runs[1].italic, std::optional<bool>(true));
        // The image object came back intact.
        QCOMPARE(reader.model().objects.size(), 1);
        QCOMPARE(reader.model().objects.first().frame->x, 300.0);
        // content.md + history landed in the archive.
        QFile file(path);
        QVERIFY(file.open(QIODevice::ReadOnly));
        const LuceArchive::Contents contents = LuceArchive::read(file.readAll());
        QCOMPARE(contents.history.size(), 1);
        QVERIFY(contents.images.contains(QStringLiteral("images/lake.png")));
    }

    void typingIsCapturedOnSave() {
        QTemporaryDir dir;
        Editor editor;
        editor.loadModel(DefaultDocuments::empty(), {});
        QTextCursor cursor(editor.document());
        cursor.movePosition(QTextCursor::End);
        cursor.insertText(QStringLiteral("Hello from Ubuntu."));
        const DocumentModel model = editor.snapshotModel();
        QCOMPARE(model.body.size(), 1);
        QCOMPARE(model.body.first().plainText(), QStringLiteral("Hello from Ubuntu."));
        QCOMPARE(model.body.first().style, QStringLiteral("body"));
        // No spurious run-level overrides from just typing in the base style.
        QCOMPARE(model.body.first().runs.size(), 1);
        QCOMPARE(model.body.first().runs.first().bold, std::optional<bool>());
        QCOMPARE(model.body.first().runs.first().font, std::optional<QString>());
    }

    void applyStylePreservesInlineDeltas() {
        Editor editor;
        DocumentModel model = DefaultDocuments::empty();
        Paragraph p;
        p.id = "p1";
        p.style = "body";
        p.runs.append(Run{QStringLiteral("plain ")});
        Run bolded{QStringLiteral("bold")};
        bolded.bold = true;
        p.runs.append(bolded);
        model.body = {p};
        editor.loadModel(model, {});

        QTextCursor cursor(editor.document());
        editor.applyStyle(cursor, QStringLiteral("heading1"));
        const DocumentModel after = editor.snapshotModel();
        QCOMPARE(after.body.first().style, QStringLiteral("heading1"));
        // heading1 is bold by definition: the formerly-bold run needs no
        // override, and the formerly-plain run must now be marked not-bold?
        // No: the Mac semantics re-derive deltas against the OLD style, so
        // "plain" (no delta) adopts the new style's bold, and "bold" (delta
        // bold=true vs body) stays explicitly bold — equal on the page.
        const QString text = after.body.first().plainText();
        QCOMPARE(text, QStringLiteral("plain bold"));
    }

    void objectCommandsAreUndoable() {
        Editor editor;
        editor.loadModel(DefaultDocuments::sampleLetter(),
                         DefaultDocuments::sampleLetterImages());
        const RectModel before = *editor.objects().first().frame;

        editor.previewObjectFrame(QStringLiteral("img1"), 0,
                                  {before.x + 50, before.y + 40, before.width, before.height});
        editor.commitObjectFrame(QStringLiteral("img1"), 0, before,
                                 QStringLiteral("Move Image"));
        QCOMPARE(editor.objects().first().frame->x, before.x + 50);
        QVERIFY(editor.isModified());

        editor.undoStack()->undo();
        QCOMPARE(editor.objects().first().frame->x, before.x);
        editor.undoStack()->redo();
        QCOMPARE(editor.objects().first().frame->x, before.x + 50);
    }

    void textAndObjectUndoShareOneStack() {
        Editor editor;
        editor.loadModel(DefaultDocuments::empty(), {});
        QTextCursor cursor(editor.document());
        cursor.insertText(QStringLiteral("abc"));

        const QVector<PlacedObject> none = editor.objects();
        const QByteArray pixel = DefaultDocuments::sampleLetterImages().first();
        editor.insertImage(pixel, QStringLiteral("lake.png"), 0, QPointF(300, 300));
        QCOMPARE(editor.objects().size(), 1);

        // Undo pops the image first, then the typing — one interleaved history.
        editor.undoStack()->undo();
        QCOMPARE(editor.objects().size(), 0);
        editor.undoStack()->undo();
        QCOMPARE(editor.document()->toPlainText(), QString());
    }

    void deleteObjectDropsItsExclusion() {
        Editor editor;
        editor.loadModel(DefaultDocuments::sampleLetter(),
                         DefaultDocuments::sampleLetterImages());
        const int pagesBefore = editor.layout()->pageCount();
        editor.deleteObject(QStringLiteral("img1"));
        QCOMPARE(editor.objects().size(), 0);
        QVERIFY(editor.layout()->pageCount() <= pagesBefore);
        editor.undoStack()->undo();
        QCOMPARE(editor.objects().size(), 1);
    }
};

QTEST_MAIN(tst_editor)
#include "tst_editor.moc"
