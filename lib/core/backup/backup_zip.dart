import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Deliberately small ZIP profile: STORE only, no encryption, symlinks, ZIP64,
/// extra fields or data descriptors. Limits are checked before reading payloads.
/// Streaming IO keeps large recordings off the Dart heap.
class BackupZip {
  static const maxBytes = 512 * 1024 * 1024;
  static const maxFileBytes = 256 * 1024 * 1024;
  static const maxEntries = 2000;

  static void checkName(String name) {
    if (!RegExp(r'^(manifest\.json|database\.sqlite|media/[a-zA-Z0-9._-]+)$')
            .hasMatch(name) ||
        name.contains('..') || name.length > 200) {
      throw const FormatException('Unsafe backup entry.');
    }
  }

  static final _crcTable = List<int>.generate(256, (value) {
      var crc = value;
      for (var bit = 0; bit < 8; bit++) {
        crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xedb88320 : crc >> 1;
      }
      return crc;
  });

  static int _crc(int crc, List<int> bytes) {
    for (final byte in bytes) {
      crc = _crcTable[(crc ^ byte) & 0xff] ^ (crc >> 8);
    }
    return crc;
  }

  static Future<int> _fileCrc(File file) async {
    var value = 0xffffffff;
    await for (final chunk in file.openRead()) {
      value = _crc(value, chunk);
    }
    return value ^ 0xffffffff;
  }

  static ByteData _header(int size) => ByteData(size);

  static Future<void> write(File output, Map<String, File> files) async {
    if (files.length > maxEntries) throw const FormatException('Too many files.');
    final out = await output.open(mode: FileMode.writeOnly);
    final central = <List<int>>[];
    var total = 0;
    try {
      for (final item in files.entries) {
        checkName(item.key);
        final bytes = utf8.encode(item.key);
        final length = await item.value.length();
        total += length;
        if (length > maxFileBytes || total > maxBytes) {
          throw const FormatException('Backup exceeds supported size.');
        }
        final crc = await _fileCrc(item.value);
        final offset = await out.position();
        final h = _header(30);
        h.setUint32(0, 0x04034b50, Endian.little);
        h.setUint16(4, 20, Endian.little);
        h.setUint16(6, 0x800, Endian.little);
        h.setUint32(14, crc, Endian.little);
        h.setUint32(18, length, Endian.little);
        h.setUint32(22, length, Endian.little);
        h.setUint16(26, bytes.length, Endian.little);
        await out.writeFrom(h.buffer.asUint8List());
        await out.writeFrom(bytes);
        var copied = 0;
        var copiedCrc = 0xffffffff;
        await for (final chunk in item.value.openRead()) {
          copied += chunk.length;
          copiedCrc = _crc(copiedCrc, chunk);
          if (copied > length) throw const FormatException('File changed during backup.');
          await out.writeFrom(chunk);
        }
        if (copied != length || (copiedCrc ^ 0xffffffff) != crc) {
          throw const FormatException('File changed during backup.');
        }
        final c = _header(46);
        c.setUint32(0, 0x02014b50, Endian.little);
        c.setUint16(4, 20, Endian.little);
        c.setUint16(6, 20, Endian.little);
        c.setUint16(8, 0x800, Endian.little);
        c.setUint32(16, crc, Endian.little);
        c.setUint32(20, length, Endian.little);
        c.setUint32(24, length, Endian.little);
        c.setUint16(28, bytes.length, Endian.little);
        c.setUint32(42, offset, Endian.little);
        central.add([...c.buffer.asUint8List(), ...bytes]);
      }
      final start = await out.position();
      for (final entry in central) {
        await out.writeFrom(entry);
      }
      final end = await out.position();
      final e = _header(22);
      e.setUint32(0, 0x06054b50, Endian.little);
      e.setUint16(8, central.length, Endian.little);
      e.setUint16(10, central.length, Endian.little);
      e.setUint32(12, end - start, Endian.little);
      e.setUint32(16, start, Endian.little);
      await out.writeFrom(e.buffer.asUint8List());
      await out.flush();
    } finally {
      await out.close();
    }
  }

  static Future<Uint8List> _read(RandomAccessFile file, int count) async {
    final result = await file.read(count);
    if (result.length != count) throw const FormatException('Truncated backup.');
    return result;
  }

