/// A small ZIP writer and reader for backups: plain `dart:io`, no package.
///
/// Supported: stored (method 0) and deflated (method 8) entries with UTF-8
/// names, which every unzip tool reads. Not supported (and refused with a
/// [ZipException]): ZIP64 (archives over 4 GiB or with more than 65,535
/// entries), encryption, multi-disk archives and other methods.
///
/// Format reference: PKWARE APPNOTE.TXT, sections 4.3.7 (local header),
/// 4.3.12 (central directory) and 4.3.16 (end of central directory).
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

/// The archive is unreadable, or cannot be written in this format.
class ZipException implements Exception {
  const ZipException(this.message);

  final String message;

  @override
  String toString() => 'ZipException: $message';
}

abstract final class _Sig {
  static const int local = 0x04034b50;
  static const int central = 0x02014b50;
  static const int end = 0x06054b50;
}

/// Largest offset or size a non-ZIP64 archive can hold.
const int _max32 = 0xFFFFFFFF;
const int _maxEntries = 0xFFFF;

/// General purpose flag bit 11: names are UTF-8. Bit 0: encrypted.
const int _flagUtf8 = 0x0800;
const int _flagEncrypted = 0x0001;

const int _methodStore = 0;
const int _methodDeflate = 8;

/// "Version needed to extract" 2.0: deflate.
const int _versionNeeded = 20;

/// Streams are copied in chunks of this size.
const int _chunkBytes = 1 << 20;

/// CRC-32 (IEEE 802.3, the one ZIP uses), fed in pieces.
class Crc32 {
  int _crc = 0xFFFFFFFF;

  static final Uint32List _table = _makeTable();

  static Uint32List _makeTable() {
    final table = Uint32List(256);
    for (var n = 0; n < 256; n++) {
      var c = n;
      for (var k = 0; k < 8; k++) {
        c = (c & 1) != 0 ? 0xEDB88320 ^ (c >>> 1) : c >>> 1;
      }
      table[n] = c;
    }
    return table;
  }

  void add(List<int> bytes) {
    var c = _crc;
    for (final b in bytes) {
      c = _table[(c ^ b) & 0xFF] ^ (c >>> 8);
    }
    _crc = c;
  }

  int get value => _crc ^ 0xFFFFFFFF;

  static int of(List<int> bytes) => (Crc32()..add(bytes)).value;
}

/// Whether [name] is a safe relative entry path: `/`-separated, no empty,
/// `.` or `..` segments, no backslashes, drive letters or leading slash.
/// Extracting such a name under a folder can never leave that folder.
bool isSafeZipPath(String name) {
  if (name.isEmpty || name.startsWith('/') || name.contains('\\')) {
    return false;
  }
  if (name.contains(':') || name.contains('\u0000')) return false;
  for (final segment in name.split('/')) {
    if (segment.isEmpty || segment == '.' || segment == '..') return false;
  }
  return true;
}

/// Writes a ZIP archive to a file, one entry at a time. Memory stays at
/// about one entry when it is deflated, and one chunk when it is stored.
class ZipWriter {
  ZipWriter._(this.file, this._raf, this._dosTime, this._dosDate);

  /// Creates (or truncates) [file]. [modified] is the time stamped on every
  /// entry (default: now).
  static Future<ZipWriter> create(File file, {DateTime? modified}) async {
    await file.parent.create(recursive: true);
    final raf = await file.open(mode: FileMode.write);
    final t = (modified ?? DateTime.now()).toLocal();
    return ZipWriter._(file, raf, _dosTimeOf(t), _dosDateOf(t));
  }

  final File file;
  final RandomAccessFile _raf;
  final int _dosTime;
  final int _dosDate;
  final List<_CentralRecord> _records = [];
  final Set<String> _names = {};
  bool _closed = false;

  int get entryCount => _records.length;

  /// Adds an entry with [bytes]. With [compress], it is deflated unless
  /// that does not make it smaller.
  Future<void> addBytes(String name, List<int> bytes,
      {bool compress = true}) async {
    final nameBytes = _checkName(name);
    final crc = Crc32.of(bytes);
    var method = _methodStore;
    List<int> data = bytes;
    if (compress && bytes.isNotEmpty) {
      final deflated = ZLibCodec(raw: true, level: 6).encode(bytes);
      if (deflated.length < bytes.length) {
        method = _methodDeflate;
        data = deflated;
      }
    }
    final offset = await _raf.position();
    _checkFits(offset + 30 + nameBytes.length + data.length);
    await _raf.writeFrom(
        _localHeader(nameBytes, method, crc, data.length, bytes.length));
    await _raf.writeFrom(data);
    _records.add(_CentralRecord(
        nameBytes, method, crc, data.length, bytes.length, offset));
  }

