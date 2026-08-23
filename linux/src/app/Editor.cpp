#include "app/Editor.h"
#include "app/DocumentBridge.h"
#include "core/DefaultDocuments.h"
#include "core/Furniture.h"
#include "core/Markdown.h"
#include "core/Lists.h"

#include <QDate>
#include <QFile>
#include <QFileInfo>
#include <QLocale>
#include <QPainter>
#include <QSaveFile>
#include <QTextBlock>

namespace lucerne {

namespace {

/// Proxy that folds QTextDocument's built-in undo into the unified stack.
/// The document has already performed the edit when the command is pushed, so
/// the mandatory first redo() is a no-op.
class TextCommand : public QUndoCommand {
public:
    TextCommand(QTextDocument *doc, Editor *editor)
        : QUndoCommand(QObject::tr("Typing")), m_doc(doc), m_editor(editor) {}
    void undo() override { m_doc->undo(); }
    void redo() override {
        if (m_first) {
            m_first = false;
            return;
        }
        m_doc->redo();
    }

private:
    QTextDocument *m_doc;
    Editor *m_editor;
    bool m_first = true;
};

} // namespace

/// Snapshot command for object-array mutations (insert/move/resize/wrap/
/// standoff/delete). Whole-array snapshots keep it simple and correct; the
/// arrays are tiny (a letter has a handful of images).
class ObjectsCommand : public QUndoCommand {
public:
    ObjectsCommand(Editor *editor, const QString &text,
                   const QVector<PlacedObject> &before, const QVector<PlacedObject> &after)
        : QUndoCommand(text), m_editor(editor), m_before(before), m_after(after) {}
    void undo() override { m_editor->applyObjects(m_before); }
    void redo() override {
        if (m_first) {
            m_first = false;
            // The live edit already applied `after` in the preview path; make
            // sure the model really is there (insert/delete apply here).
            m_editor->applyObjects(m_after);
            return;
        }
        m_editor->applyObjects(m_after);
    }

private:
    Editor *m_editor;
    QVector<PlacedObject> m_before;
    QVector<PlacedObject> m_after;
    bool m_first = true;
};

Editor::Editor(QObject *parent) : QObject(parent) {
    m_doc = new QTextDocument(this);
    m_layout = new PageLayout(m_doc);
    m_doc->setDocumentLayout(m_layout);
    m_undo = new QUndoStack(this);

    connect(m_doc, &QTextDocument::undoCommandAdded, this, [this] {
        m_undo->push(new TextCommand(m_doc, this));
    });
    connect(m_undo, &QUndoStack::cleanChanged, this, [this] { emit modifiedChanged(); });
    connect(m_undo, &QUndoStack::indexChanged, this, [this] { emit modifiedChanged(); });

    loadModel(DefaultDocuments::empty(), {});
}

QString Editor::displayName() const {
    if (m_filePath.isEmpty()) return tr("Untitled");
    return QFileInfo(m_filePath).completeBaseName();
}

void Editor::loadModel(const DocumentModel &model, const QMap<QString, QByteArray> &images,
                       const QVector<HistorySnapshot> &history) {
    m_model = model;
    m_images = images;
    m_history = history;
    m_imageCache.clear();
    m_layout->setPage(m_model.page);
    DocumentBridge::build(m_doc, m_model);
    m_layout->setObjects(m_model.objects);
    m_undo->clear();
    emit pageSetupChanged();
    emit objectsChanged();
}

bool Editor::loadFile(const QString &path, QString *error) {
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly)) {
        if (error) *error = file.errorString();
        return false;
    }
    try {
        const LuceArchive::Contents contents = LuceArchive::read(file.readAll());
        loadModel(contents.model, contents.images, contents.history);
        m_filePath = path;
        return true;
    } catch (const std::exception &e) {
        if (error) *error = QString::fromUtf8(e.what());
        return false;
    }
}

DocumentModel Editor::snapshotModel() const {
    DocumentModel model = m_model;
    model.body = DocumentBridge::readBody(m_doc, m_model);
    return model;
}

