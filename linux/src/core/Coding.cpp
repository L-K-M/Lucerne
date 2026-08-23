#include "core/Coding.h"
#include "core/Lists.h"

#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonValue>

#include <charconv>
#include <cmath>

namespace lucerne {
namespace Coding {

// MARK: - Decode helpers
//
// Mirrors Swift Codable's behavior: a *present* member with the wrong JSON type
// is an error (never silently coerced); an absent member (or JSON null) takes
// the documented default; unknown members are ignored wherever they appear.

namespace {

[[noreturn]] void malformed(const QString &what) {
    throw CodingError(CodingError::Kind::Malformed, what);
}

QJsonValue member(const QJsonObject &o, const char *key) {
    const QJsonValue v = o.value(QLatin1String(key));
    return v.isNull() ? QJsonValue(QJsonValue::Undefined) : v;
}

QString reqString(const QJsonObject &o, const char *key, const QString &context) {
    const QJsonValue v = member(o, key);
    if (!v.isString()) malformed(QStringLiteral("%1: expected string \"%2\"").arg(context, key));
    return v.toString();
}

double reqDouble(const QJsonObject &o, const char *key, const QString &context) {
    const QJsonValue v = member(o, key);
    if (!v.isDouble()) malformed(QStringLiteral("%1: expected number \"%2\"").arg(context, key));
    return v.toDouble();
}

int reqInt(const QJsonObject &o, const char *key, const QString &context) {
    const double d = reqDouble(o, key, context);
    if (d != std::floor(d))
        malformed(QStringLiteral("%1: expected integer \"%2\"").arg(context, key));
    return int(d);
}

QJsonObject reqObject(const QJsonObject &o, const char *key, const QString &context) {
    const QJsonValue v = member(o, key);
    if (!v.isObject()) malformed(QStringLiteral("%1: expected object \"%2\"").arg(context, key));
    return v.toObject();
}

QJsonArray reqArray(const QJsonObject &o, const char *key, const QString &context) {
    const QJsonValue v = member(o, key);
    if (!v.isArray()) malformed(QStringLiteral("%1: expected array \"%2\"").arg(context, key));
    return v.toArray();
}

std::optional<QString> optString(const QJsonObject &o, const char *key, const QString &context) {
    const QJsonValue v = member(o, key);
    if (v.isUndefined()) return std::nullopt;
    if (!v.isString()) malformed(QStringLiteral("%1: expected string \"%2\"").arg(context, key));
    return v.toString();
}

std::optional<double> optDouble(const QJsonObject &o, const char *key, const QString &context) {
    const QJsonValue v = member(o, key);
    if (v.isUndefined()) return std::nullopt;
    if (!v.isDouble()) malformed(QStringLiteral("%1: expected number \"%2\"").arg(context, key));
    return v.toDouble();
}

std::optional<int> optInt(const QJsonObject &o, const char *key, const QString &context) {
    const auto d = optDouble(o, key, context);
    if (!d) return std::nullopt;
    if (*d != std::floor(*d))
        malformed(QStringLiteral("%1: expected integer \"%2\"").arg(context, key));
    return int(*d);
}

std::optional<bool> optBool(const QJsonObject &o, const char *key, const QString &context) {
    const QJsonValue v = member(o, key);
    if (v.isUndefined()) return std::nullopt;
    if (!v.isBool()) malformed(QStringLiteral("%1: expected boolean \"%2\"").arg(context, key));
    return v.toBool();
}

std::optional<QJsonObject> optObject(const QJsonObject &o, const char *key,
                                     const QString &context) {
    const QJsonValue v = member(o, key);
    if (v.isUndefined()) return std::nullopt;
    if (!v.isObject()) malformed(QStringLiteral("%1: expected object \"%2\"").arg(context, key));
    return v.toObject();
}

// MARK: - Piecewise decoders

EdgeInsetsModel decodeInsets(const QJsonObject &o) {
    return {reqDouble(o, "top", QStringLiteral("margins")),
            reqDouble(o, "left", QStringLiteral("margins")),
            reqDouble(o, "bottom", QStringLiteral("margins")),
            reqDouble(o, "right", QStringLiteral("margins"))};
}

PageConfig decodePage(const QJsonObject &o) {
    PageConfig page;
    const QString ctx = QStringLiteral("page");
    page.size = reqString(o, "size", ctx);
    page.width = reqDouble(o, "width", ctx);
    page.height = reqDouble(o, "height", ctx);
    page.margins = decodeInsets(reqObject(o, "margins", ctx));
    page.foldMarks = optBool(o, "foldMarks", ctx);
    return page;
}

ParagraphStyle decodeStyle(const QString &key, const QJsonObject &o) {
    ParagraphStyle s;
    const QString ctx = QStringLiteral("style \"%1\"").arg(key);
    s.name = reqString(o, "name", ctx);
    s.markdown = reqString(o, "markdown", ctx);
    s.font = optString(o, "font", ctx);
    s.size = optDouble(o, "size", ctx);
    s.bold = optBool(o, "bold", ctx);
    s.italic = optBool(o, "italic", ctx);
    s.underline = optBool(o, "underline", ctx);
    s.lineSpacing = optDouble(o, "lineSpacing", ctx);
    s.spaceBefore = optDouble(o, "spaceBefore", ctx);
    s.spaceAfter = optDouble(o, "spaceAfter", ctx);
    s.leftIndent = optDouble(o, "leftIndent", ctx);
    s.firstLineIndent = optDouble(o, "firstLineIndent", ctx);
    s.rightIndent = optDouble(o, "rightIndent", ctx);
    s.alignment = optString(o, "alignment", ctx);
    s.color = optString(o, "color", ctx);
    s.order = optDouble(o, "order", ctx);
    return s;
}

Run decodeRun(const QJsonObject &o, const QString &paragraphID) {
    Run r;
    const QString ctx = QStringLiteral("run in \"%1\"").arg(paragraphID);
    const QJsonValue text = member(o, "text");
    if (!text.isString()) malformed(ctx + QStringLiteral(": expected string \"text\""));
    r.text = text.toString();
    r.bold = optBool(o, "bold", ctx);
    r.italic = optBool(o, "italic", ctx);
    r.underline = optBool(o, "underline", ctx);
    r.font = optString(o, "font", ctx);
    r.size = optDouble(o, "size", ctx);
    r.color = optString(o, "color", ctx);
    return r;
}

Paragraph decodeParagraph(const QJsonObject &o) {
    Paragraph p;
    p.id = reqString(o, "id", QStringLiteral("paragraph"));
    const QString ctx = QStringLiteral("paragraph \"%1\"").arg(p.id);
    p.style = reqString(o, "style", ctx);
    p.align = optString(o, "align", ctx);

    if (auto indent = optObject(o, "indent", ctx)) {
        IndentModel model;
        model.left = optDouble(*indent, "left", ctx);
        model.right = optDouble(*indent, "right", ctx);
        model.firstLine = optDouble(*indent, "firstLine", ctx);
        p.indent = model;
    }
    {
        const QJsonValue v = member(o, "tabStops");
        if (!v.isUndefined()) {
            if (!v.isArray()) malformed(ctx + QStringLiteral(": expected array \"tabStops\""));
            QVector<TabStopModel> stops;
            for (const QJsonValue &item : v.toArray()) {
                if (!item.isObject()) malformed(ctx + QStringLiteral(": bad tab stop"));
                const QJsonObject stop = item.toObject();
                TabStopModel model;
                model.pos = reqDouble(stop, "pos", ctx);
                model.type = optString(stop, "type", ctx).value_or(QStringLiteral("left"));
                stops.append(model);
            }
            p.tabStops = stops;
        }
    }
    p.lineSpacing = optDouble(o, "lineSpacing", ctx);
    p.spaceBefore = optDouble(o, "spaceBefore", ctx);
    p.spaceAfter = optDouble(o, "spaceAfter", ctx);
    p.pageBreakBefore = optBool(o, "pageBreakBefore", ctx);

    if (auto cell = optObject(o, "cell", ctx)) {
        TableCellModel model;
        model.table = reqString(*cell, "table", ctx);
        model.row = reqInt(*cell, "row", ctx);
        model.column = reqInt(*cell, "column", ctx);
        model.rowSpan = optInt(*cell, "rowSpan", ctx).value_or(1);
        model.columnSpan = optInt(*cell, "columnSpan", ctx).value_or(1);
        model.width = optDouble(*cell, "width", ctx);
        p.cell = model;
    }
    if (auto list = optObject(o, "list", ctx)) {
        ListItemModel model;
        model.list = reqString(*list, "list", ctx);
        const QJsonValue ordered = member(*list, "ordered");
        if (!ordered.isBool()) malformed(ctx + QStringLiteral(": expected boolean \"ordered\""));
        model.ordered = ordered.toBool();
        model.marker = reqString(*list, "marker", ctx);
        model.level = optInt(*list, "level", ctx).value_or(0);
        model.start = optInt(*list, "start", ctx);
        p.list = model;
    }

    const QJsonArray runs = reqArray(o, "runs", ctx);
    for (const QJsonValue &item : runs) {
        if (!item.isObject()) malformed(ctx + QStringLiteral(": bad run"));
        p.runs.append(decodeRun(item.toObject(), p.id));
    }
    return p;
}

PlacedObject decodeObject(const QJsonObject &o) {
    PlacedObject obj;
    obj.id = reqString(o, "id", QStringLiteral("object"));
    const QString ctx = QStringLiteral("object \"%1\"").arg(obj.id);
    obj.type = optString(o, "type", ctx).value_or(QStringLiteral("image"));
    obj.src = optString(o, "src", ctx);
    obj.anchor = optString(o, "anchor", ctx).value_or(QStringLiteral("page"));
    obj.page = optInt(o, "page", ctx);
    if (auto frame = optObject(o, "frame", ctx)) {
        obj.frame = RectModel{reqDouble(*frame, "x", ctx), reqDouble(*frame, "y", ctx),
                              reqDouble(*frame, "width", ctx), reqDouble(*frame, "height", ctx)};
    }
    obj.anchorParagraph = optString(o, "anchorParagraph", ctx);
    if (auto offset = optObject(o, "offset", ctx)) {
        obj.offset = PointModel{reqDouble(*offset, "x", ctx), reqDouble(*offset, "y", ctx)};
    }
    obj.wrap = optString(o, "wrap", ctx).value_or(QStringLiteral("rectangular"));
    obj.standoff = optDouble(o, "standoff", ctx).value_or(12);
    obj.z = optInt(o, "z", ctx).value_or(0);
    return obj;
}

PageFurniture decodeFurniture(const QJsonObject &o, const QString &ctx) {
    PageFurniture f;
    f.left = optString(o, "left", ctx).value_or(QString());
    f.center = optString(o, "center", ctx).value_or(QString());
    f.right = optString(o, "right", ctx).value_or(QString());
    return f;
}

/// Codable verifies representation; these are the value checks that depend on
/// editor constraints (mirrors DocumentCoding.validateSemantics).
void validateSemantics(const DocumentModel &model) {
    for (const PlacedObject &object : model.objects) {
        if (object.anchorMode() != PlacedObject::Anchor::Page || !object.page) continue;
        if (*object.page < 0 || *object.page >= DocumentModel::maximumPageCount()) {
            throw CodingError(CodingError::Kind::InvalidObjectPage,
                QStringLiteral("Placed object \"%1\" has page index %2; page indexes "
                               "must be between 0 and %3.")
                    .arg(object.id).arg(*object.page)
                    .arg(DocumentModel::maximumPageCount() - 1));
        }
    }
    for (const Paragraph &paragraph : model.body) {
        if (!paragraph.list) continue;
        const int level = paragraph.list->level;
        if (level < 0 || level > ListGeometry::maximumLevel()) {
            throw CodingError(CodingError::Kind::InvalidListLevel,
                QStringLiteral("Paragraph \"%1\" has list level %2; list levels must "
                               "be between 0 and %3.")
                    .arg(paragraph.id).arg(level).arg(ListGeometry::maximumLevel()));
        }
    }
}

} // namespace

QMap<QString, ParagraphStyle> decodeStyleTable(const QJsonObject &object) {
    QMap<QString, ParagraphStyle> styles;
    for (auto it = object.constBegin(); it != object.constEnd(); ++it) {
        if (!it.value().isObject())
            malformed(QStringLiteral("style \"%1\": expected object").arg(it.key()));
        styles.insert(it.key(), decodeStyle(it.key(), it.value().toObject()));
    }
    return styles;
}

DocumentModel decode(const QByteArray &json) {
    QJsonParseError parseError;
    const QJsonDocument doc = QJsonDocument::fromJson(json, &parseError);
    if (doc.isNull() || !doc.isObject())
        malformed(QStringLiteral("document.json is not a JSON object (%1)")
                      .arg(parseError.errorString()));
    const QJsonObject root = doc.object();

    // Probe format/version before the full decode (spec §3.1 / §9): a foreign
    // file or a future format must fail loudly, not shed unknown fields.
    const QJsonValue format = member(root, "format");
    if (format.isString() && format.toString() != DocumentModel::canonicalFormat()) {
        throw CodingError(CodingError::Kind::WrongFormat,
            QStringLiteral("This is not a Lucerne document (its format is \"%1\", "
                           "expected \"%2\").")
                .arg(format.toString(), DocumentModel::canonicalFormat()));
    }
    const QJsonValue version = member(root, "formatVersion");
    if (version.isDouble() && version.toInt() > DocumentModel::currentFormatVersion()) {
        throw CodingError(CodingError::Kind::FormatTooNew,
            QStringLiteral("This document was saved by a newer version of Lucerne "
                           "(format %1; this app reads up to %2). Please update "
                           "Lucerne to open it.")
                .arg(version.toInt()).arg(DocumentModel::currentFormatVersion()));
    }

    DocumentModel model;
    const QString ctx = QStringLiteral("document");
    model.format = reqString(root, "format", ctx);
    model.formatVersion = reqInt(root, "formatVersion", ctx);
    model.page = decodePage(reqObject(root, "page", ctx));
    model.styles = decodeStyleTable(reqObject(root, "styles", ctx));
    for (const QJsonValue &item : reqArray(root, "body", ctx)) {
        if (!item.isObject()) malformed(QStringLiteral("body: bad paragraph"));
        model.body.append(decodeParagraph(item.toObject()));
    }
    for (const QJsonValue &item : reqArray(root, "objects", ctx)) {
        if (!item.isObject()) malformed(QStringLiteral("objects: bad object"));
        model.objects.append(decodeObject(item.toObject()));
    }
    if (auto header = optObject(root, "header", ctx))
        model.header = decodeFurniture(*header, QStringLiteral("header"));
    if (auto footer = optObject(root, "footer", ctx))
        model.footer = decodeFurniture(*footer, QStringLiteral("footer"));
    model.pageNumberStart = optInt(root, "pageNumberStart", ctx);

    validateSemantics(model);
    return model;
}

// MARK: - Encode

namespace {

void set(QJsonObject &o, const char *key, const QString &value) {
    o.insert(QLatin1String(key), value);
}
void set(QJsonObject &o, const char *key, double value) { o.insert(QLatin1String(key), value); }
void set(QJsonObject &o, const char *key, int value) { o.insert(QLatin1String(key), value); }
void set(QJsonObject &o, const char *key, bool value) { o.insert(QLatin1String(key), value); }

template <typename T>
void setOpt(QJsonObject &o, const char *key, const std::optional<T> &value) {
    if (value) set(o, key, *value);
}

QJsonObject encodeInsets(const EdgeInsetsModel &m) {
    QJsonObject o;
    set(o, "top", m.top);
    set(o, "left", m.left);
    set(o, "bottom", m.bottom);
    set(o, "right", m.right);
    return o;
}

QJsonObject encodePage(const PageConfig &page) {
    QJsonObject o;
    set(o, "size", page.size);
    set(o, "width", page.width);
    set(o, "height", page.height);
    o.insert(QLatin1String("margins"), encodeInsets(page.margins));
    setOpt(o, "foldMarks", page.foldMarks);
    return o;
}

QJsonObject encodeStyle(const ParagraphStyle &s) {
    QJsonObject o;
    set(o, "name", s.name);
    setOpt(o, "font", s.font);
    setOpt(o, "size", s.size);
    setOpt(o, "bold", s.bold);
    setOpt(o, "italic", s.italic);
    setOpt(o, "underline", s.underline);
    setOpt(o, "lineSpacing", s.lineSpacing);
    setOpt(o, "spaceBefore", s.spaceBefore);
    setOpt(o, "spaceAfter", s.spaceAfter);
    setOpt(o, "leftIndent", s.leftIndent);
    setOpt(o, "firstLineIndent", s.firstLineIndent);
    setOpt(o, "rightIndent", s.rightIndent);
    setOpt(o, "alignment", s.alignment);
    setOpt(o, "color", s.color);
    setOpt(o, "order", s.order);
    set(o, "markdown", s.markdown);
    return o;
}

QJsonObject encodeRun(const Run &r) {
    QJsonObject o;
    set(o, "text", r.text);
    setOpt(o, "bold", r.bold);
    setOpt(o, "italic", r.italic);
    setOpt(o, "underline", r.underline);
    setOpt(o, "font", r.font);
    setOpt(o, "size", r.size);
    setOpt(o, "color", r.color);
    return o;
}

QJsonObject encodeParagraph(const Paragraph &p) {
    QJsonObject o;
    set(o, "id", p.id);
    set(o, "style", p.style);
    setOpt(o, "align", p.align);
    if (p.indent) {
        QJsonObject indent;
        setOpt(indent, "left", p.indent->left);
        setOpt(indent, "right", p.indent->right);
        setOpt(indent, "firstLine", p.indent->firstLine);
        o.insert(QLatin1String("indent"), indent);
    }
    if (p.tabStops) {
        QJsonArray stops;
        for (const TabStopModel &stop : *p.tabStops) {
            QJsonObject s;
            set(s, "pos", stop.pos);
            set(s, "type", stop.type);
            stops.append(s);
        }
        o.insert(QLatin1String("tabStops"), stops);
    }
    setOpt(o, "lineSpacing", p.lineSpacing);
    setOpt(o, "spaceBefore", p.spaceBefore);
    setOpt(o, "spaceAfter", p.spaceAfter);
    setOpt(o, "pageBreakBefore", p.pageBreakBefore);
    if (p.cell) {
        QJsonObject cell;
        set(cell, "table", p.cell->table);
        set(cell, "row", p.cell->row);
        set(cell, "column", p.cell->column);
        set(cell, "rowSpan", p.cell->rowSpan);
        set(cell, "columnSpan", p.cell->columnSpan);
        setOpt(cell, "width", p.cell->width);
        o.insert(QLatin1String("cell"), cell);
    }
    if (p.list) {
        QJsonObject list;
        set(list, "list", p.list->list);
        set(list, "ordered", p.list->ordered);
        set(list, "marker", p.list->marker);
        set(list, "level", p.list->level);
        setOpt(list, "start", p.list->start);
        o.insert(QLatin1String("list"), list);
    }
    QJsonArray runs;
    for (const Run &run : p.runs) runs.append(encodeRun(run));
    o.insert(QLatin1String("runs"), runs);
    return o;
}

QJsonObject encodeObject(const PlacedObject &obj) {
    QJsonObject o;
    set(o, "id", obj.id);
    set(o, "type", obj.type);
    setOpt(o, "src", obj.src);
    set(o, "anchor", obj.anchor);
    setOpt(o, "page", obj.page);
    if (obj.frame) {
        QJsonObject frame;
        set(frame, "x", obj.frame->x);
        set(frame, "y", obj.frame->y);
        set(frame, "width", obj.frame->width);
        set(frame, "height", obj.frame->height);
        o.insert(QLatin1String("frame"), frame);
    }
    setOpt(o, "anchorParagraph", obj.anchorParagraph);
    if (obj.offset) {
        QJsonObject offset;
        set(offset, "x", obj.offset->x);
        set(offset, "y", obj.offset->y);
        o.insert(QLatin1String("offset"), offset);
    }
    set(o, "wrap", obj.wrap);
    set(o, "standoff", obj.standoff);
    set(o, "z", obj.z);
    return o;
}

QJsonObject encodeFurniture(const PageFurniture &f) {
    QJsonObject o;
    set(o, "left", f.left);
    set(o, "center", f.center);
    set(o, "right", f.right);
    return o;
}

} // namespace

QJsonObject encodeStyleTable(const QMap<QString, ParagraphStyle> &styles) {
    QJsonObject o;
    for (auto it = styles.constBegin(); it != styles.constEnd(); ++it)
        o.insert(it.key(), encodeStyle(it.value()));
    return o;
}

QByteArray encode(const DocumentModel &model) {
    QJsonObject root;
    set(root, "format", model.format);
    set(root, "formatVersion", model.formatVersion);
    root.insert(QLatin1String("page"), encodePage(model.page));
    root.insert(QLatin1String("styles"), encodeStyleTable(model.styles));
    QJsonArray body;
    for (const Paragraph &p : model.body) body.append(encodeParagraph(p));
    root.insert(QLatin1String("body"), body);
    QJsonArray objects;
    for (const PlacedObject &obj : model.objects) objects.append(encodeObject(obj));
    root.insert(QLatin1String("objects"), objects);
    if (model.header) root.insert(QLatin1String("header"), encodeFurniture(*model.header));
    if (model.footer) root.insert(QLatin1String("footer"), encodeFurniture(*model.footer));
    setOpt(root, "pageNumberStart", model.pageNumberStart);
    return stableJson(root);
}

// MARK: - Stable serializer

namespace {

void appendEscaped(QByteArray &out, const QString &s) {
    out += '"';
    for (const QChar ch : s) {
        const ushort u = ch.unicode();
        switch (u) {
        case '"': out += "\\\""; break;
        case '\\': out += "\\\\"; break;
        case '\n': out += "\\n"; break;
        case '\r': out += "\\r"; break;
        case '\t': out += "\\t"; break;
        case '\b': out += "\\b"; break;
        case '\f': out += "\\f"; break;
        default:
            if (u < 0x20) {
                char buf[8];
                std::snprintf(buf, sizeof buf, "\\u%04x", u);
                out += buf;
            } else {
                out += QString(ch).toUtf8();   // raw UTF-8, '/' unescaped
            }
        }
    }
    out += '"';
}

void appendNumber(QByteArray &out, double d) {
    if (d == std::floor(d) && std::abs(d) < 9.007199254740992e15) {
        out += QByteArray::number(qlonglong(d));
        return;
    }
    // Shortest round-trip representation, like the Swift encoder's output.
    char buf[32];
    const auto result = std::to_chars(buf, buf + sizeof buf, d);
    out.append(buf, int(result.ptr - buf));
}

void appendValue(QByteArray &out, const QJsonValue &v, int depth) {
    const QByteArray indent(2 * depth, ' ');
    const QByteArray childIndent(2 * (depth + 1), ' ');
    switch (v.type()) {
    case QJsonValue::Object: {
        const QJsonObject o = v.toObject();
        QStringList keys = o.keys();
        std::sort(keys.begin(), keys.end());
        if (keys.isEmpty()) { out += "{}"; return; }
        out += "{\n";
        for (int i = 0; i < keys.size(); ++i) {
            out += childIndent;
            appendEscaped(out, keys[i]);
            out += ": ";
            appendValue(out, o.value(keys[i]), depth + 1);
            if (i + 1 < keys.size()) out += ',';
            out += '\n';
        }
        out += indent + "}";
        break;
    }
    case QJsonValue::Array: {
        const QJsonArray a = v.toArray();
        if (a.isEmpty()) { out += "[]"; return; }
        out += "[\n";
        for (int i = 0; i < a.size(); ++i) {
            out += childIndent;
            appendValue(out, a.at(i), depth + 1);
            if (i + 1 < a.size()) out += ',';
            out += '\n';
        }
        out += indent + "]";
        break;
    }
    case QJsonValue::String: appendEscaped(out, v.toString()); break;
    case QJsonValue::Double: appendNumber(out, v.toDouble()); break;
    case QJsonValue::Bool: out += v.toBool() ? "true" : "false"; break;
    default: out += "null"; break;
    }
}

} // namespace

QByteArray stableJson(const QJsonValue &value) {
    QByteArray out;
    appendValue(out, value, 0);
    return out;
}

} // namespace Coding
} // namespace lucerne