  /// Adds the contents of [source]. Deflated files are read into memory
  /// whole, so pass [compress] only for files of a few megabytes (JSON);
  /// stored files are streamed.
  Future<void> addFile(String name, File source, {bool compress = false}) async {
    if (compress) {
      await addBytes(name, await source.readAsBytes(), compress: true);
      return;
    }
    final nameBytes = _checkName(name);
    final offset = await _raf.position();
    final expected = await source.length();
    _checkFits(offset + 30 + nameBytes.length + expected);
    // The header is written with the sizes known now and patched below
    // with what was actually read (CRC included).
    await _raf.writeFrom(_localHeader(nameBytes, _methodStore, 0, 0, 0));
    final crc = Crc32();
    var size = 0;
    await for (final chunk in source.openRead()) {
      crc.add(chunk);
      size += chunk.length;
      _checkFits(offset + 30 + nameBytes.length + size);
      await _raf.writeFrom(chunk);
    }
    final end = await _raf.position();
    await _raf.setPosition(offset);
    await _raf.writeFrom(
        _localHeader(nameBytes, _methodStore, crc.value, size, size));
    await _raf.setPosition(end);
    _records.add(_CentralRecord(
        nameBytes, _methodStore, crc.value, size, size, offset));
  }

  /// Writes the central directory and closes the file.
  Future<void> close() async {
    if (_closed) return;
    final start = await _raf.position();
    final out = BytesBuilder(copy: false);
    for (final r in _records) {
      out.add(_centralHeader(r));
    }
    final dir = out.takeBytes();
    _checkFits(start + dir.length + 22);
    await _raf.writeFrom(dir);
    final end = ByteData(22)
      ..setUint32(0, _Sig.end, Endian.little)
      ..setUint16(4, 0, Endian.little) // this disk
      ..setUint16(6, 0, Endian.little) // disk with the directory
      ..setUint16(8, _records.length, Endian.little)
      ..setUint16(10, _records.length, Endian.little)
      ..setUint32(12, dir.length, Endian.little)
      ..setUint32(16, start, Endian.little)
      ..setUint16(20, 0, Endian.little); // comment length
    await _raf.writeFrom(end.buffer.asUint8List());
    await _raf.flush();
    await _raf.close();
    _closed = true;
  }

  /// Closes and deletes the unfinished archive. Never throws.
  Future<void> abort() async {
    try {
      if (!_closed) await _raf.close();
    } catch (_) {}
    _closed = true;
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  Uint8List _checkName(String name) {
    if (!isSafeZipPath(name)) throw ZipException('Bad entry name: $name');
    if (!_names.add(name)) throw ZipException('Duplicate entry: $name');
    if (_records.length >= _maxEntries) {
      throw const ZipException('Too many files for one archive');
    }
    final bytes = utf8.encode(name);
    if (bytes.length > 0xFFFF) throw ZipException('Name too long: $name');
    return Uint8List.fromList(bytes);
  }

  static void _checkFits(int offset) {
    if (offset > _max32) {
      throw const ZipException('The archive would be larger than 4 GB');
    }
  }

  Uint8List _localHeader(
      Uint8List name, int method, int crc, int compressed, int size) {
    final h = ByteData(30)
      ..setUint32(0, _Sig.local, Endian.little)
      ..setUint16(4, _versionNeeded, Endian.little)
      ..setUint16(6, _flagUtf8, Endian.little)
      ..setUint16(8, method, Endian.little)
      ..setUint16(10, _dosTime, Endian.little)
      ..setUint16(12, _dosDate, Endian.little)
      ..setUint32(14, crc, Endian.little)
      ..setUint32(18, compressed, Endian.little)
      ..setUint32(22, size, Endian.little)
      ..setUint16(26, name.length, Endian.little)
      ..setUint16(28, 0, Endian.little); // extra field length
    return (BytesBuilder(copy: false)
          ..add(h.buffer.asUint8List())
          ..add(name))
        .takeBytes();
  }

  Uint8List _centralHeader(_CentralRecord r) {
    final h = ByteData(46)
      ..setUint32(0, _Sig.central, Endian.little)
      ..setUint16(4, _versionNeeded, Endian.little) // made by (MS-DOS, 2.0)
      ..setUint16(6, _versionNeeded, Endian.little)
      ..setUint16(8, _flagUtf8, Endian.little)
      ..setUint16(10, r.method, Endian.little)
      ..setUint16(12, _dosTime, Endian.little)
      ..setUint16(14, _dosDate, Endian.little)
      ..setUint32(16, r.crc, Endian.little)
      ..setUint32(20, r.compressed, Endian.little)
      ..setUint32(24, r.size, Endian.little)
      ..setUint16(28, r.name.length, Endian.little)
      ..setUint16(30, 0, Endian.little) // extra
      ..setUint16(32, 0, Endian.little) // comment
      ..setUint16(34, 0, Endian.little) // disk number start
      ..setUint16(36, 0, Endian.little) // internal attributes
      ..setUint32(38, 0, Endian.little) // external attributes
      ..setUint32(42, r.offset, Endian.little);
    return (BytesBuilder(copy: false)
          ..add(h.buffer.asUint8List())
          ..add(r.name))
        .takeBytes();
  }

  // MS-DOS time: 5 bits hour, 6 bits minute, 5 bits seconds / 2; date: 7
  // bits years since 1980, 4 bits month, 5 bits day.
  static int _dosTimeOf(DateTime t) =>
      (t.hour << 11) | (t.minute << 5) | (t.second ~/ 2);
  static int _dosDateOf(DateTime t) =>
      ((math.max(t.year, 1980) - 1980).clamp(0, 127) << 9) |
      (t.month << 5) |
      t.day;
}

class _CentralRecord {
  _CentralRecord(this.name, this.method, this.crc, this.compressed, this.size,
      this.offset);

