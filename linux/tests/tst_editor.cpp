// Editor-level behavior: file round-trips through the real save path (history
// trail included), delta capture on read-back, style application preserving
// inline formatting, unified undo across text and object mutations.

#include "app/Editor.h"
#include "app/PageCanvas.h"
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
        DocumentModel after = editor.snapshotModel();
        QCOMPARE(after.body.first().style, QStringLiteral("heading1"));
        // The Mac semantics re-derive deltas against the OLD style: "plain"
        // (no delta) adopts heading1's bold, and "bold" (delta bold=true vs
        // body) stays explicitly bold. heading1 IS bold, so on read-back both
        // runs match the new style — no overrides, and they merge into one.
        QCOMPARE(after.body.first().plainText(), QStringLiteral("plain bold"));
        QCOMPARE(after.body.first().runs.size(), 1);
        QCOMPARE(after.body.first().runs.first().bold, std::optional<bool>());

        // Applying a NOT-bold style to the original paragraph is the real
        // preservation check: the explicit bold survives as a run-level delta.
        // (Going through a bold intermediate style absorbs the distinction —
        // attributes are baked, exactly as on the Mac, where a bold word
        // inside a bold heading is indistinguishable from the style's bold.)
        Editor second;
        second.loadModel(model, {});
        QTextCursor quoteCursor(second.document());
        second.applyStyle(quoteCursor, QStringLiteral("quote"));
        after = second.snapshotModel();
        QCOMPARE(after.body.first().style, QStringLiteral("quote"));
        QCOMPARE(after.body.first().runs.size(), 2);
        QCOMPARE(after.body.first().runs.first().text, QStringLiteral("plain "));
        QCOMPARE(after.body.first().runs.first().bold, std::optional<bool>());
        QCOMPARE(after.body.first().runs[1].text, QStringLiteral("bold"));
        QCOMPARE(after.body.first().runs[1].bold, std::optional<bool>(true));
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

        QCOMPARE(editor.objects().size(), 0);
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

    void styleAndListEditsDoNotTouchNeighbors() {
        // Regression: block-format writes must reach EXACTLY one paragraph.
        // (select(BlockUnderCursor) reaches into the previous block's
        // separator and used to corrupt its role/id/list properties.)
        Editor editor;
        DocumentModel model = DefaultDocuments::empty();
        model.body.clear();
        for (int i = 0; i < 3; ++i) {
            Paragraph p;
            p.id = QStringLiteral("p%1").arg(i);
            p.style = QStringLiteral("body");
            p.runs.append(Run{QStringLiteral("Paragraph %1").arg(i)});
            model.body.append(p);
        }
        editor.loadModel(model, {});

        // Style the MIDDLE paragraph as heading1; toggle a list on it too.
        QTextCursor cursor(editor.document());
        cursor.setPosition(editor.document()->findBlockByNumber(1).position() + 2);
        editor.applyStyle(cursor, QStringLiteral("heading1"));
        editor.toggleList(cursor, true, QStringLiteral("decimal"));

        const DocumentModel after = editor.snapshotModel();
        QCOMPARE(after.body.size(), 3);
        QCOMPARE(after.body[0].style, QStringLiteral("body"));
        QCOMPARE(after.body[0].id, QStringLiteral("p0"));
        QVERIFY(!after.body[0].list);
        QCOMPARE(after.body[1].style, QStringLiteral("heading1"));
        QVERIFY(after.body[1].list && after.body[1].list->ordered);
        QCOMPARE(after.body[2].style, QStringLiteral("body"));
        QVERIFY(!after.body[2].list);
    }

    void pageBreakDoesNotTouchThePreviousParagraph() {
        Editor editor;
        DocumentModel model = DefaultDocuments::empty();
        model.body.clear();
        for (int i = 0; i < 2; ++i) {
            Paragraph p;
            p.id = QStringLiteral("p%1").arg(i);
            p.style = QStringLiteral("body");
            p.runs.append(Run{QStringLiteral("Paragraph %1").arg(i)});
            model.body.append(p);
        }
        editor.loadModel(model, {});
        QTextCursor cursor(editor.document());
        cursor.setPosition(editor.document()->findBlockByNumber(1).position());
        editor.insertPageBreak(cursor);
        const DocumentModel after = editor.snapshotModel();
        QCOMPARE(after.body[0].pageBreakBefore, std::optional<bool>());
        QCOMPARE(after.body[1].pageBreakBefore, std::optional<bool>(true));
    }

    void returnOnTrailingEmptyListItemKeepsPreviousBullet() {
        // Regression: leaving a list via Return on its empty last item must
        // not strip the previous item's membership.
        Editor editor;
        DocumentModel model = DefaultDocuments::empty();
        model.body.clear();
        Paragraph first;
        first.id = QStringLiteral("l1");
        first.style = QStringLiteral("body");
        first.runs.append(Run{QStringLiteral("First bullet")});
        ListItemModel item;
        item.list = QStringLiteral("L");
        item.ordered = false;
        item.marker = QStringLiteral("disc");
        first.list = item;
        Paragraph second = first;
        second.id = QStringLiteral("l2");
        second.runs = {Run{QString()}};
        model.body = {first, second};
        editor.loadModel(model, {});

        PageCanvas canvas(&editor);
        canvas.resize(700, 500);
        canvas.show();
        QTextCursor cursor(editor.document());
        cursor.movePosition(QTextCursor::End);
        canvas.setTextCursor(cursor);
        QTest::keyClick(&canvas, Qt::Key_Return);

        const DocumentModel after = editor.snapshotModel();
        QCOMPARE(after.body.size(), 2);
        QVERIFY2(after.body[0].list.has_value(), "previous bullet lost its list");
        QVERIFY(!after.body[1].list.has_value());
    }

    void typingAfterAnObjectCommandUndoesInOrder() {
        // Regression: QTextDocument merges adjacent insertions; without the
        // coalescing break, "def" merges into the pre-move "abc" command and
        // undo order inverts.
        Editor editor;
        editor.loadModel(DefaultDocuments::empty(), {});
        PageCanvas canvas(&editor);
        canvas.resize(700, 500);
        canvas.show();
        QTextCursor cursor(editor.document());
        cursor.movePosition(QTextCursor::End);
        canvas.setTextCursor(cursor);

        QTest::keyClicks(canvas.viewport(), QStringLiteral("abc"));
        const QByteArray pixel = DefaultDocuments::sampleLetterImages().first();
        editor.insertImage(pixel, QStringLiteral("lake.png"), 0, QPointF(300, 300));
        QTest::keyClicks(canvas.viewport(), QStringLiteral("def"));
        QCOMPARE(editor.document()->toPlainText(), QStringLiteral("abcdef"));

        editor.undoStack()->undo();   // removes "def" only
        QCOMPARE(editor.document()->toPlainText(), QStringLiteral("abc"));
        QCOMPARE(editor.objects().size(), 1);
        editor.undoStack()->undo();   // removes the image
        QCOMPARE(editor.objects().size(), 0);
        editor.undoStack()->undo();   // removes "abc"
        QCOMPARE(editor.document()->toPlainText(), QString());
    }
};

QTEST_MAIN(tst_editor)
#include "tst_editor.moc"
