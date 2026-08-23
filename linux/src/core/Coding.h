#pragma once

// Centralised JSON encode/decode for the canonical model (the C++ mirror of
// Swift LucerneCore's DocumentCoding.swift):
//   • decoding is forgiving exactly where the spec says readers must be —
//     optional members default per Appendix C, unknown members are ignored —
//     and strict where it says they must reject (format marker, version,
//     required members, semantic ranges);
//   • encoding is deterministic: sorted keys, two-space pretty printing,
//     unescaped '/', integral numbers without a decimal point — so saves are
//     diff-friendly and regeneration is byte-stable.

#include "core/Model.h"

#include <QByteArray>
#include <QJsonObject>
#include <QJsonValue>
#include <stdexcept>

namespace lucerne {

class CodingError : public std::runtime_error {
public:
    enum class Kind {
        Malformed,          // not JSON, wrong types, missing required members
        WrongFormat,        // `format` is not "lucerne-document" (spec §3.1 MUST reject)
        FormatTooNew,       // `formatVersion` above what this build understands (§9)
        InvalidObjectPage,  // page-anchored object outside the editor's page range
        InvalidListLevel,   // list level outside 0…8
    };

    CodingError(Kind kind, const QString &message)
        : std::runtime_error(message.toStdString()), m_kind(kind), m_message(message) {}

    Kind kind() const { return m_kind; }
    QString message() const { return m_message; }

private:
    Kind m_kind;
    QString m_message;
};

namespace Coding {

/// Parses and validates a document.json payload. Throws CodingError.
DocumentModel decode(const QByteArray &json);

/// Serializes the model to the stable reference form described above.
QByteArray encode(const DocumentModel &model);

/// The style-table halves, shared with the style library's interchange file.
QMap<QString, ParagraphStyle> decodeStyleTable(const QJsonObject &object);
QJsonObject encodeStyleTable(const QMap<QString, ParagraphStyle> &styles);

/// Deterministic serializer for any QJsonValue: sorted keys, 2-space indent,
/// integral doubles emitted without a fraction, no '/' escaping.
QByteArray stableJson(const QJsonValue &value);

} // namespace Coding

} // namespace lucerne
