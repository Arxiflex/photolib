import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photolib/features/download/zip.dart';

ZipEntry entry(String name, List<List<int>> chunks, DateTime modified) =>
    (name: name, modified: modified, bytes: Stream.fromIterable(chunks));

// Each file's name, size, time and SHA-256 as Python's zipfile reads them,
// and the first whose CRC is wrong.
const _read = '''
import hashlib, json, sys, zipfile
with zipfile.ZipFile(sys.argv[1]) as z:
    print(json.dumps({"bad": z.testzip(), "files": [[i.filename, i.file_size,
        list(i.date_time), hashlib.sha256(z.read(i)).hexdigest()]
        for i in z.infolist()]}))
''';

void main() {
  test(
    'Python reads back every file: names, folders, bytes and times',
    () async {
      final dir = await Directory.systemTemp.createTemp('zip');
      addTearDown(() => dir.delete(recursive: true));
      final path = '${dir.path}/a.zip';
      final big = [for (var i = 0; i < 200003; i++) i * 7 & 0xff];
      await zip(
        Stream.fromIterable([
          entry('IMG_0001.JPG', [
            utf8.encode('photo'),
          ], DateTime(2024, 5, 6, 7, 8, 11)),
          entry('Été/clip.mov', [big], DateTime(2023, 12, 31, 23, 59, 58)),
          entry('empty.png', [], DateTime(1970)),
          entry('Été/split.bin', [
            [1, 2],
            [3],
            [4, 5, 6, 7, 8, 9, 10],
          ], DateTime(2024)),
        ]),
      ).pipe(File(path).openWrite());
      final read = await Process.run('python3', ['-c', _read, path]);
      expect(read.stderr, '');
      String hash(List<int> bytes) => '${sha256.convert(bytes)}';
      expect(jsonDecode(read.stdout as String), {
        'bad': null,
        'files': [
          [
            'IMG_0001.JPG',
            5,
            [2024, 5, 6, 7, 8, 10],
            hash(utf8.encode('photo')),
          ],
          [
            'Été/clip.mov',
            big.length,
            [2023, 12, 31, 23, 59, 58],
            hash(big),
          ],
          [
            'empty.png',
            0,
            [1980, 1, 1, 0, 0, 0],
            hash([]),
          ],
          [
            'Été/split.bin',
            10,
            [2024, 1, 1, 0, 0, 0],
            hash([1, 2, 3, 4, 5, 6, 7, 8, 9, 10]),
          ],
        ],
      });
    },
  );

  test('a time in UTC is written as the wall clock here, as zip tools read '
      'it', () async {
    final dir = await Directory.systemTemp.createTemp('zip');
    addTearDown(() => dir.delete(recursive: true));
    final path = '${dir.path}/a.zip';
    final taken = DateTime.utc(2019, 7, 14, 12, 30);
    await zip(Stream.value(entry('a.jpg', [], taken)))
        .pipe(File(path).openWrite());
    final read = await Process.run('python3', ['-c', _read, path]);
    final here = taken.toLocal();
    expect(
      ((jsonDecode(read.stdout as String) as Map)['files'] as List).single[2],
      [here.year, here.month, here.day, here.hour, here.minute, 0],
    );
  });

  test(
    'a file dated 2100 keeps its date, one past 2107 the last a zip holds',
    () async {
      final dir = await Directory.systemTemp.createTemp('zip');
      addTearDown(() => dir.delete(recursive: true));
      final path = '${dir.path}/a.zip';
      await zip(
        Stream.fromIterable([
          entry('a', [], DateTime(2100, 2, 3, 4, 5, 6)),
          entry('b', [], DateTime(2200)),
        ]),
      ).pipe(File(path).openWrite());
      final read = await Process.run('python3', ['-c', _read, path]);
      expect(read.stderr, '');
      expect(
        [
          for (final f
              in (jsonDecode(read.stdout as String) as Map)['files'] as List)
            f[2],
        ],
        [
          [2100, 2, 3, 4, 5, 6],
          [2107, 12, 31, 23, 59, 58],
        ],
      );
    },
  );

  test(
    '2,000 files of 10 GB in all stream through in constant memory',
    () async {
      const files = 2000, size = 5000000, name = 12;
      final chunk = Uint8List(1 << 16)..fillRange(0, 1 << 16, 0x5a);
      Stream<List<int>> bytes() async* {
        for (var left = size; left > 0; left -= chunk.length) {
          yield left < chunk.length
              ? Uint8List.sublistView(chunk, 0, left)
              : chunk;
        }
      }

      final start = ProcessInfo.currentRss;
      var total = 0, peak = start, chunks = 0;
      // The last MiB, where the central directory is.
      final tail = <List<int>>[];
      var kept = 0;
      await for (final c in zip(
        Stream.fromIterable([
          for (var i = 0; i < files; i++)
            entry('IMG_${'$i'.padLeft(4, '0')}.JPG', [], DateTime(2024)),
        ]).map((e) => (name: e.name, modified: e.modified, bytes: bytes())),
      )) {
        total += c.length;
        tail.add(c);
        kept += c.length;
        while (kept - tail.first.length >= 1 << 20) {
          kept -= tail.removeAt(0).length;
        }
        if (++chunks % 4096 == 0 && ProcessInfo.currentRss > peak) {
          peak = ProcessInfo.currentRss;
        }
      }
      final end = ByteData.sublistView(
        Uint8List.fromList([for (final c in tail) ...c]),
      );
      int u16(int at) => end.getUint16(end.lengthInBytes - at, Endian.little);
      int u32(int at) => end.getUint32(end.lengthInBytes - at, Endian.little);
      int u64(int at) => u32(at) + u32(at - 4) * 0x100000000;
      const each = 30 + name + 20 + size + 24, entries = files * each;
      const directory = files * (46 + name + 28);
      expect(total, entries + directory + 56 + 20 + 22);
      expect(u32(22), 0x06054b50, reason: 'end of central directory');
      expect(u32(42), 0x07064b50, reason: 'zip64 locator');
      expect(u64(34), entries + directory, reason: 'where zip64 ends');
      expect(u32(98), 0x06064b50, reason: 'zip64 end of central directory');
      expect([u64(66), u64(58), u64(50)], [files, directory, entries]);
      // Each file's sizes and offset, and that every one has the same CRC.
      final crcs = <int>{};
      for (var i = 0; i < files; i++) {
        final at = 98 + directory - i * (46 + name + 28);
        expect(u32(at), 0x02014b50);
        crcs.add(u32(at - 16));
        expect(u16(at - 28), name);
        expect(
          [u64(at - 46 - name - 4), u64(at - 46 - name - 12)],
          [size, size],
        );
        expect(u64(at - 46 - name - 20), i * each);
      }
      expect(crcs, hasLength(1));
      expect(peak - start, lessThan(64 << 20), reason: 'RSS grew');
    },
  );
}
