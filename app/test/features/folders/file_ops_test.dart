// The sync calls would block the test's isolate as they would the app's.
// ignore_for_file: avoid_slow_async_io

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:photolib/features/folders/file_ops.dart';

void main() {
  late Directory tmp;
  late String a;
  late String b;
  final mtime = DateTime.utc(2001, 2, 3, 4, 5, 6);
  // A JPEG's start with its EXIF block, which no operation may change.
  final jpeg = [0xFF, 0xD8, 0xFF, 0xE1, 0, 8, ...'Exif'.codeUnits, 0, 0];

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('photolib-ops-');
    a = '${tmp.path}/a';
    b = '${tmp.path}/b';
    await Directory(a).create();
    await Directory(b).create();
  });
  tearDown(() => tmp.delete(recursive: true));

  Future<File> file(String path, [int kib = 1]) async {
    final f = File(path);
    await f.writeAsBytes([
      ...jpeg,
      for (var i = 0; i < kib << 10; i++) i % 251,
    ]);
    await f.setLastModified(mtime);
    return f;
  }

  Future<List<String>> names(String dir) async => [
    for (final e in await Directory(dir).list().toList())
      e.path.split('/').last,
  ]..sort();

  test('a rename swaps names without losing a file, refuses a name taken '
      'and is undone', () async {
    await file('$a/1.jpg');
    await file('$a/2.jpg', 2);
    await file('$a/3.jpg', 3);
    final done = await renameFiles([
      ('$a/1.jpg', '$a/2.jpg'),
      ('$a/2.jpg', '$a/1.jpg'),
      ('$a/3.jpg', '$a/x.jpg'),
    ]);
    expect([for (final r in done) r.error], [null, null, null]);
    expect(await File('$a/1.jpg').length(), 2048 + jpeg.length);
    expect((await File('$a/x.jpg').lastModified()).toUtc(), mtime);
    await file('$a/y.jpg');
    final refused = await renameFiles([('$a/x.jpg', '$a/y.jpg')]);
    expect(refused.single.error, 'exists');
    expect(await names(a), ['1.jpg', '2.jpg', 'x.jpg', 'y.jpg']);
    await renameFiles([for (final r in done.reversed) (r.target!, r.source)]);
    expect(await names(a), ['1.jpg', '2.jpg', '3.jpg', 'y.jpg']);
    expect(await File('$a/1.jpg').length(), 1024 + jpeg.length);
  });

  test('a copy goes file by file with progress, verified, with the bytes '
      'and time of its original, and is undone', () async {
    await file('$a/1.jpg', 3000);
    await file('$a/2.jpg');
    await file('$b/2.jpg', 2);
    final copy = Transfer(['$a/1.jpg', '$a/2.jpg'], b, move: false);
    final seen = <double>[];
    copy.addListener(() => seen.add(copy.files.first.done));
    await copy.run();
    expect([for (final f in copy.files) f.error], [null, 'exists']);
    expect(seen, contains(greaterThan(0.0)));
    expect(seen.where((d) => d > 0 && d < 1), isNotEmpty, reason: 'per file');
    expect(
      await File('$b/1.jpg').readAsBytes(),
      await File('$a/1.jpg').readAsBytes(),
    );
    expect((await File('$b/1.jpg').lastModified()).toUtc(), mtime);
    expect(await File('$b/2.jpg').length(), 2048 + jpeg.length);
    expect(await names(a), ['1.jpg', '2.jpg']);
    await copy.undo();
    expect(await names(b), ['2.jpg']);
    expect(await names(a), ['1.jpg', '2.jpg']);
  });

  test('a move leaves nothing behind and is undone', () async {
    await file('$a/1.jpg');
    final move = Transfer(['$a/1.jpg'], b, move: true);
    await move.run();
    expect(await names(a), isEmpty);
    expect(await names(b), ['1.jpg']);
    expect((await File('$b/1.jpg').lastModified()).toUtc(), mtime);
    await move.undo();
    expect(await names(a), ['1.jpg']);
    expect(await names(b), isEmpty);
  });

  test('an undo leaves a file whose old place was taken since where it is, '
      'and undoes the rest', () async {
    await file('$a/1.jpg');
    await file('$a/2.jpg');
    final move = Transfer(['$a/1.jpg', '$a/2.jpg'], b, move: true);
    await move.run();
    await file('$a/1.jpg', 2);
    await move.undo();
    expect(await names(a), ['1.jpg', '2.jpg']);
    expect(await names(b), ['1.jpg']);
    expect(await File('$a/1.jpg').length(), 2048 + jpeg.length);
    expect([for (final f in move.files) f.target], ['$b/1.jpg', null]);
  });

  test(
    'a cancelled copy stops within its file and leaves no partial file',
    () async {
      await file('$a/big.jpg', 64 << 10);
      await file('$a/next.jpg');
      final copy = Transfer(['$a/big.jpg', '$a/next.jpg'], b, move: false);
      copy.addListener(() {
        if (copy.files.first.done > 0) copy.cancel();
      });
      await copy.run();
      expect([for (final f in copy.files) f.error], ['cancelled', 'cancelled']);
      expect(await names(a), ['big.jpg', 'next.jpg']);
      // Ten seconds of its own waits, which a stopped process does not run out.
      for (var i = 0; i < 500 && (await names(b)).isNotEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(await names(b), isEmpty);
    },
  );

  test('a folder is made under any folder, never over one', () async {
    expect(await createFolder(a, 'new'), isNull);
    expect(await Directory('$a/new').exists(), isTrue);
    expect(await createFolder(a, 'new'), 'exists');
    expect(await createFolder(a, 'x/y'), 'invalid');
  });
}