bool Editor::saveFile(const QString &path, QString *error) {
    try {
        const DocumentModel model = snapshotModel();
        const QString markdown = MarkdownExporter::exportModel(model);
        // Append a dated snapshot (skipping duplicates), thinned with age —
        // commit the trail only after the archive is built (the Mac's
        // HistoryArchiveWriter contract).
        const QVector<HistorySnapshot> updatedHistory =
            HistoryPruner::updated(m_history, markdown, QDateTime::currentDateTimeUtc());
        const QByteArray data = LuceArchive::write(model, m_images, updatedHistory);

        QSaveFile file(path);
        if (!file.open(QIODevice::WriteOnly) || file.write(data) != data.size()
            || !file.commit()) {
            if (error) *error = file.errorString();
            return false;
        }
        m_history = updatedHistory;
        m_model = model;   // body now canonical again
        m_filePath = path;
        m_undo->setClean();
        return true;
    } catch (const std::exception &e) {
        if (error) *error = QString::fromUtf8(e.what());
        return false;
    }
}

// MARK: - Objects

const PlacedObject *Editor::objectById(const QString &id) const {
    for (const PlacedObject &object : m_model.objects)
        if (object.id == id) return &object;
    return nullptr;
}

QImage Editor::imageForObject(const PlacedObject &object) const {
    if (!object.src) return {};
    const auto cached = m_imageCache.constFind(*object.src);
    if (cached != m_imageCache.constEnd()) return *cached;
    QImage image;
    const auto payload = m_images.constFind(*object.src);
    if (payload != m_images.constEnd()) image = QImage::fromData(*payload);
    m_imageCache.insert(*object.src, image);
    return image;
}

void Editor::applyObjects(const QVector<PlacedObject> &objects) {
    m_model.objects = objects;
    m_layout->setObjects(objects);
    emit objectsChanged();
}

void Editor::pushObjectsCommand(const QString &text, const QVector<PlacedObject> &before,
                                const QVector<PlacedObject> &after,
                                const QMap<QString, QByteArray> &addedImages) {
    for (auto it = addedImages.constBegin(); it != addedImages.constEnd(); ++it)
        m_images.insert(it.key(), it.value());
    m_undo->push(new ObjectsCommand(this, text, before, after));
    emit undoCoalescingBreak();
}

QString Editor::insertImage(const QByteArray &payload, const QString &suggestedName,
                            int page, const QPointF &pagePoint) {
    const QImage decoded = QImage::fromData(payload);
    if (decoded.isNull()) return {};

    // Unique archive path under images/ from the suggested filename.
    QString stem = QFileInfo(suggestedName).completeBaseName();
    QString extension = QFileInfo(suggestedName).suffix().toLower();
    if (stem.isEmpty()) stem = QStringLiteral("image");
    if (extension.isEmpty()) extension = QStringLiteral("png");
    stem.replace(QLatin1Char('/'), QLatin1Char('-'));
    QString src = LuceArchive::imagesPrefix() + stem + QLatin1Char('.') + extension;
    for (int n = 2; m_images.contains(src); ++n)
        src = LuceArchive::imagesPrefix() + stem + QStringLiteral("-%1.").arg(n) + extension;

    // Mac defaults: aspect-fit into half the text column, wrap on, standoff 12.
    const PageMetrics metrics = m_layout->metrics();
    const SizeModel maximum{metrics.contentSize().width * 0.5, metrics.pageSize.height};
    SizeModel size = aspectFitSize({double(decoded.width()), double(decoded.height())},
                                   maximum);
    if (size.width <= 0)
        size = {maximum.width, maximum.width * 0.75};

    RectModel frame{pagePoint.x() - size.width / 2, pagePoint.y() - size.height / 2,
                    size.width, size.height};
    frame = metrics.clampObjectFrame(frame);

    int maxZ = 0;
    for (const PlacedObject &object : m_model.objects) maxZ = std::max(maxZ, object.z);

    PlacedObject object;
    object.id = IDGenerator::next(QStringLiteral("img"));
    object.src = src;
    object.page = std::clamp(page, 0, DocumentModel::maximumPageCount() - 1);
    object.frame = frame;
    object.z = maxZ + 1;

    const QVector<PlacedObject> before = m_model.objects;
    QVector<PlacedObject> after = before;
    after.append(object);
    pushObjectsCommand(tr("Insert Image"), before, after, {{src, payload}});
    return object.id;
}

