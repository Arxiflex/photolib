@TestOn('vm')
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:photolib_data/photolib_data.dart';
import 'package:photolib_data/src/trash_native.dart';
import 'package:test/test.dart';

void main() {
  late Directory tmp;
  late String home;
  late String data;
  late String drive;
  var next = 0;
  setUp(() {
    tmp = Directory.systemTemp.createTempSync('trash');
    home = '${tmp.path}/home';
    data = '$home/.local/share';
    drive = '${tmp.path}/media/card';
    Directory('$home/Pictures/My Trip').createSync(recursive: true);
    Directory('$drive/DCIM').createSync(recursive: true);
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  // A home on one file system and a card mounted beside it.
  FreedesktopTrash trash() => FreedesktopTrash(
    dataHome: data,
    mountInfo:
        '22 1 8:1 / / rw - ext4 /dev/sda1 rw\n'
        '40 22 8:2 / ${tmp.path}/home rw - ext4 /dev/sda2 rw\n'
        '41 22 179:1 / ${tmp.path}/media/card rw - vfat /dev/mmcblk0p1 rw',
    uid: 1000,
    now: () => DateTime(2024, 5, 2, 22, 0, 5),
  );

  LocalAssetData item(String root, String path, {String? bin}) {
    final file = File('$root/$path');
    if (bin == null && !file.existsSync()) file.writeAsStringSync(path);
    return LocalAssetData(
      id: Uint8List(16)..[15] = ++next,
      source: 'folder',
      volume: root,
      sourceId: '$next',
      path: path,
      size: 1,
      mtime: 0,
      state: 'present',
      favorite: 0,
      trashed: bin == null ? 0 : 1,
      edited: 0,
      folder: 0,
      hidden: 0,
      archived: 0,
      bin: bin,
      tile: 0,
    );
  }

  LocalAssetData binned(LocalAssetData row, Binned to) =>
      row.copyWith(trashed: 1, bin: Value(to.bin));

  test('a file goes to the home trash, as file managers list it, with where '
      'it was and when', () async {
    final a = item('$home/Pictures', 'My Trip/a #1.jpg');
    final [to] = await trash().trash([a]);
    expect(to.bin, '$data/Trash/files/a #1.jpg');
    expect(to.expires, isNull);
    expect(File('$home/Pictures/My Trip/a #1.jpg').existsSync(), isFalse);
    expect(File(to.bin!).readAsStringSync(), 'My Trip/a #1.jpg');
    expect(
      File('$data/Trash/info/a #1.jpg.trashinfo').readAsStringSync(),
      '[Trash Info]\n'
      'Path=${Uri.file('$home/Pictures/My Trip/a #1.jpg').path}\n'
      'DeletionDate=2024-05-02T22:00:05\n',
    );
    expect(
      File('$data/Trash/info/a #1.jpg.trashinfo').readAsStringSync(),
      contains('My%20Trip/a%20%231.jpg'),
    );
  });

  test('a name the trash holds already is numbered', () async {
    final a = item('$home/Pictures', 'a.jpg');
    final b = item('$home/Pictures', 'My Trip/a.jpg');
    final bins = await trash().trash([a, b]);
    expect(
      [for (final b in bins) b.bin],
      ['$data/Trash/files/a.jpg', '$data/Trash/files/a.2.jpg'],
    );
    expect(File('$data/Trash/info/a.2.jpg.trashinfo').existsSync(), isTrue);
  });

  test("a file on another drive goes to that drive's trash, its path "
      'relative to it', () async {
    final c = item(drive, 'DCIM/c.jpg');
    final [to] = await trash().trash([c]);
    expect(to.bin, '$drive/.Trash-1000/files/c.jpg');
    expect(
      File('$drive/.Trash-1000/info/c.jpg.trashinfo').readAsStringSync(),
      contains('\nPath=DCIM/c.jpg\n'),
    );
  });

  test('restores a file where it was, into its folder made again', () async {
    final a = item('$home/Pictures', 'My Trip/a.jpg');
    final t = trash();
    final [to] = await t.trash([a]);
    Directory('$home/Pictures/My Trip').deleteSync();
    await t.restore([binned(a, to)]);
    expect(
      File('$home/Pictures/My Trip/a.jpg').readAsStringSync(),
      'My Trip/a.jpg',
    );
    expect(Directory('$data/Trash/files').listSync(), isEmpty);
    expect(Directory('$data/Trash/info').listSync(), isEmpty);
  });

  test('a file in the way keeps the trashed one in the trash', () async {
    final a = item('$home/Pictures', 'a.jpg');
    final t = trash();
    final [to] = await t.trash([a]);
    File('$home/Pictures/a.jpg').writeAsStringSync('new');
    await expectLater(
      t.restore([binned(a, to)]),
      throwsA(isA<FileSystemException>()),
    );
    expect(File(to.bin!).existsSync(), isTrue);
    expect(File('$home/Pictures/a.jpg').readAsStringSync(), 'new');
  });

  test('a batch that fails part way puts back what it moved', () async {
    final a = item('$home/Pictures', 'a.jpg');
    final gone = item('$home/Pictures', 'gone.jpg');
    File('$home/Pictures/gone.jpg').deleteSync();
    await expectLater(
      trash().trash([a, gone]),
      throwsA(isA<FileSystemException>()),
    );
    expect(File('$home/Pictures/a.jpg').existsSync(), isTrue);
    expect(Directory('$data/Trash/files').listSync(), isEmpty);
    expect(Directory('$data/Trash/info').listSync(), isEmpty);
  });

  test('purges a file and its info; one emptied already is no error', () async {
    final a = item('$home/Pictures', 'a.jpg');
    final b = item('$home/Pictures', 'b.jpg');
    final t = trash();
    final bins = await t.trash([a, b]);
    File(bins[1].bin!).deleteSync();
    await t.purge([binned(a, bins[0]), binned(b, bins[1])]);
    expect(Directory('$data/Trash/files').listSync(), isEmpty);
    expect(Directory('$data/Trash/info').listSync(), isEmpty);
  });

  test('a file Photolib trashed stays in its trash while gone, and leaves '
      'it when a file manager restores it', () async {
    final root = '$home/Pictures';
    for (final name in ['a.jpg', 'b.jpg']) {
      File('$root/$name').writeAsStringSync(name);
    }
    final db = Replica(NativeDatabase.memory());
    addTearDown(db.close);
    final indexer = FolderIndexer(db);
    await addFolder(db, root);
    await indexer.scan(root);
    Future<LocalAssetData> a() => (db.select(
      db.localAsset,
    )..where((a) => a.path.equals('a.jpg'))).getSingle();
    await DeletionService(db, (_) => trash()).trash([(await a()).id]);
    await indexer.scan(root);
    final trashed = await a();
    expect((trashed.state, trashed.trashed), ('missing', 1));
    expect(await db.trashItems(false).get(), hasLength(1));

    File(trashed.bin ?? '').renameSync('$root/a.jpg');
    await indexer.scan(root);
    final back = await a();
    expect(
      (back.state, back.trashed, back.bin, back.expires),
      ('present', 0, null, null),
    );
  });

  test(
    "Photolib's own bin leaves a file in place until it is purged",
    () async {
      final a = item('$home/Pictures', 'a.jpg');
      const bin = appBin;
      final [to] = await bin.trash([a]);
      expect(to, (bin: null, expires: null));
      await bin.restore([binned(a, to)]);
      expect(File('$home/Pictures/a.jpg').existsSync(), isTrue);
      await bin.purge([binned(a, to)]);
      expect(File('$home/Pictures/a.jpg').existsSync(), isFalse);
      await bin.purge([binned(a, to)]);
    },
  );

  group("Windows' Recycle Bin", () {
    late String bin;
    setUp(() => bin = '${tmp.path}/\$Recycle.Bin');

    // What the shell does: the file goes to `$R<id>` in the user's folder of
    // the drive's bin, beside an `$I<id>` record of where it was.
    Future<void> recycle(String path) async {
      final user = Directory('$bin/S-1-5-21-1')..createSync(recursive: true);
      final id = 'A${user.listSync().length}.jpg';
      final units = [...path.codeUnits, 0];
      final record = ByteData(28 + 2 * units.length)
        ..setInt64(0, 2, Endian.little)
        ..setInt64(8, 1, Endian.little)
        ..setInt64(16, 133000000000000000 + next, Endian.little)
        ..setInt32(24, units.length, Endian.little);
      for (final (i, unit) in units.indexed) {
        record.setUint16(28 + 2 * i, unit, Endian.little);
      }
      File('${user.path}/\$I$id').writeAsBytesSync(record.buffer.asUint8List());
      File(path).renameSync('${user.path}/\$R$id');
    }

    RecycleBin recycleBin() => RecycleBin(
      recycle: recycle,
      binOf: (path) => path.startsWith(drive) ? null : bin,
    );

    test('a file goes to the Recycle Bin, found by its record, and comes back '
        'from it', () async {
      // Another user's folder, which this one may not list.
      Directory('$bin/S-1-5-18').createSync(recursive: true);
      final a = item('$home/Pictures', 'My Trip/a.jpg');
      final b = item('$home/Pictures', 'b.jpg');
      final t = recycleBin();
      final bins = await t.trash([a, b]);
      expect(
        [for (final b in bins) b.bin],
        ['$bin/S-1-5-21-1/\$RA0.jpg', '$bin/S-1-5-21-1/\$RA2.jpg'],
      );
      expect(File('$home/Pictures/My Trip/a.jpg').existsSync(), isFalse);
      await t.restore([binned(a, bins[0])]);
      expect(
        File('$home/Pictures/My Trip/a.jpg').readAsStringSync(),
        'My Trip/a.jpg',
      );
      expect(File('$bin/S-1-5-21-1/\$IA0.jpg').existsSync(), isFalse);
      await t.purge([binned(b, bins[1])]);
      expect(Directory('$bin/S-1-5-21-1').listSync(), isEmpty);
    });

    test(
      "a drive without a Recycle Bin keeps the file in Photolib's own bin",
      () async {
        final c = item(drive, 'DCIM/c.jpg');
        final t = recycleBin();
        final [to] = await t.trash([c]);
        expect(to, (bin: null, expires: null));
        expect(File('$drive/DCIM/c.jpg').existsSync(), isTrue);
        await t.purge([binned(c, to)]);
        expect(File('$drive/DCIM/c.jpg').existsSync(), isFalse);
      },
    );

    test(
      "a record names where its file was, in either of Windows' layouts",
      () {
        Uint8List v1(String path) {
          final record = ByteData(24 + 520)..setInt64(0, 1, Endian.little);
          for (final (i, unit) in path.codeUnits.indexed) {
            record.setUint16(24 + 2 * i, unit, Endian.little);
          }
          return record.buffer.asUint8List();
        }

        expect(recycledFrom(v1(r'C:\Photos\a.jpg')), r'C:\Photos\a.jpg');
        expect(recycledFrom(Uint8List(10)), isNull);
      },
    );
  });
}
