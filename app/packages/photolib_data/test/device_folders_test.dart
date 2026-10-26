@TestOn('vm')
library;

import 'dart:io';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:photolib_data/photolib_data.dart';
import 'package:photolib_data/testing.dart';
import 'package:test/test.dart';

void main() {
  late Replica db;
  late FakeMediaStore store;
  late MediaStoreIndexer indexer;
  setUp(() {
    db = Replica(NativeDatabase.memory());
    store = FakeMediaStore();
    indexer = MediaStoreIndexer(db, store, page: 2);
  });
  tearDown(() => db.close());

  const camera = 'DCIM/Camera/';
  const screenshots = 'Pictures/Screenshots/';

  /// Each folder: volume, path, name, items, newest day, in or out of the
  /// library, and whether it is new.
  Future<List<String>> folders() async => [
    for (final f in await db.deviceFolders().get())
      [
        '${f.volume}:${f.path} ${f.name} ${f.items} ${f.newest}',
        if (f.out) 'out' else 'in',
        if (f.fresh == 1) 'new',
      ].join(' '),
  ];

  Future<int> folder(String path, {String volume = 'external_primary'}) async =>
      (await db.deviceFolders().get())
          .singleWhere((f) => f.volume == volume && f.path == path)
          .id;

  /// What the library shows: the timeline's days and items, and what each
  /// other query of device items finds.
  Future<Map<String, Object>> library() async {
    final days = await db.timelineDays(false, null).get();
    final excluded = await excludedFolders(db);
    return {
      'days': [for (final d in days) '${d.day} ${d.count}'],
      'items': [
        for (final i
            in await db.timelinePage(1 << 30, false, null, 100, 0).get())
          [
            '${i.volume}/${i.sourceId}',
            if (excluded.contains(i.folder)) 'excluded',
          ].join(' '),
      ],
      'added': [
        for (final d in await db.timelineAddedDays(0, false, null).get())
          d.count,
      ],
      'search': (await searchPage(db, const LocalQuery(), limit: 1)).count,
    };
  }

  FakeVolume primary() => store.mounted['external_primary'] ??= FakeVolume();

  test('every bucket of every volume is a folder, with its items and its '
      'newest day', () async {
    primary()
      ..add('a.jpg')
      ..add('b.jpg', taken: 1700000000000)
      ..add('c.png', path: screenshots);
    store.mounted['0000-0000'] = FakeVolume()..add('d.jpg');
    await indexer.sync();
    expect(await folders(), [
      '0000-0000:DCIM/Camera/ Camera 1 20200913 in',
      'external_primary:DCIM/Camera/ Camera 2 20231114 in',
      'external_primary:Pictures/Screenshots/ Screenshots 1 20200913 in',
    ]);
  });

  test('excluding a folder takes its items out of every count and page at '
      'once, and showing it again brings them back, reading nothing of '
      'MediaStore', () async {
    primary()
      ..add('a.jpg')
      ..add('b.png', path: screenshots)
      ..add('c.png', path: screenshots, taken: 1700000000000);
    await indexer.sync();
    final all = await library();
    store.queries.clear();

    await showFolder(db, await folder(screenshots), shown: false);
    expect(await library(), {
      'days': ['20200913 1'],
      'items': ['external_primary/1'],
      'added': [1],
      'search': 1,
    });
    expect(await folders(), contains(endsWith('Screenshots 2 20231114 out')));

    await showFolder(db, await folder(screenshots), shown: true);
    expect(await library(), all);
    expect(store.queries, isEmpty);
  });

  test('only the chosen folders: from nothing, then what the user chooses; '
      'switching modes keeps both lists', () async {
    primary()
      ..add('a.jpg')
      ..add('b.png', path: screenshots);
    await indexer.sync();
    await showFolder(db, await folder(screenshots), shown: false);

    await setOnlyChosen(db, on: true);
    expect(await onlyChosen(db), isTrue);
    expect((await library())['items'], isEmpty);
    await showFolder(db, await folder(camera), shown: true);
    expect((await library())['items'], ['external_primary/1']);

    await setOnlyChosen(db, on: false);
    expect((await library())['items'], ['external_primary/1']);
    await showFolder(db, await folder(screenshots), shown: true);
    expect((await library())['items'], hasLength(2));
    await setOnlyChosen(db, on: true);
    expect((await library())['items'], ['external_primary/1']);
  });

  test('a folder that comes after the first index is shown while the library '
      'shows every folder, out of it while only the chosen, and new to the '
      'user until answered', () async {
    primary().add('a.jpg');
    store.mounted['0000-0000'] = FakeVolume()..add('b.jpg');
    await indexer.sync();
    expect(await folders(), everyElement(endsWith(' in')));

    primary().add('c.png', path: screenshots);
    await indexer.sync();
    expect(
      await folders(),
      contains(
        'external_primary:Pictures/Screenshots/ Screenshots 1 '
        '20200913 in new',
      ),
    );
    await setOnlyChosen(db, on: true);
    expect(await folders(), contains(endsWith('20200913 out new')));

    await showFolder(db, await folder(screenshots), shown: true);
    expect(await folders(), contains(endsWith('Screenshots 1 20200913 in')));
    expect((await library())['items'], ['external_primary/2']);
  });

  test('the default junk list starts out of the library and is never new; '
      'screenshots, messaging and download folders start in it', () async {
    for (final path in [
      'Android/data/com.android.chrome/cache/',
      'Android/obb/com.game/',
      'DCIM/.thumbnails/',
      'Android/media/com.whatsapp/WhatsApp/Media/.Statuses/',
      'Music/Artist/Album/',
      'Telegram/Cache/',
    ]) {
      expect(isJunk(path), isTrue, reason: path);
    }
    for (final path in [
      'DCIM/Camera/',
      screenshots,
      'Android/media/com.whatsapp/WhatsApp/Media/WhatsApp Images/',
      'Telegram/Telegram Images/',
      'Download/',
      'Pictures/Musicians/',
      '',
    ]) {
      expect(isJunk(path), isFalse, reason: path);
    }
    primary().add('a.jpg');
    await indexer.sync();
    primary().add('b.jpg', path: 'Android/data/com.app/files/');
    await indexer.sync();
    expect(await folders(), [
      'external_primary:Android/data/com.app/files/ files 1 20200913 out',
      'external_primary:DCIM/Camera/ Camera 1 20200913 in',
    ]);
  });

  test('a removed card leaves its folders listed, not present, with their '
      'settings, which apply again when it comes back', () async {
    primary().add('a.jpg');
    final card = store.mounted['0000-0000'] = FakeVolume()..add('b.jpg');
    await indexer.sync();
    await showFolder(
      db,
      await folder(camera, volume: '0000-0000'),
      shown: false,
    );
    store.mounted.remove('0000-0000');
    await indexer.sync();
    expect(await folders(), [
      '0000-0000:DCIM/Camera/ Camera 0 null out',
      'external_primary:DCIM/Camera/ Camera 1 20200913 in',
    ]);
    store.mounted['0000-0000'] = card..add('c.jpg');
    await indexer.sync();
    expect(await folders(), [
      '0000-0000:DCIM/Camera/ Camera 2 20200913 out',
      'external_primary:DCIM/Camera/ Camera 1 20200913 in',
    ]);
    expect((await library())['items'], ['external_primary/1']);
  });

  test('a new MediaStore version or install keeps the settings, and a folder '
      'whose items went stays until the user forgets it', () async {
    primary()
      ..add('a.jpg')
      ..add('b.png', path: screenshots);
    await indexer.sync();
    await showFolder(db, await folder(screenshots), shown: false);
    store.mounted['external_primary'] = FakeVolume('v2')
      ..add('b.png', path: screenshots)
      ..add('a.jpg');
    await indexer.sync();
    store.install = 'install-2';
    await indexer.sync();
    expect(await folders(), [
      'external_primary:DCIM/Camera/ Camera 1 20200913 in',
      'external_primary:Pictures/Screenshots/ Screenshots 1 20200913 out',
    ]);

    primary().items.removeWhere((_, i) => i.path == screenshots);
    await indexer.sync();
    expect(await folders(), contains(endsWith('Screenshots 0 null out')));
    await forgetFolder(db, await folder(screenshots));
    expect(await folders(), [
      'external_primary:DCIM/Camera/ Camera 1 20200913 in',
    ]);
  });

  test('the settings export and import into a new replica, as a reinstall '
      'restores them, before or after its first index', () async {
    primary()
      ..add('a.jpg')
      ..add('b.png', path: screenshots);
    await indexer.sync();
    await showFolder(db, await folder(screenshots), shown: false);
    await setOnlyChosen(db, on: true);
    await showFolder(db, await folder(camera), shown: true);
    final exported = await exportDeviceFolders(db);

    for (final indexFirst in [false, true]) {
      final fresh = Replica(NativeDatabase.memory());
      addTearDown(fresh.close);
      final reindex = MediaStoreIndexer(fresh, store..install = 'new');
      if (indexFirst) await reindex.sync();
      await importDeviceFolders(fresh, exported);
      await reindex.sync();
      expect(
        [for (final f in await fresh.deviceFolders().get()) (f.path, f.out)],
        [(camera, false), (screenshots, true)],
      );
      expect(await onlyChosen(fresh), isTrue);
      await setOnlyChosen(fresh, on: false);
      expect(
        [for (final f in await fresh.deviceFolders().get()) f.out],
        [false, true],
      );
    }
  });

  test('excluding the folder of an item; while the excluded show, their '
      'items are marked, until the time is up', () async {
    primary()
      ..add('a.jpg')
      ..add('b.png', path: screenshots, taken: 1500000000000);
    await indexer.sync();
    final b = (await db.timelinePage(1 << 30, false, null, 9, 0).get())
        .singleWhere((i) => i.sourceId == '2');
    await excludeFolderOf(db, b.id);
    expect((await library())['items'], ['external_primary/1']);

    await revealExcluded(db, DateTime.now().add(const Duration(minutes: 5)));
    expect((await library())['items'], [
      'external_primary/1',
      'external_primary/2 excluded',
    ]);
    await revealExcluded(
      db,
      DateTime.now().subtract(const Duration(seconds: 1)),
    );
    expect((await library())['items'], ['external_primary/1']);
    await revealExcluded(db, null);
    expect((await library())['items'], ['external_primary/1']);
  });

  test('an excluded folder is still the swipe context of its items, and a '
      'desktop file has none', () async {
    primary()
      ..add('a.jpg')
      ..add('b.png', path: screenshots, taken: 1700000000000)
      ..add('c.png', path: screenshots);
    await indexer.sync();
    await showFolder(db, await folder(screenshots), shown: false);
    final c = await (db.select(
      db.localAsset,
    )..where((a) => a.sourceId.equals('3'))).getSingle();
    expect(
      [for (final i in await folderContextOf(db, c.id)) i.sourceId],
      ['2', '3'],
    );
    await db
        .into(db.localAsset)
        .insert(
          LocalAssetCompanion.insert(
            id: Uint8List(16),
            source: 'folder',
            sourceId: 'x',
            size: 1,
            mtime: 1,
          ),
        );
    expect(await folderContextOf(db, Uint8List(16)), isEmpty);
  });

  test('a .nomedia file neither hides a folder nor is ever written', () async {
    final root = await Directory.systemTemp.createTemp('nomedia');
    addTearDown(() => root.delete(recursive: true));
    store.roots = root.path;
    final nomedia = File('${root.path}/external_primary/$screenshots.nomedia');
    await nomedia.create(recursive: true);
    List<String> files() => [
      for (final e in root.listSync(recursive: true))
        if (e is File) e.path,
    ];
    primary().add('b.png', path: screenshots);
    await indexer.sync();
    expect(await folders(), [endsWith('Screenshots 1 20200913 in')]);
    await showFolder(db, await folder(screenshots), shown: false);
    await showFolder(db, await folder(screenshots), shown: true);
    expect(files(), [nomedia.path]);
  });
}
