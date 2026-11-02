#include "core/MiniZip.h"

#include <zlib.h>
#include <QSet>

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
constexpr quint16 encryptedFlag = 0x0001;
constexpr quint16 storedMethod = 0;
constexpr int localHeaderSize = 30;
constexpr int centralHeaderSize = 46;
constexpr int endOfCentralSize = 22;

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
                          quint16 flags, const QByteArray &name, int compressedSize,
                          int uncompressedSize, qsizetype centralStart) {
    if (localOffset < 0 || localOffset + localHeaderSize > centralStart
        || readLE32(bytes, localOffset) != localHeaderSig)
        corrupt(QStringLiteral("bad local header"));
    const int nameLen = readLE16(bytes, localOffset + 26);
    const int extraLen = readLE16(bytes, localOffset + 28);
    const qsizetype dataStart = localOffset + localHeaderSize + nameLen + extraLen;
    if (dataStart + compressedSize > centralStart)
        corrupt(QStringLiteral("entry data out of bounds"));
    if (readLE16(bytes, localOffset + 6) != flags
        || readLE16(bytes, localOffset + 8) != method
        || bytes.mid(localOffset + localHeaderSize, nameLen) != name)
        corrupt(QStringLiteral("local header disagrees with central directory"));
    if (method == storedMethod && compressedSize != uncompressedSize)
        corrupt(QStringLiteral("stored entry size mismatch"));
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
    if (entries.size() > maxEntryCount)
        unsupported(QStringLiteral("ZIP entry count exceeds the application limit"));

    // Reject the whole save before allocating output, including name/header overhead.
    QSet<QString> names;
    qint64 totalSize = 0;
    qint64 archiveSize = endOfCentralSize;
    for (const Entry &entry : entries) {
        if (names.contains(entry.name)) corrupt(QStringLiteral("duplicate ZIP entry name"));
        names.insert(entry.name);
        const QByteArray nameBytes = entry.name.toUtf8();
        if (QString::fromUtf8(nameBytes) != entry.name)
            unsupported(QStringLiteral("ZIP entry name is not UTF-8"));
        const qsizetype nameSize = nameBytes.size();
        if (nameSize > 0xffff || entry.data.size() > maxEntrySize)
            unsupported(QStringLiteral("ZIP entry exceeds the application size limit"));
        totalSize += entry.data.size();
        archiveSize += entry.data.size() + localHeaderSize + centralHeaderSize + 2 * nameSize;
        if (totalSize > maxTotalSize || archiveSize > maxArchiveSize)
            unsupported(QStringLiteral("ZIP aggregate size exceeds the application limit"));
    }

    QByteArray output;
    QByteArray central;
    struct Record {
        const Entry *entry;
        quint32 crc;
        quint32 offset;
    };
    QVector<Record> records;

    for (const Entry &entry : entries) {
        const QByteArray nameBytes = entry.name.toUtf8();
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
    const quint32 cdSize = readLE32(bytes, eocd + 12);
    const quint32 cdOffset = readLE32(bytes, eocd + 16);
    // ZIP64 uses sentinels rather than ordinary sizes/offsets.
    if (total == 0xffff || cdOffset == 0xffffffffU || cdSize == 0xffffffffU)
        unsupported(QStringLiteral("This archive uses ZIP64 extensions, which Lucerne "
                                   "can't open."));
    if (readLE16(bytes, eocd + 4) != 0 || readLE16(bytes, eocd + 6) != 0
        || readLE16(bytes, eocd + 8) != total)
        unsupported(QStringLiteral("multi-disk ZIP archives are not supported"));
    if (total > maxEntryCount)
        unsupported(QStringLiteral("ZIP entry count exceeds the application limit"));
    if (bytes.size() > maxArchiveSize)
        unsupported(QStringLiteral("ZIP aggregate archive size exceeds the application limit"));
    if (quint64(cdOffset) + cdSize != quint64(eocd))
        corrupt(QStringLiteral("invalid central directory bounds"));

    struct Record {
        QString name;
        QByteArray nameBytes;
        quint16 flags;
        quint16 method;
        quint32 crc;
        int compressedSize;
        int uncompressedSize;
        qsizetype localOffset;
    };
    QVector<Record> records;
    QSet<QString> names;
    qint64 compressedTotal = 0;
    qint64 uncompressedTotal = 0;
    qsizetype cursor = qsizetype(cdOffset);

    // Preflight every record before inflating anything; droppable entries still
    // consume the budget and cannot hide duplicate names or malformed directories.
    for (int i = 0; i < total; ++i) {
        if (cursor + centralHeaderSize > eocd || readLE32(bytes, cursor) != centralHeaderSig)
            corrupt(QStringLiteral("bad central directory header"));
        const quint16 flags = readLE16(bytes, cursor + 8);
        const quint16 method = readLE16(bytes, cursor + 10);
        const quint32 crc = readLE32(bytes, cursor + 16);
        const quint32 compressedSize = readLE32(bytes, cursor + 20);
        const quint32 uncompressedSize = readLE32(bytes, cursor + 24);
        const int nameLen = readLE16(bytes, cursor + 28);
        const int extraLen = readLE16(bytes, cursor + 30);
        const int commentLen = readLE16(bytes, cursor + 32);
        const qsizetype localOffset = qsizetype(readLE32(bytes, cursor + 42));
        const qsizetype recordEnd = cursor + centralHeaderSize + nameLen + extraLen + commentLen;
        if (recordEnd > eocd) corrupt(QStringLiteral("central directory entry overruns its bounds"));
        if ((flags & encryptedFlag) || readLE16(bytes, cursor + 34) != 0)
            unsupported(QStringLiteral("encrypted or multi-disk ZIP entries are not supported"));
        if (compressedSize > maxEntrySize || uncompressedSize > maxEntrySize)
            corrupt(QStringLiteral("entry size out of bounds"));
        compressedTotal += compressedSize;
        uncompressedTotal += uncompressedSize;
        if (compressedTotal > maxTotalSize || uncompressedTotal > maxTotalSize)
            corrupt(QStringLiteral("ZIP aggregate extraction size exceeds the application limit"));

        const QByteArray nameBytes = bytes.mid(cursor + centralHeaderSize, nameLen);
        const QString name = QString::fromUtf8(nameBytes);
        if (name.toUtf8() != nameBytes) corrupt(QStringLiteral("ZIP entry name is not UTF-8"));
        if (names.contains(name)) corrupt(QStringLiteral("duplicate ZIP entry name"));
        names.insert(name);
        records.append({name, nameBytes, flags, method, crc,
                        int(compressedSize), int(uncompressedSize), localOffset});
        cursor = recordEnd;
    }
    if (cursor != eocd) corrupt(QStringLiteral("central directory size does not match its records"));

    QVector<Entry> result;
    for (const Record &record : records) {
        try {
            QByteArray payload = readLocalEntry(bytes, record.localOffset, record.method,
                record.flags, record.nameBytes, record.compressedSize,
                record.uncompressedSize, qsizetype(cdOffset));
            if (crc32(payload) != record.crc)
                corrupt(QStringLiteral("CRC mismatch for %1").arg(record.name));
            result.append({record.name, payload});
        } catch (const ZipError &) {
            if (isDroppable && isDroppable(record.name)) continue;
            throw;
        }
    }
    return result;
}

} // namespace MiniZip
} // namespace lucerne