void Editor::previewObjectFrame(const QString &id, int page, const RectModel &frame) {
    QVector<PlacedObject> objects = m_model.objects;
    for (PlacedObject &object : objects) {
        if (object.id != id) continue;
        object.page = page;
        object.frame = m_layout->metrics().clampObjectFrame(frame);
    }
    applyObjects(objects);
}

void Editor::commitObjectFrame(const QString &id, int beforePage, const RectModel &beforeFrame,
                               const QString &undoText) {
    QVector<PlacedObject> before = m_model.objects;
    for (PlacedObject &object : before) {
        if (object.id != id) continue;
        object.page = beforePage;
        object.frame = beforeFrame;
    }
    if (before == m_model.objects) return;   // nothing actually moved
    m_undo->push(new ObjectsCommand(this, undoText, before, m_model.objects));
    emit undoCoalescingBreak();
}

void Editor::setObjectWrap(const QString &id, const QString &wrap) {
    const QVector<PlacedObject> before = m_model.objects;
    QVector<PlacedObject> after = before;
    for (PlacedObject &object : after)
        if (object.id == id) object.wrap = wrap;
    if (after == before) return;
    pushObjectsCommand(tr("Change Text Wrap"), before, after);
}

void Editor::adjustObjectStandoff(const QString &id, double delta) {
    const QVector<PlacedObject> before = m_model.objects;
    QVector<PlacedObject> after = before;
    for (PlacedObject &object : after)
        if (object.id == id) object.standoff = std::max(0.0, object.standoff + delta);
    if (after == before) return;
    pushObjectsCommand(tr("Change Standoff"), before, after);
}

void Editor::deleteObject(const QString &id) {
    const QVector<PlacedObject> before = m_model.objects;
    QVector<PlacedObject> after;
    for (const PlacedObject &object : before)
        if (object.id != id) after.append(object);
    if (after.size() == before.size()) return;
    pushObjectsCommand(tr("Delete Image"), before, after);
}

// MARK: - Styles

QString Editor::styleRoleAt(const QTextCursor &cursor) const {
    const QString role = cursor.block().charFormat().stringProperty(Props::StyleRole);
    return role.isEmpty() ? DocumentModel::defaultStyleRole() : role;
}

void Editor::applyParagraphStyleFormats(QTextCursor &cursor, const QString &role) {
    // Rebuild the block's formats from the style while preserving run-level
    // deltas captured against the OLD style (inline bold on a word survives a
    // style change, like the Mac).
    QTextBlock block = cursor.block();
    const QString oldRole = styleRoleAt(cursor);
    const ParagraphStyle oldStyle = m_model.resolvedStyle(oldRole);
    const ParagraphStyle newStyle = m_model.resolvedStyle(role);

    Paragraph probe;
    probe.style = role;
    probe.id = block.charFormat().stringProperty(Props::ParagraphId);
    QTextBlockFormat bf = DocumentBridge::blockFormat(m_model, probe);

    QTextCharFormat bcf = DocumentBridge::blockCharFormat(m_model, probe);
    // Keep identity/descriptor properties the block already carries.
    const QTextCharFormat old = block.charFormat();
    if (old.hasProperty(Props::PageBreakBefore))
        bcf.setProperty(Props::PageBreakBefore, old.boolProperty(Props::PageBreakBefore));
    if (old.hasProperty(Props::ListItem))
        bcf.setProperty(Props::ListItem, old.stringProperty(Props::ListItem));
    if (old.hasProperty(Props::TableCell))
        bcf.setProperty(Props::TableCell, old.stringProperty(Props::TableCell));

    // Capture every fragment's span and its delta against the OLD style FIRST —
    // applying formats splits/merges fragments and would invalidate the
    // iteration mid-walk.
    struct Span {
        int position;
        int length;
        QTextCharFormat format;
    };
    QVector<Span> spans;
    for (auto it = block.begin(); !it.atEnd(); ++it) {
        const QTextFragment fragment = it.fragment();
        if (!fragment.isValid() || fragment.length() == 0) continue;
        const QTextCharFormat cf = fragment.charFormat();
        Run run;   // capture the deltas exactly as readBody() would
        const QString fontName = cf.hasProperty(Props::ModelFont)
            ? cf.stringProperty(Props::ModelFont) : cf.font().family();
        if (fontName != oldStyle.font.value_or(QStringLiteral("Helvetica"))) run.font = fontName;
        if (std::abs(cf.font().pointSizeF() - oldStyle.size.value_or(12.0)) > 1e-9)
            run.size = cf.font().pointSizeF();
        if (cf.font().bold() != oldStyle.bold.value_or(false)) run.bold = cf.font().bold();
        if (cf.font().italic() != oldStyle.italic.value_or(false))
            run.italic = cf.font().italic();
        if (cf.fontUnderline() != oldStyle.underline.value_or(false))
            run.underline = cf.fontUnderline();
        const QString color = cf.hasProperty(Props::ModelColor)
            ? cf.stringProperty(Props::ModelColor)
            : DocumentBridge::colorToHex(cf.foreground().color());
        if (color != oldStyle.color.value_or(QStringLiteral("#000000"))) run.color = color;
        spans.append({fragment.position(), fragment.length(),
                      DocumentBridge::charFormat(newStyle, run)});
    }

    QTextCursor blockCursor(block);
    blockCursor.setBlockFormat(bf);
    blockCursor.setBlockCharFormat(bcf);

    for (const Span &span : spans) {
        QTextCursor spanCursor(m_doc);
        spanCursor.setPosition(span.position);
        spanCursor.setPosition(span.position + span.length, QTextCursor::KeepAnchor);
        spanCursor.setCharFormat(span.format);
    }
}

