import 'dart:convert';
import 'dart:typed_data';

/// A file in a zip: its path inside ('/' between folders), when it last
/// changed, and its bytes, read once the archive reaches it.
typedef ZipEntry = ({String name, DateTime modified, Stream<List<int>> bytes});

/// A zip of [entries] (APPNOTE 6.3.10), streamed as it is read: each file is
/// stored as it comes, its CRC and sizes in a data descriptor after it, so
/// memory holds a chunk and the central directory whatever the sizes. Always
/// zip64, so that neither a file nor the archive stops at 4 GiB.
Stream<List<int>> zip(Stream<ZipEntry> entries) async* {
  final directory = BytesBuilder(copy: false);
  var offset = 0, count = 0;
  await for (final entry in entries) {
    final name = utf8.encode(entry.name);
    final time = _dosTime(entry.modified.toLocal());
    final header =
        (_Writer(30 + name.length + 20)
              ..u32(0x04034b50)
              ..u16(45) // version 4.5: zip64
              ..u16(_flags)
              ..u16(0) // stored
              ..u32(time)
              ..u32(0) // the CRC and sizes are in the descriptor
              ..u32(0xffffffff)
              ..u32(0xffffffff)
              ..u16(name.length)
              ..u16(20)
              ..bytes(name)
              ..u16(1) // zip64 sizes
              ..u16(16)
              ..u64(0)
              ..u64(0))
            .done;
    yield header;
    final crc = _Crc32();
    var size = 0;
    await for (final chunk in entry.bytes) {
      crc.add(chunk);
      size += chunk.length;
      yield chunk;
    }
    yield (_Writer(24)
          ..u32(0x08074b50)
          ..u32(crc.value)
          ..u64(size)
          ..u64(size))
        .done;
    directory.add(
      (_Writer(46 + name.length + 28)
            ..u32(0x02014b50)
            ..u16(45)
            ..u16(45)
            ..u16(_flags)
            ..u16(0)
            ..u32(time)
            ..u32(crc.value)
            ..u32(0xffffffff)
            ..u32(0xffffffff)
            ..u16(name.length)
            ..u16(28)
            ..u16(0) // comment
            ..u16(0) // disk
            ..u16(0) // internal attributes
            ..u32(0) // external attributes
            ..u32(0xffffffff)
            ..bytes(name)
            ..u16(1)
            ..u16(24)
            ..u64(size)
            ..u64(size)
            ..u64(offset))
          .done,
    );
    offset += header.length + size + 24;
    count++;
  }
  final size = directory.length;
  yield directory.takeBytes();
  yield (_Writer(56 + 20 + 22)
        ..u32(0x06064b50) // zip64 end of central directory
        ..u64(44)
        ..u16(45)
        ..u16(45)
        ..u32(0)
        ..u32(0)
        ..u64(count)
        ..u64(count)
        ..u64(size)
        ..u64(offset)
        ..u32(0x07064b50) // its locator
        ..u32(0)
        ..u64(offset + size)
        ..u32(1)
        ..u32(0x06054b50) // end of central directory, deferring to zip64
        ..u16(0)
        ..u16(0)
        ..u16(0xffff)
        ..u16(0xffff)
        ..u32(0xffffffff)
        ..u32(0xffffffff)
        ..u16(0))
      .done;
}

/// A data descriptor follows each file (bit 3); names are UTF-8 (bit 11).
const _flags = 0x0808;

/// MS-DOS date and time, as zip tools show them, from 1980 to 2107.
int _dosTime(DateTime t) => t.year < 1980
    ? 0x00210000
    : t.year > 2107
    ? 0xff9fbf7d
    : (t.year - 1980) << 25 |
          t.month << 21 |
          t.day << 16 |
          t.hour << 11 |
          t.minute << 5 |
          t.second ~/ 2;

class _Writer {
  _Writer(int length) : done = Uint8List(length);

  final Uint8List done;
  late final _data = ByteData.sublistView(done);
  var _at = 0;

  void u16(int v) => _data.setUint16((_at += 2) - 2, v, Endian.little);
  void u32(int v) => _data.setUint32((_at += 4) - 4, v, Endian.little);
  void u64(int v) {
    u32(v % 0x100000000);
    u32(v ~/ 0x100000000);
  }

  void bytes(List<int> v) => done.setAll((_at += v.length) - v.length, v);
}

/// CRC-32 (ISO 3309), slicing by 8.
class _Crc32 {
  static final _table = () {
    final t = Uint32List(8 * 256);
    for (var n = 0; n < 256; n++) {
      var c = n;
      for (var k = 0; k < 8; k++) {
        c = c & 1 != 0 ? 0xedb88320 ^ (c >> 1) : c >> 1;
      }
      t[n] = c;
    }
    for (var n = 256; n < 8 * 256; n++) {
      final c = t[n - 256];
      t[n] = t[c & 0xff] ^ (c >> 8);
    }
    return t;
  }();

  var _c = 0xffffffff;

  int get value => _c ^ 0xffffffff;

  void add(List<int> bytes) {
    final t = _table;
    var c = _c, i = 0;
    for (final end = bytes.length & ~7; i < end; i += 8) {
      final a =
          c ^
          (bytes[i] | bytes[i + 1] << 8 | bytes[i + 2] << 16) +
              bytes[i + 3] * 0x1000000;
      c =
          t[0x700 + (a & 0xff)] ^
          t[0x600 + (a >> 8 & 0xff)] ^
          t[0x500 + (a >> 16 & 0xff)] ^
          t[0x400 + (a >> 24 & 0xff)] ^
          t[0x300 + bytes[i + 4]] ^
          t[0x200 + bytes[i + 5]] ^
          t[0x100 + bytes[i + 6]] ^
          t[bytes[i + 7]];
    }
    for (; i < bytes.length; i++) {
      c = t[(c ^ bytes[i]) & 0xff] ^ (c >> 8);
    }
    _c = c;
  }
}