  static Future<Map<String, File>> extract(File input, Directory stage) async {
    final size = await input.length();
    if (size < 22 || size > maxBytes + 1024 * 1024) {
      throw const FormatException('Backup size is invalid.');
    }
    final file = await input.open();
    final entries = <String, File>{};
    try {
      await file.setPosition(size - 22);
      final end = ByteData.sublistView(await _read(file, 22));
      final count = end.getUint16(10, Endian.little);
      final centralSize = end.getUint32(12, Endian.little);
      final centralStart = end.getUint32(16, Endian.little);
      if (end.getUint32(0, Endian.little) != 0x06054b50 ||
          end.getUint32(4, Endian.little) != 0 ||
          end.getUint16(8, Endian.little) != count ||
          end.getUint16(20, Endian.little) != 0 || count < 2 ||
          count > maxEntries || centralStart + centralSize != size - 22) {
        throw const FormatException('Unsupported or damaged ZIP directory.');
      }
      var next = centralStart;
      var localEnd = 0;
      var total = 0;
      for (var i = 0; i < count; i++) {
        await file.setPosition(next);
        final c = ByteData.sublistView(await _read(file, 46));
        final length = c.getUint32(24, Endian.little);
        final nameLength = c.getUint16(28, Endian.little);
        if (c.getUint32(0, Endian.little) != 0x02014b50 ||
            c.getUint16(8, Endian.little) != 0x800 ||
            c.getUint16(10, Endian.little) != 0 ||
            c.getUint32(20, Endian.little) != length ||
            c.getUint32(30, Endian.little) != 0 ||
            c.getUint16(34, Endian.little) != 0 ||
            c.getUint32(38, Endian.little) != 0 ||
            nameLength < 1 || nameLength > 200) {
          throw const FormatException('Unsafe or unsupported ZIP entry.');
        }
        final name = utf8.decode(await _read(file, nameLength));
        checkName(name);
        if (entries.containsKey(name)) throw const FormatException('Duplicate entry.');
        next += 46 + nameLength;
        total += length;
        if (length > maxFileBytes || total > maxBytes ||
            (name == 'manifest.json' && length > 1024 * 1024)) {
          throw const FormatException('Backup extraction limit exceeded.');
        }
        final offset = c.getUint32(42, Endian.little);
        if (offset != localEnd) throw const FormatException('Overlapping ZIP entries.');
        await file.setPosition(offset);
        final h = ByteData.sublistView(await _read(file, 30));
        if (h.getUint32(0, Endian.little) != 0x04034b50 ||
            h.getUint16(6, Endian.little) != 0x800 ||
            h.getUint16(8, Endian.little) != 0 ||
            h.getUint32(14, Endian.little) != c.getUint32(16, Endian.little) ||
            h.getUint32(18, Endian.little) != length ||
            h.getUint32(22, Endian.little) != length ||
            h.getUint16(26, Endian.little) != nameLength ||
            h.getUint16(28, Endian.little) != 0 ||
            utf8.decode(await _read(file, nameLength)) != name) {
          throw const FormatException('ZIP headers disagree.');
        }
        localEnd = offset + 30 + nameLength + length;
        if (localEnd > centralStart) throw const FormatException('Overlapping ZIP data.');
        final dest = File('${stage.path}/$name');
        await dest.parent.create(recursive: true);
        final out = await dest.open(mode: FileMode.writeOnly);
        var crc = 0xffffffff;
        try {
          var remaining = length;
          while (remaining > 0) {
            final chunk = await _read(file, remaining.clamp(1, 65536).toInt());
            remaining -= chunk.length;
            crc = _crc(crc, chunk);
            await out.writeFrom(chunk);
          }
          await out.flush();
        } finally {
          await out.close();
        }
        if ((crc ^ 0xffffffff) != c.getUint32(16, Endian.little)) {
          throw const FormatException('ZIP checksum failed.');
        }
        entries[name] = dest;
      }
      if (next != size - 22 || localEnd != centralStart) {
        throw const FormatException('Unexpected ZIP data.');
      }
      return entries;
    } finally {
      await file.close();
    }
  }
}