  final Uint8List name;
  final int method;
  final int crc;
  final int compressed;
  final int size;
  final int offset;
}

/// One file in a [ZipReader].
class ZipEntry {
  const ZipEntry._(this.name, this._method, this._crc, this.compressedSize,
      this.size, this._headerOffset);

  final String name;
  final int _method;
  final int _crc;
  final int compressedSize;

  /// Uncompressed size in bytes.
  final int size;
  final int _headerOffset;

  bool get isDirectory => name.endsWith('/');
}

/// Reads a ZIP archive from a file. Every entry's CRC is checked when it is
/// read, so a damaged archive fails instead of restoring damaged files.
class ZipReader {
  ZipReader._(this._raf, this._length, this.entries);

  /// Largest entry inflated in memory (deflated entries are inflated whole).
  static const int maxInflatedBytes = 256 * 1024 * 1024;

  final RandomAccessFile _raf;
  final int _length;

  /// The entries in archive order.
  final List<ZipEntry> entries;

  /// Opens [file] and reads its directory. Throws [ZipException] when it is
  /// not a ZIP archive this reader supports.
  static Future<ZipReader> open(File file) async {
    final raf = await file.open();
    try {
      final length = await raf.length();
      final entries = await _readDirectory(raf, length);
      return ZipReader._(raf, length, entries);
    } catch (e) {
      await raf.close();
      if (e is ZipException) rethrow;
      if (e is FileSystemException) rethrow;
      throw ZipException('Not a readable archive ($e)');
    }
  }

  ZipEntry? entry(String name) {
    for (final e in entries) {
      if (e.name == name) return e;
    }
    return null;
  }

  /// The contents of [e], checked against its CRC.
  Future<Uint8List> readBytes(ZipEntry e) async {
    final start = await _dataStart(e);
    if (e._method == _methodStore) {
      final bytes = await _read(start, e.compressedSize);
      _checkCrc(e, Crc32.of(bytes), bytes.length);
      return bytes;
    }
    if (e.size > maxInflatedBytes) {
      throw ZipException('${e.name} is too large to unpack');
    }
    final compressed = await _read(start, e.compressedSize);
    final List<int> inflated;
    try {
      inflated = ZLibCodec(raw: true).decode(compressed);
    } on FormatException catch (err) {
      throw ZipException('${e.name} is damaged ($err)');
    }
    final bytes =
        inflated is Uint8List ? inflated : Uint8List.fromList(inflated);
    _checkCrc(e, Crc32.of(bytes), bytes.length);
    return bytes;
  }

  /// Writes the contents of [e] to [target] (stored entries are streamed).
  /// On a CRC mismatch the target is deleted and a [ZipException] thrown.
  Future<void> extractTo(ZipEntry e, File target) async {
    await target.parent.create(recursive: true);
    if (e._method != _methodStore) {
      await target.writeAsBytes(await readBytes(e), flush: true);
      return;
    }
    final start = await _dataStart(e);
    final out = await target.open(mode: FileMode.write);
    final crc = Crc32();
    var done = 0;
    try {
      while (done < e.compressedSize) {
        final n = math.min(_chunkBytes, e.compressedSize - done);
        final chunk = await _read(start + done, n);
        crc.add(chunk);
        await out.writeFrom(chunk);
        done += n;
      }
      await out.flush();
    } finally {
      await out.close();
    }
    try {
      _checkCrc(e, crc.value, done);
    } on ZipException {
      await target.delete();
      rethrow;
    }
  }