void Editor::applyStyle(QTextCursor cursor, const QString &role) {
    if (!m_model.styles.contains(role)) return;
    cursor.beginEditBlock();
    const int start = cursor.selectionStart();
    const int end = cursor.selectionEnd();
    QTextBlock block = m_doc->findBlock(start);
    while (block.isValid() && block.position() <= end) {
        QTextCursor blockCursor(block);
        applyParagraphStyleFormats(blockCursor, role);
        block = block.next();
    }
    cursor.endEditBlock();
}

void Editor::redefineStyle(const QString &role, const ParagraphStyle &def) {
    QTextCursor cursor(m_doc);
    cursor.beginEditBlock();
    m_model.styles.insert(role, def);
    for (QTextBlock block = m_doc->begin(); block.isValid(); block = block.next()) {
        if (block.charFormat().stringProperty(Props::StyleRole) != role) continue;
        QTextCursor blockCursor(block);
        applyParagraphStyleFormats(blockCursor, role);
    }
    cursor.endEditBlock();
}

// MARK: - Lists

void Editor::toggleList(QTextCursor cursor, bool ordered, const QString &marker) {
    cursor.beginEditBlock();
    const int start = cursor.selectionStart();
    const int end = cursor.selectionEnd();

    // If the caret paragraph already carries this exact kind, the command
    // removes the list (the Mac toggle); otherwise it applies it, joining the
    // neighbouring run's id when the item above is compatible.
    QTextBlock first = m_doc->findBlock(start);
    const auto current = DocumentBridge::decodeListItem(
        first.charFormat().stringProperty(Props::ListItem));
    const bool removing = current && current->ordered == ordered
        && (current->marker == marker || marker.isEmpty());

    QString listId;
    if (!removing) {
        const QTextBlock previous = first.previous();
        if (previous.isValid()) {
            if (const auto above = DocumentBridge::decodeListItem(
                    previous.charFormat().stringProperty(Props::ListItem)))
                listId = above->list;
        }
        if (listId.isEmpty()) listId = IDGenerator::next(QStringLiteral("list"));
    }

    for (QTextBlock block = first; block.isValid() && block.position() <= end;
         block = block.next()) {
        QTextCharFormat bcf = block.charFormat();
        if (removing) {
            bcf.clearProperty(Props::ListItem);
        } else {
            ListItemModel item;
            const auto existing =
                DocumentBridge::decodeListItem(bcf.stringProperty(Props::ListItem));
            item.list = listId;
            item.ordered = ordered;
            item.marker = marker.isEmpty()
                ? (ordered ? ListMarkers::defaultOrderedMarker()
                           : ListMarkers::defaultUnorderedMarker())
                : marker;
            item.level = existing ? existing->level : 0;
            bcf.setProperty(Props::ListItem, DocumentBridge::encodeListItem(item));
        }
        QTextCursor blockCursor(block);
        blockCursor.setBlockCharFormat(bcf);
    }
    cursor.endEditBlock();
}

