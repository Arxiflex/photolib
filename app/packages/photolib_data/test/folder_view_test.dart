@TestOn('vm')
library;

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:photolib_data/photolib_data.dart';
import 'package:test/test.dart';

Uint8List _id(int n) => Uint8List(16)..[15] = n;

void main() {
  late Replica db;
  setUp(() => db = Replica(NativeDatabase.memory()));
  tearDown(() => db.close());

  var next = 0;
  Future<void> item(
    String source,
    String volume,
    String path, {
    int mtime = 0,
    bool favorite = false,
    bool trashed = false,
    String state = 'present',
    int folder = 0,
    int hidden = 0,
    int archived = 0,
  }) => db
      .into(db.localAsset)
      .insert(
        LocalAssetCompanion.insert(
          id: _id(++next),
          source: source,
          volume: Value(volume),
          sourceId: '$next',
          size: 1,
          mtime: mtime,
          path: Value(source == 'folder' ? path : path.split('|').first),
          name: Value(source == 'folder' ? null : path.split('|').last),
          favorite: Value(favorite ? 1 : 0),
          trashed: Value(trashed ? 1 : 0),
          state: Value(state),
          folder: Value(folder),
          hidden: Value(hidden),
          archived: Value(archived),
        ),
      );

  // A device folder the user keeps out of the library (ADR-0210).
  Future<void> excluded(int id, String path) => db
      .into(db.deviceFolder)
      .insert(
        DeviceFolderCompanion.insert(
          id: Value(id),
          volume: 'external_primary',
          path: path,
          visibility: const Value('hidden'),
        ),
      );

  test(
    'device folders hold their own present items, apart per volume, '
    'each with its newest as cover and whether the user keeps it out',
    () async {
      await item('mediastore', 'external_primary', 'DCIM/Camera/|a.jpg');
      await item(
        'mediastore',
        'external_primary',
        'DCIM/Camera/|b.jpg',
        mtime: 9,
      );
      await item('mediastore', '1234-abcd', 'DCIM/Camera/|c.jpg', mtime: 5);
      await item(
        'mediastore',
        '1234-abcd',
        'DCIM/Camera/|d.jpg',
        trashed: true,
      );
      await item('folder', '/home/me/Pictures', 'x.jpg');
      await item('folder', '/home/me/Pictures', 'Trips/2024/y.jpg', mtime: 3);
      await item('folder', '/home/me/Pictures', 'Trips/2024/z.jpg', mtime: 4);
      await item(
        'folder',
        '/home/me/Pictures',
        'Trips/w.jpg',
        state: 'missing',
      );
      await excluded(7, 'Music/');
      await item('mediastore', 'external_primary', 'Music/|e.jpg', folder: 7);
      final folders = await folderEntries(db).first;
      expect(
        [
          for (final f in folders)
            (
              f.folder.source,
              f.folder.volume,
              f.folder.dir,
              f.items,
              f.excluded,
            ),
        ],
        unorderedEquals([
          ('mediastore', 'external_primary', 'DCIM/Camera/', 2, false),
          ('mediastore', '1234-abcd', 'DCIM/Camera/', 1, false),
          ('mediastore', 'external_primary', 'Music/', 1, true),
          ('folder', '/home/me/Pictures', '', 1, false),
          ('folder', '/home/me/Pictures', 'Trips/2024/', 2, false),
        ]),
      );
      expect(
        {
          for (final f in folders)
            f.folder.dir + f.folder.volume: f.cover.mtime,
        },
        {
          'DCIM/Camera/external_primary': 9,
          'DCIM/Camera/1234-abcd': 5,
          'Music/external_primary': 0,
          '/home/me/Pictures': 0,
          'Trips/2024//home/me/Pictures': 4,
        },
      );
    },
  );

  test(
    'a folder lists its own present items, none of its subfolders',
    () async {
      await item('folder', '/p', 'a/1.jpg');
      await item('folder', '/p', 'a/b/2.jpg');
      await item('folder', '/p', '3.jpg');
      await item('folder', '/p', 'a/4.jpg', trashed: true);
      await item('mediastore', 'external_primary', 'a/|5.jpg');
      Future<List<String>> paths(
        String source,
        String volume,
        String dir,
      ) async => [
        for (final a in await folderContents(db, (
          source: source,
          volume: volume,
          dir: dir,
        )).first)
          a.name ?? a.path!,
      ];
      expect(await paths('folder', '/p', 'a/'), ['a/1.jpg']);
      expect(await paths('folder', '/p', ''), ['3.jpg']);
      expect(await paths('mediastore', 'external_primary', 'a/'), ['5.jpg']);
    },
  );

  test('favourites are the present favourite items of folders the library '
      'shows', () async {
    await excluded(7, 'Music/');
    await item(
      'mediastore',
      'external_primary',
      'Music/|4.jpg',
      folder: 7,
      favorite: true,
    );
    await item('folder', '/p', '1.jpg', favorite: true);
    await item('folder', '/p', '2.jpg');
    await item('folder', '/p', '3.jpg', favorite: true, trashed: true);
    expect([for (final a in await favouriteItems(db).first) a.path], ['1.jpg']);
  });

  test('hidden items stay out of folders, their counts and covers, and the '
      'favourites until they show; archived ones stay in', () async {
    await item('folder', '/p', 'a/1.jpg', favorite: true);
    await item('folder', '/p', 'a/2.jpg', mtime: 9, favorite: true, hidden: 1);
    await item('folder', '/p', 'a/3.jpg', mtime: 5, archived: 1);
    await item('folder', '/p', 'b/4.jpg', hidden: 1);
    for (final veiled in [false, true]) {
      expect(
        [
          for (final f in await folderEntries(db, veiled: veiled).first)
            (f.folder.dir, f.items, f.cover.path),
        ],
        unorderedEquals([
          ('a/', veiled ? 3 : 2, veiled ? 'a/2.jpg' : 'a/3.jpg'),
          if (veiled) ('b/', 1, 'b/4.jpg'),
        ]),
        reason: 'veiled: $veiled',
      );
      expect([
        for (final a in await folderContents(db, (
          source: 'folder',
          volume: '/p',
          dir: 'a/',
        ), veiled: veiled).first)
          a.path,
      ], unorderedEquals(['a/1.jpg', if (veiled) 'a/2.jpg', 'a/3.jpg']));
      expect([
        for (final a in await favouriteItems(db, veiled: veiled).first) a.path,
      ], unorderedEquals(['a/1.jpg', if (veiled) 'a/2.jpg']));
    }
  });
}
