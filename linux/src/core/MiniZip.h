#pragma once

// A tiny, self-contained ZIP reader/writer — the C++ mirror of Swift
// LucerneCore's MiniZip.swift, byte-for-byte compatible on the write side
// (stored entries, deterministic 1980 DOS date, UTF-8 name flag) and equally
// tolerant/strict on the read side (stored + raw-DEFLATE via zlib, CRC-32
// verified, ZIP64 and encryption rejected, hostile sizes capped).

#include <QByteArray>
#include <QString>
#include <QVector>

#include <functional>
#include <stdexcept>

namespace lucerne {
namespace MiniZip {

struct Entry {
    QString name;
    QByteArray data;

    friend bool operator==(const Entry &a, const Entry &b) {
        return a.name == b.name && a.data == b.data;
    }
};

class ZipError : public std::runtime_error {
public:
    enum class Kind { NotAZip, Corrupt, Unsupported };
    ZipError(Kind kind, const QString &message)
        : std::runtime_error(message.toStdString()), m_kind(kind), m_message(message) {}
    Kind kind() const { return m_kind; }
    QString message() const { return m_message; }

private:
    Kind m_kind;
    QString m_message;
};

/// Upper bound on a single entry's uncompressed size: the size field of a
/// hostile archive must not size an inflate buffer unchecked.
constexpr int maxEntrySize = 512 * 1024 * 1024;

/// Builds a stored-only ZIP. Throws ZipError on the same limits the reader
/// enforces (entry size cap, 32-bit offsets), so a save can never produce an
/// archive this code then refuses to reopen.
QByteArray archive(const QVector<Entry> &entries);

/// Reads every entry, verifying structure and each entry's CRC-32. Strict by
/// default; `isDroppable` names entries whose own corruption merely drops them
/// (the .luce recovery snapshots) instead of failing the whole read.
QVector<Entry> entries(const QByteArray &data,
                       const std::function<bool(const QString &)> &isDroppable = {});

/// CRC-32 (IEEE 802.3), exposed for tests.
quint32 crc32(const QByteArray &data);

} // namespace MiniZip
} // namespace lucerne
