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
        LuceArchive::Contents contents;
        try {
            contents = LuceArchive::read(file.readAll());
        } catch (const std::exception &error) {
            // A named failure, not an uncaught exception that aborts the binary.
            QFAIL(qPrintable(QStringLiteral("saved letter rejected: %1")
                                 .arg(QString::fromUtf8(error.what()))));
        }
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
        // Actually run the save path (the test's name is a promise): typing
        // must survive encode → archive → disk, not just the model snapshot.
        QString error;
        QVERIFY2(editor.saveFile(dir.filePath(QStringLiteral("typed.luce")), &error),
                 qPrintable(error));
        // …and assert on what a fresh Editor READS BACK from that file — the
        // in-memory snapshot alone can't show a stale-serialization bug.
        Editor reader;
        QVERIFY2(reader.loadFile(dir.filePath(QStringLiteral("typed.luce")), &error),
                 qPrintable(error));
        const DocumentModel model = reader.model();
        QCOMPARE(model.body.size(), 1);
        QCOMPARE(model.body.first().plainText(), QStringLiteral("Hello from Ubuntu."));
        QCOMPARE(model.body.first().style, QStringLiteral("body"));
        // No spurious run-level overrides from just typing in the base style.
        QCOMPARE(model.body.first().runs.size(), 1);
        QCOMPARE(model.body.first().runs.first().bold, std::optional<bool>());
        QCOMPARE(model.body.first().runs.first().font, std::optional<QString>());
    }

    void bridgeRoundTripsTheKitchenSinkFixture() {
        // Every save runs the model through DocumentBridge::build() into a
        // QTextDocument and back out via readBody(); nothing tested that pair
        // against a document carrying the full attribute set, so a dropped
        // setProperty would erase tab stops, indents or alignment from every
        // file a user saved — with ctest still green. The corpus fixture is
        // the widest model available, so drive THAT through the bridge.
        QFile file(QStringLiteral(LUCERNE_FIXTURES_DIR "/kitchen-sink.luce"));
        QVERIFY2(file.open(QIODevice::ReadOnly), "kitchen-sink.luce missing");
        DocumentModel before;
        try {
            before = LuceArchive::read(file.readAll()).model;
        } catch (const std::exception &error) {
            QFAIL(qPrintable(QStringLiteral("kitchen-sink.luce rejected: %1")
                                 .arg(QString::fromUtf8(error.what()))));
        }

        Editor editor;
        editor.loadModel(before, {});
        const DocumentModel after = editor.snapshotModel();

        auto find = [](const DocumentModel &m, const QString &id) -> const Paragraph * {
            for (const Paragraph &p : m.body)
                if (p.id == id) return &p;
            return nullptr;
        };

        // Paragraph-level attributes that the bridge must carry both ways.
        const Paragraph *a = find(after, QStringLiteral("p2"));
        QVERIFY2(a, "p2 did not survive the bridge round-trip");
        QCOMPARE(a->style, QStringLiteral("body"));
        QCOMPARE(a->align, std::optional<QString>(QStringLiteral("right")));
        QVERIFY2(a->indent && a->indent->firstLine == std::optional<double>(18),
                 "first-line indent lost in the bridge");
        QCOMPARE(a->lineSpacing, std::optional<double>(1.5));
        QVERIFY2(a->tabStops && a->tabStops->size() == 4, "tab stops lost in the bridge");
        QCOMPARE(a->tabStops->at(1).type, QStringLiteral("center"));
        QCOMPARE(a->tabStops->at(3).type, QStringLiteral("decimal"));

        // Run-level deltas.
        QVERIFY(a->runs.size() >= 4);
        QCOMPARE(a->runs[1].italic, std::optional<bool>(true));
        QCOMPARE(a->runs[2].bold, std::optional<bool>(true));
        QCOMPARE(a->runs[3].font, std::optional<QString>(QStringLiteral("Courier")));
        QCOMPARE(a->runs[3].color, std::optional<QString>(QStringLiteral("#123456")));

        // Custom and unknown style roles keep their names (an unknown role
        // falls back for RENDERING, but must not be rewritten in the model).
        const Paragraph *p6 = find(after, QStringLiteral("p6"));
        QVERIFY2(p6 && p6->style == QLatin1String("fancy"),
                 "a custom style role was rewritten by the bridge");
        const Paragraph *p3 = find(after, QStringLiteral("p3"));
        QVERIFY2(p3 && p3->style == QLatin1String("unknownRole"),
                 "an unknown style role was rewritten by the bridge");

        // Explicit page break, and the page setup itself.
        const Paragraph *p5 = find(after, QStringLiteral("p5"));
        QVERIFY2(p5 && p5->pageBreakBefore == std::optional<bool>(true),
                 "explicit page break lost in the bridge");
        QCOMPARE(after.page.width, before.page.width);
        QCOMPARE(after.page.height, before.page.height);
        QCOMPARE(after.page.margins.right, before.page.margins.right);

        // Placed objects and furniture ride alongside the document, untouched.
        QCOMPARE(after.objects.size(), before.objects.size());
        QVERIFY(after.header && after.header->left == QLatin1String("{title}"));
        QCOMPARE(after.pageNumberStart, before.pageNumberStart);
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

    void coalescedRulerDragIsOneUndoStep() {
        // Regression: a ruler drag applies one block-format edit per mouse-move
        // and joins them so the DOCUMENT gains a single undo step — but
        // joinPreviousEditBlock still makes Qt emit undoCommandAdded, so the
        // unified stack used to grow by one command per move. The two
        // histories then drifted: undo presses were swallowed and interleaved
        // object commands replayed out of order (an inserted image could be
        // stranded out of the document and lost on the next edit).
        // This mirrors Ruler::beginCoalescedEdit's exact sequence.
        Editor editor;
        editor.loadModel(DefaultDocuments::empty(), {});
        QTextCursor typing(editor.document());
        typing.insertText(QStringLiteral("Dear Sir"));
        const int afterTyping = editor.undoStack()->count();

        for (int move = 0; move < 8; ++move) {
            QTextCursor cursor(editor.document());
            if (move > 0) {
                editor.suppressNextTextCommand();
                cursor.joinPreviousEditBlock();
            } else {
                cursor.beginEditBlock();
            }
            QTextBlockFormat format;
            format.setLeftMargin(4.0 * (move + 1));
            cursor.mergeBlockFormat(format);
            cursor.endEditBlock();
        }

        // Eight moves, ONE undo step — matching what the document itself holds.
        QCOMPARE(editor.undoStack()->count(), afterTyping + 1);
        editor.undoStack()->undo();          // the whole drag
        QCOMPARE(editor.document()->firstBlock().blockFormat().leftMargin(), 0.0);
        QCOMPARE(editor.document()->toPlainText(), QStringLiteral("Dear Sir"));
        editor.undoStack()->undo();          // the typing
        QCOMPARE(editor.document()->toPlainText(), QString());
        QVERIFY(!editor.undoStack()->canUndo());
    }

    void objectSurvivesUndoRedoAcrossACoalescedDrag() {
        // The consequence the desync actually caused: with the stack longer
        // than the document's history, redo replayed out of order and an
        // image could sit in a command the document never got back.
        Editor editor;
        editor.loadModel(DefaultDocuments::empty(), {});
        QTextCursor typing(editor.document());
        typing.insertText(QStringLiteral("abc"));
        for (int move = 0; move < 5; ++move) {
            QTextCursor cursor(editor.document());
            if (move > 0) {
                editor.suppressNextTextCommand();
                cursor.joinPreviousEditBlock();
            } else {
                cursor.beginEditBlock();
            }
            QTextBlockFormat format;
            format.setLeftMargin(4.0 * (move + 1));
            cursor.mergeBlockFormat(format);
            cursor.endEditBlock();
        }
        const QByteArray pixel = DefaultDocuments::sampleLetterImages().first();
        editor.insertImage(pixel, QStringLiteral("lake.png"), 0, QPointF(300, 300));
        QCOMPARE(editor.objects().size(), 1);

        // Unwind everything, then replay: the image must come back exactly once
        // and the text must be intact at every step.
        while (editor.undoStack()->canUndo()) editor.undoStack()->undo();
        QCOMPARE(editor.objects().size(), 0);
        QCOMPARE(editor.document()->toPlainText(), QString());
        while (editor.undoStack()->canRedo()) editor.undoStack()->redo();
        QCOMPARE(editor.document()->toPlainText(), QStringLiteral("abc"));
        QCOMPARE(editor.objects().size(), 1);
        QCOMPARE(editor.document()->firstBlock().blockFormat().leftMargin(), 20.0);
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