void Editor::changeListLevel(QTextCursor cursor, int delta) {
    cursor.beginEditBlock();
    const int start = cursor.selectionStart();
    const int end = cursor.selectionEnd();
    for (QTextBlock block = m_doc->findBlock(start);
         block.isValid() && block.position() <= end; block = block.next()) {
        QTextCharFormat bcf = block.charFormat();
        const auto item = DocumentBridge::decodeListItem(bcf.stringProperty(Props::ListItem));
        if (!item) continue;
        ListItemModel updated = *item;
        updated.level = ListGeometry::clampedLevel(item->level + delta);
        bcf.setProperty(Props::ListItem, DocumentBridge::encodeListItem(updated));
        QTextCursor blockCursor(block);
        blockCursor.setBlockCharFormat(bcf);
    }
    cursor.endEditBlock();
}

void Editor::insertPageBreak(QTextCursor cursor) {
    cursor.beginEditBlock();
    // A paragraph break first when not at a paragraph start, then flag the
    // (new) paragraph — matching the Mac's semantics.
    if (cursor.positionInBlock() != 0) {
        const QTextCharFormat bcf = cursor.block().charFormat();
        cursor.insertBlock(cursor.blockFormat(), bcf);
        // The freshly minted paragraph needs its own identity.
        QTextCharFormat updated = cursor.block().charFormat();
        updated.setProperty(Props::ParagraphId, IDGenerator::next(QStringLiteral("p")));
        QTextCursor blockCursor(cursor.block());
        blockCursor.setBlockCharFormat(updated);
    }
    QTextCharFormat bcf = cursor.block().charFormat();
    bcf.setProperty(Props::PageBreakBefore, true);
    QTextCursor blockCursor(cursor.block());
    blockCursor.setBlockCharFormat(bcf);
    cursor.endEditBlock();
}

// MARK: - Model-level settings

namespace {

/// Snapshot command over the non-body model halves (page config, furniture).
class ModelSettingsCommand : public QUndoCommand {
public:
    ModelSettingsCommand(Editor *editor, const QString &text,
                         std::function<void()> apply, std::function<void()> revert)
        : QUndoCommand(text), m_apply(std::move(apply)), m_revert(std::move(revert)) {
        Q_UNUSED(editor);
    }
    void undo() override { m_revert(); }
    void redo() override { m_apply(); }

private:
    std::function<void()> m_apply;
    std::function<void()> m_revert;
};

} // namespace

void Editor::setPageConfig(const PageConfig &page) {
    const PageConfig before = m_model.page;
    if (before == page) return;
    m_undo->push(new ModelSettingsCommand(this, tr("Document Setup"),
        [this, page] {
            m_model.page = page;
            m_layout->setPage(page);
            emit pageSetupChanged();
        },
        [this, before] {
            m_model.page = before;
            m_layout->setPage(before);
            emit pageSetupChanged();
        }));
    emit undoCoalescingBreak();
}

void Editor::setFurniture(const std::optional<PageFurniture> &header,
                          const std::optional<PageFurniture> &footer,
                          std::optional<int> pageNumberStart) {
    const auto beforeHeader = m_model.header;
    const auto beforeFooter = m_model.footer;
    const auto beforeStart = m_model.pageNumberStart;
    if (beforeHeader == header && beforeFooter == footer && beforeStart == pageNumberStart)
        return;
    m_undo->push(new ModelSettingsCommand(this, tr("Change Header & Footer"),
        [this, header, footer, pageNumberStart] {
            m_model.header = header;
            m_model.footer = footer;
            m_model.pageNumberStart = pageNumberStart;
            emit pageSetupChanged();
        },
        [this, beforeHeader, beforeFooter, beforeStart] {
            m_model.header = beforeHeader;
            m_model.footer = beforeFooter;
            m_model.pageNumberStart = beforeStart;
            emit pageSetupChanged();
        }));
    emit undoCoalescingBreak();
}

