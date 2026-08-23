#pragma once

// The document controller — the Qt analogue of the Mac's EditorController:
// owns the canonical model halves that live outside the text storage (page
// config, style table, placed objects, furniture, image payloads, history),
// the QTextDocument + PageLayout pair, and one unified QUndoStack through
// which BOTH text edits (proxied from QTextDocument's built-in undo) and
// object/model mutations flow, so Edit ▸ Undo walks one history like the Mac's
// NSUndoManager does.

#include "app/PageLayout.h"
#include "core/LuceArchive.h"
#include "core/Model.h"

#include <QImage>
#include <QObject>
#include <QTextCursor>
#include <QUndoStack>

namespace lucerne {

class Editor : public QObject {
    Q_OBJECT
public:
    explicit Editor(QObject *parent = nullptr);

    QTextDocument *document() const { return m_doc; }
    PageLayout *layout() const { return m_layout; }
    QUndoStack *undoStack() const { return m_undo; }

    const DocumentModel &model() const { return m_model; }
    const QVector<PlacedObject> &objects() const { return m_model.objects; }
    const QMap<QString, ParagraphStyle> &styles() const { return m_model.styles; }

    QString filePath() const { return m_filePath; }
    /// The window/tab title: file stem, or "Untitled".
    QString displayName() const;

    // MARK: - Load / save

    void loadModel(const DocumentModel &model, const QMap<QString, QByteArray> &images,
                   const QVector<HistorySnapshot> &history = {});
    bool loadFile(const QString &path, QString *error);
    bool saveFile(const QString &path, QString *error);
    /// The model with `body` freshly read back from the storage.
    DocumentModel snapshotModel() const;
    bool isModified() const { return !m_undo->isClean(); }

    // MARK: - Objects (all undoable)

    const PlacedObject *objectById(const QString &id) const;
    QImage imageForObject(const PlacedObject &object) const;   // cached decode

    /// Insert an image payload centered on `pagePoint` of `page` (aspect-fit
    /// to half the text column, the Mac default). Returns the new object id.
    QString insertImage(const QByteArray &payload, const QString &suggestedName,
                        int page, const QPointF &pagePoint);
    /// Live drag: apply without undo (mirrors the Mac's live reflow)…
    void previewObjectFrame(const QString &id, int page, const RectModel &frame);
    /// …and commit records one undo step from the pre-drag state.
    void commitObjectFrame(const QString &id, int beforePage, const RectModel &beforeFrame,
                           const QString &undoText);
    void setObjectWrap(const QString &id, const QString &wrap);
    void adjustObjectStandoff(const QString &id, double delta);
    void deleteObject(const QString &id);

    // MARK: - Text formatting (cursor-based; canvas supplies the cursor)

    void applyStyle(QTextCursor cursor, const QString &role);
    /// Re-applies a (changed) style definition to every paragraph using it,
    /// preserving run-level deltas — the S3 engine's job on the Mac.
    void redefineStyle(const QString &role, const ParagraphStyle &def);
    QString styleRoleAt(const QTextCursor &cursor) const;

    void toggleList(QTextCursor cursor, bool ordered, const QString &marker);
    void changeListLevel(QTextCursor cursor, int delta);
    void insertPageBreak(QTextCursor cursor);

    // MARK: - Model-level settings (undoable)

    void setPageConfig(const PageConfig &page);
    void setFurniture(const std::optional<PageFurniture> &header,
                      const std::optional<PageFurniture> &footer,
                      std::optional<int> pageNumberStart);

    // MARK: - Furniture rendering support

    QString furnitureZoneText(const QString &zoneTemplate, int physicalPage) const;

    /// Renders one page's content (text, images, furniture, fold marks) with
    /// the painter's origin at the page sheet's top-left — shared by PDF
    /// export and printing so they match the screen exactly, minus the desk
    /// chrome (shadows, borders, selection).
    void renderPage(QPainter *painter, int pageIndex) const;

signals:
    /// A non-text command was pushed onto the unified stack. QTextDocument
    /// merges adjacent same-format insertions into one internal undo command,
    /// which would let typing AFTER an object/settings command coalesce into
    /// the text command BEFORE it and break undo ordering — listeners (the
    /// canvas) perturb the pending typing format so the next insertion starts
    /// a fresh document undo command.
    void undoCoalescingBreak();
    /// Objects/geometry changed — canvas must resync image frames and repaint.
    void objectsChanged();
    /// Page config / furniture changed (full canvas refresh).
    void pageSetupChanged();
    void modifiedChanged();

private:
    friend class ObjectsCommand;
    void applyObjects(const QVector<PlacedObject> &objects);
    void pushObjectsCommand(const QString &text, const QVector<PlacedObject> &before,
                            const QVector<PlacedObject> &after,
                            const QMap<QString, QByteArray> &addedImages = {});
    void applyParagraphStyleFormats(QTextCursor &cursor, const QString &role);

    DocumentModel m_model;
    QMap<QString, QByteArray> m_images;
    QVector<HistorySnapshot> m_history;
    mutable QMap<QString, QImage> m_imageCache;
    QTextDocument *m_doc;
    PageLayout *m_layout;
    QUndoStack *m_undo;
    QString m_filePath;
    bool m_inUndoRedo = false;
};

} // namespace lucerne