  Future<void> close() => _raf.close();

  void _checkCrc(ZipEntry e, int crc, int size) {
    if (size != e.size || crc != e._crc) {
      throw ZipException('${e.name} is damaged (checksum mismatch)');
    }
  }

  Future<int> _dataStart(ZipEntry e) async {
    final h = ByteData.sublistView(await _read(e._headerOffset, 30));
    if (h.getUint32(0, Endian.little) != _Sig.local) {
      throw ZipException('${e.name}: bad local header');
    }
    final start = e._headerOffset +
        30 +
        h.getUint16(26, Endian.little) +
        h.getUint16(28, Endian.little);
    if (start + e.compressedSize > _length) {
      throw ZipException('${e.name} runs past the end of the archive');
    }
    return start;
  }

  Future<Uint8List> _read(int offset, int count) async {
    if (offset < 0 || count < 0 || offset + count > _length) {
      throw const ZipException('The archive is cut short');
    }
    await _raf.setPosition(offset);
    final bytes = await _raf.read(count);
    if (bytes.length != count) {
      throw const ZipException('The archive is cut short');
    }
    return bytes;
  }

  static Future<List<ZipEntry>> _readDirectory(
      RandomAccessFile raf, int length) async {
    if (length < 22) throw const ZipException('Not a ZIP archive');
    // The end record is the last 22 bytes plus a comment of up to 64 KiB.
    final tailLength = math.min(length, 22 + 0xFFFF);
    await raf.setPosition(length - tailLength);
    final tail = ByteData.sublistView(await raf.read(tailLength));
    var at = -1;
    for (var i = tail.lengthInBytes - 22; i >= 0; i--) {
      if (tail.getUint32(i, Endian.little) == _Sig.end) {
        at = i;
        break;
      }
    }
    if (at < 0) throw const ZipException('Not a ZIP archive');
    final disk = tail.getUint16(at + 4, Endian.little);
    final dirDisk = tail.getUint16(at + 6, Endian.little);
    final count = tail.getUint16(at + 10, Endian.little);
    final dirSize = tail.getUint32(at + 12, Endian.little);
    final dirOffset = tail.getUint32(at + 16, Endian.little);
    if (disk != 0 || dirDisk != 0) {
      throw const ZipException('Multi-part archives are not supported');
    }
    if (dirOffset == _max32 || count == _maxEntries) {
      throw const ZipException('ZIP64 archives are not supported');
    }
    if (dirOffset + dirSize > length) {
      throw const ZipException('The archive is cut short');
    }
    await raf.setPosition(dirOffset);
    final dir = ByteData.sublistView(await raf.read(dirSize));
    final entries = <ZipEntry>[];
    var p = 0;
    for (var i = 0; i < count; i++) {
      if (p + 46 > dir.lengthInBytes ||
          dir.getUint32(p, Endian.little) != _Sig.central) {
        throw const ZipException('Damaged archive directory');
      }
      final flags = dir.getUint16(p + 8, Endian.little);
      final method = dir.getUint16(p + 10, Endian.little);
      final crc = dir.getUint32(p + 16, Endian.little);
      final compressed = dir.getUint32(p + 20, Endian.little);
      final size = dir.getUint32(p + 24, Endian.little);
      final nameLength = dir.getUint16(p + 28, Endian.little);
      final extraLength = dir.getUint16(p + 30, Endian.little);
      final commentLength = dir.getUint16(p + 32, Endian.little);
      final offset = dir.getUint32(p + 42, Endian.little);
      final nameEnd = p + 46 + nameLength;
      if (nameEnd > dir.lengthInBytes) {
        throw const ZipException('Damaged archive directory');
      }
      final nameBytes = dir.buffer
          .asUint8List(dir.offsetInBytes + p + 46, nameLength);
      final name = (flags & _flagUtf8) != 0
          ? utf8.decode(nameBytes)
          : latin1.decode(nameBytes);
      if ((flags & _flagEncrypted) != 0) {
        throw ZipException('$name is encrypted');
      }
      if (method != _methodStore && method != _methodDeflate) {
        throw ZipException('$name uses an unsupported compression');
      }
      if (compressed == _max32 || size == _max32 || offset == _max32) {
        throw const ZipException('ZIP64 archives are not supported');
      }
      entries.add(ZipEntry._(name, method, crc, compressed, size, offset));
      p = nameEnd + extraLength + commentLength;
    }
    return entries;
  }
}