void Editor::renderPage(QPainter *painter, int pageIndex) const {
    const QRectF sheet = m_layout->pageRect(pageIndex);
    const PageMetrics metrics = m_layout->metrics();

    painter->save();
    painter->translate(-sheet.topLeft());
    painter->setClipRect(sheet);

    if (m_model.page.foldMarks.value_or(false)) {
        painter->setPen(QPen(QColor(0, 0, 0, 64), 0.5));
        for (const double offset : PageMetrics::din5008FoldMarkOffsetsFromTop())
            if (offset < m_model.page.height)
                painter->drawLine(QPointF(sheet.left() + 6, sheet.top() + offset),
                                  QPointF(sheet.left() + 18, sheet.top() + offset));
    }

    const bool hasHeader = m_model.header && !m_model.header->isEmpty();
    const bool hasFooter = m_model.footer && !m_model.footer->isEmpty();
    if (hasHeader || hasFooter) {
        const ParagraphStyle body = m_model.resolvedStyle(DocumentModel::defaultStyleRole());
        const double size = std::max(8.0, body.size.value_or(12.0) * 0.8);
        painter->setFont(DocumentBridge::displayFont(
            body.font.value_or(QStringLiteral("Helvetica")), size, false, false));
        painter->setPen(QColor(0, 0, 0, 150));
        const QRectF textArea = m_layout->textAreaRect(pageIndex);
        auto drawBand = [&](const PageFurniture &furniture, const QRectF &band) {
            const QString left = furnitureZoneText(furniture.left, pageIndex);
            const QString center = furnitureZoneText(furniture.center, pageIndex);
            const QString right = furnitureZoneText(furniture.right, pageIndex);
            if (!left.isEmpty()) painter->drawText(band, Qt::AlignLeft | Qt::AlignVCenter, left);
            if (!center.isEmpty())
                painter->drawText(band, Qt::AlignHCenter | Qt::AlignVCenter, center);
            if (!right.isEmpty())
                painter->drawText(band, Qt::AlignRight | Qt::AlignVCenter, right);
        };
        if (hasHeader)
            drawBand(*m_model.header, QRectF(textArea.left(), sheet.top(),
                                             textArea.width(), metrics.marginTop));
        if (hasFooter)
            drawBand(*m_model.footer,
                     QRectF(textArea.left(), sheet.bottom() - metrics.marginBottom,
                            textArea.width(), metrics.marginBottom));
    }

    QAbstractTextDocumentLayout::PaintContext context;
    context.clip = sheet;
    context.cursorPosition = -1;
    m_layout->draw(painter, context);

    QVector<const PlacedObject *> sorted;
    for (const PlacedObject &object : m_model.objects)
        if (object.anchorMode() == PlacedObject::Anchor::Page
            && object.page == std::optional<int>(pageIndex) && object.frame)
            sorted.append(&object);
    std::stable_sort(sorted.begin(), sorted.end(),
                     [](const PlacedObject *a, const PlacedObject *b) { return a->z < b->z; });
    for (const PlacedObject *object : sorted) {
        const RectModel frame = *object->frame;
        const QRectF rect(sheet.left() + frame.x, sheet.top() + frame.y,
                          frame.width, frame.height);
        const QImage image = imageForObject(*object);
        if (image.isNull()) {
            painter->fillRect(rect, QColor(237, 237, 237));
            painter->setPen(QColor(0, 0, 0, 110));
            painter->drawText(rect, Qt::AlignCenter, tr("Image"));
        } else {
            painter->drawImage(rect, image);
        }
    }
    painter->restore();
}

QString Editor::furnitureZoneText(const QString &zoneTemplate, int physicalPage) const {
    const int pageCount = m_layout->pageCount();
    const auto number =
        Furniture::displayedPageNumber(physicalPage, pageCount, m_model.pageNumberStart);
    const int numbered = Furniture::numberedPageCount(pageCount, m_model.pageNumberStart);
    const QString date = QLocale().toString(QDate::currentDate(), QLocale::LongFormat);
    return Furniture::resolveTemplate(zoneTemplate, number, numbered, date, displayName());
}

} // namespace lucerne
