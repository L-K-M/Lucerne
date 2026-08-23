#include "core/MiniZip.h"

#include <zlib.h>

#include <cstring>

namespace lucerne {
namespace MiniZip {

namespace {

constexpr quint32 localHeaderSig = 0x04034b50;
constexpr quint32 centralHeaderSig = 0x02014b50;
constexpr quint32 endOfCentralSig = 0x06054b50;
constexpr quint16 dosDate1980 = 0x0021;   // 1980-01-01 (deterministic)
constexpr quint16 dosTimeZero = 0x0000;
/// General-purpose flag bit 11 (EFS): names are UTF-8, not CP437.
constexpr quint16 utf8NameFlag = 0x0800;

void appendLE16(QByteArray &out, quint16 v) {
    out += char(v & 0xff);
    out += char((v >> 8) & 0xff);
}
void appendLE32(QByteArray &out, quint32 v) {
    out += char(v & 0xff);
    out += char((v >> 8) & 0xff);
    out += char((v >> 16) & 0xff);
    out += char((v >> 24) & 0xff);
}
quint16 readLE16(const QByteArray &b, qsizetype at) {
    return quint16(quint8(b[at])) | (quint16(quint8(b[at + 1])) << 8);
}
quint32 readLE32(const QByteArray &b, qsizetype at) {
    return quint32(quint8(b[at])) | (quint32(quint8(b[at + 1])) << 8)
        | (quint32(quint8(b[at + 2])) << 16) | (quint32(quint8(b[at + 3])) << 24);
}

[[noreturn]] void corrupt(const QString &what) {
    throw ZipError(ZipError::Kind::Corrupt, what);
}
[[noreturn]] void unsupported(const QString &what) {
    throw ZipError(ZipError::Kind::Unsupported, what);
}

/// Raw DEFLATE (headerless, windowBits -15 — ZIP entry payload form).
QByteArray inflateRawDeflate(const QByteArray &input, int expectedSize, bool &ok) {
    ok = false;
    if (expectedSize == 0) { ok = true; return {}; }
    if (input.isEmpty()) return {};
    QByteArray output(expectedSize, Qt::Uninitialized);
    z_stream stream;
    std::memset(&stream, 0, sizeof stream);
    stream.next_in = reinterpret_cast<Bytef *>(const_cast<char *>(input.constData()));
    stream.avail_in = uInt(input.size());
    stream.next_out = reinterpret_cast<Bytef *>(output.data());
    stream.avail_out = uInt(output.size());
    if (inflateInit2(&stream, -15) != Z_OK) return {};
    const int status = inflate(&stream, Z_FINISH);
    const int total = int(stream.total_out);
    inflateEnd(&stream);
    if (status != Z_STREAM_END || total != expectedSize) return {};
    ok = true;
    return output;
}

QByteArray readLocalEntry(const QByteArray &bytes, qsizetype localOffset, quint16 method,
                          int compressedSize, int uncompressedSize) {
    if (localOffset < 0 || localOffset + 30 > bytes.size()
        || readLE32(bytes, localOffset) != localHeaderSig)
        corrupt(QStringLiteral("bad local header"));
    if (compressedSize < 0 || uncompressedSize < 0
        || compressedSize > maxEntrySize || uncompressedSize > maxEntrySize)
        corrupt(QStringLiteral("entry size out of bounds"));
    const int nameLen = readLE16(bytes, localOffset + 26);
    const int extraLen = readLE16(bytes, localOffset + 28);
    const qsizetype dataStart = localOffset + 30 + nameLen + extraLen;
    if (dataStart + compressedSize > bytes.size())
        corrupt(QStringLiteral("entry data out of bounds"));
    const QByteArray compressed = bytes.mid(dataStart, compressedSize);

    switch (method) {
    case 0:
        return compressed;
    case 8: {
        bool ok = false;
        QByteArray inflated = inflateRawDeflate(compressed, uncompressedSize, ok);
        if (!ok) corrupt(QStringLiteral("deflate decode failed"));
        return inflated;
    }
    default:
        unsupported(QStringLiteral("compression method %1").arg(method));
    }
}

qsizetype findEndOfCentralDirectory(const QByteArray &bytes) {
    if (bytes.size() < 22) return -1;
    const qsizetype minStart = std::max<qsizetype>(0, bytes.size() - 22 - 0xffff);
    for (qsizetype i = bytes.size() - 22; i >= minStart; --i) {
        if (readLE32(bytes, i) == endOfCentralSig) {
            const int commentLength = readLE16(bytes, i + 20);
            if (i + 22 + commentLength == bytes.size()) return i;
        }
    }
    return -1;
}

} // namespace

quint32 crc32(const QByteArray &data) {
    return quint32(::crc32(0L, reinterpret_cast<const Bytef *>(data.constData()),
                           uInt(data.size())));
}

QByteArray archive(const QVector<Entry> &entries) {
    QByteArray output;
    QByteArray central;
    struct Record {
        const Entry *entry;
        quint32 crc;
        quint32 offset;
    };
    QVector<Record> records;

    for (const Entry &entry : entries) {
        if (entry.data.size() > maxEntrySize)
            unsupported(QStringLiteral("An entry (%1) is too large to store: %2 bytes "
                                       "exceeds the %3-byte limit.")
                            .arg(entry.name).arg(entry.data.size()).arg(maxEntrySize));
        if (quint64(output.size()) > 0xffffffffULL)
            unsupported(QStringLiteral("The archive exceeds ZIP's 4 GiB size limit."));
        const QByteArray nameBytes = entry.name.toUtf8();
        if (nameBytes.size() > 0xffff)
            unsupported(QStringLiteral("An entry name is too long to store."));
        const quint32 dataLen = quint32(entry.data.size());
        const quint32 offset = quint32(output.size());
        const quint32 crc = crc32(entry.data);

        // Local file header (method 0 = stored, deterministic timestamp).
        appendLE32(output, localHeaderSig);
        appendLE16(output, 20);              // version needed
        appendLE16(output, utf8NameFlag);    // gp flag: bit 11 = UTF-8 names
        appendLE16(output, 0);               // method: stored
        appendLE16(output, dosTimeZero);
        appendLE16(output, dosDate1980);
        appendLE32(output, crc);
        appendLE32(output, dataLen);         // compressed size
        appendLE32(output, dataLen);         // uncompressed size
        appendLE16(output, quint16(nameBytes.size()));
        appendLE16(output, 0);               // extra length
        output += nameBytes;
        output += entry.data;

        records.append({&entry, crc, offset});
    }

    if (records.size() > 0xffff)
        unsupported(QStringLiteral("The archive has too many entries for a non-ZIP64 ZIP."));
    if (quint64(output.size()) > 0xffffffffULL)
        unsupported(QStringLiteral("The archive exceeds ZIP's 4 GiB size limit."));
    const quint32 centralStart = quint32(output.size());

    for (const Record &record : records) {
        const QByteArray nameBytes = record.entry->name.toUtf8();
        appendLE32(central, centralHeaderSig);
        appendLE16(central, 20);             // version made by
        appendLE16(central, 20);             // version needed
        appendLE16(central, utf8NameFlag);
        appendLE16(central, 0);              // method: stored
        appendLE16(central, dosTimeZero);
        appendLE16(central, dosDate1980);
        appendLE32(central, record.crc);
        appendLE32(central, quint32(record.entry->data.size()));
        appendLE32(central, quint32(record.entry->data.size()));
        appendLE16(central, quint16(nameBytes.size()));
        appendLE16(central, 0);              // extra length
        appendLE16(central, 0);              // comment length
        appendLE16(central, 0);              // disk number start
        appendLE16(central, 0);              // internal attrs
        appendLE32(central, 0);              // external attrs
        appendLE32(central, record.offset);  // local header offset
        central += nameBytes;
    }
    output += central;
    if (quint64(central.size()) > 0xffffffffULL)
        unsupported(QStringLiteral("The archive's central directory exceeds ZIP's 4 GiB limit."));

    // End of central directory
    appendLE32(output, endOfCentralSig);
    appendLE16(output, 0);                   // disk number
    appendLE16(output, 0);                   // disk with CD start
    appendLE16(output, quint16(records.size()));
    appendLE16(output, quint16(records.size()));
    appendLE32(output, quint32(central.size()));
    appendLE32(output, centralStart);
    appendLE16(output, 0);                   // comment length
    return output;
}

QVector<Entry> entries(const QByteArray &bytes,
                       const std::function<bool(const QString &)> &isDroppable) {
    const qsizetype eocd = findEndOfCentralDirectory(bytes);
    if (eocd < 0) throw ZipError(ZipError::Kind::NotAZip,
                                 QStringLiteral("The file is not a valid .luce archive."));

    const int total = readLE16(bytes, eocd + 10);
    const quint32 cdOffset = readLE32(bytes, eocd + 16);
    // ZIP64 parks sentinels in these fields; fail with an honest "unsupported"
    // rather than chasing 0xFFFFFFFF as a real offset.
    if (total == 0xffff || cdOffset == 0xffffffffU)
        unsupported(QStringLiteral("This archive uses ZIP64 extensions, which Lucerne "
                                   "can't open."));
    qsizetype cursor = qsizetype(cdOffset);

    QVector<Entry> result;
    for (int i = 0; i < total; ++i) {
        if (cursor + 46 > bytes.size() || readLE32(bytes, cursor) != centralHeaderSig)
            corrupt(QStringLiteral("bad central directory header"));
        const quint16 method = readLE16(bytes, cursor + 10);
        const quint32 crc = readLE32(bytes, cursor + 16);
        const int compressedSize = int(readLE32(bytes, cursor + 20));
        const int uncompressedSize = int(readLE32(bytes, cursor + 24));
        const int nameLen = readLE16(bytes, cursor + 28);
        const int extraLen = readLE16(bytes, cursor + 30);
        const int commentLen = readLE16(bytes, cursor + 32);
        const qsizetype localOffset = qsizetype(readLE32(bytes, cursor + 42));
        const qsizetype recordEnd = cursor + 46 + nameLen + extraLen + commentLen;
        if (recordEnd > bytes.size())
            corrupt(QStringLiteral("central directory entry overruns the file"));
        const QString name = QString::fromUtf8(bytes.constData() + cursor + 46, nameLen);
        cursor = recordEnd;

        try {
            QByteArray payload = readLocalEntry(bytes, localOffset, method,
                                                compressedSize, uncompressedSize);
            // The central directory carries the entry's CRC-32; checking it
            // catches truncation and bit rot the structure checks can't.
            if (crc32(payload) != crc)
                corrupt(QStringLiteral("CRC mismatch for %1").arg(name));
            result.append({name, payload});
        } catch (const ZipError &) {
            // Damage confined to a droppable entry's own payload skips just
            // that entry; the central-directory walk above stays strict.
            if (isDroppable && isDroppable(name)) continue;
            throw;
        }
    }
    return result;
}

} // namespace MiniZip
} // namespace lucerne
