@TestOn('vm')
library;

import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:photolib_data/photolib_data.dart';
import 'package:photolib_data/testing.dart';
import 'package:test/test.dart';

import 'kernel.dart';

void main() {
  final kernel = testKernel();
  late Replica db;
  late FakeMediaStore store;
  late MediaStoreIndexer indexer;
  setUp(() {
    db = Replica(NativeDatabase.memory());
    store = FakeMediaStore();
    indexer = MediaStoreIndexer(db, store, page: 2);
  });
  tearDown(() => db.close());

  Future<List<String>> index() async => [
    for (final a
        in await (db.select(db.localAsset)..orderBy([
              (a) => OrderingTerm.asc(a.volume),
              (a) => OrderingTerm.asc(a.sourceId),
            ]))
            .get())
      '${a.volume}/${a.sourceId} ${a.path}${a.name}'
          '${a.state == 'offline' ? ' offline' : ''}',
  ];

  Future<Map<String, Uint8List>> uuids() async => {
    for (final a in await db.select(db.localAsset).get())
      '${a.volume}/${a.sourceId}': a.id,
  };

  Future<void> hash(String name) =>
      (db.update(db.localAsset)..where((a) => a.name.equals(name))).write(
        LocalAssetCompanion(contentHash: Value(Uint8List(32))),
      );
  Future<List<String?>> hashed() async => [
    for (final a in await (db.select(
      db.localAsset,
    )..where((a) => a.contentHash.isNotNull())).get())
      a.name,
  ];

  test('a full index writes every item of every volume', () async {
    final primary = store.mounted['external_primary'] = FakeVolume();
    final card = store.mounted['0000-0000'] = FakeVolume();
    primary
      ..add('a.jpg')
      ..add('b.mp4')
      ..add('c.jpg', path: 'Pictures/Screenshots/');
    card.add('d.jpg');

    await indexer.sync();

    expect(await index(), [
      '0000-0000/1 DCIM/Camera/d.jpg',
      'external_primary/1 DCIM/Camera/a.jpg',
      'external_primary/2 DCIM/Camera/b.mp4',
      'external_primary/3 Pictures/Screenshots/c.jpg',
    ]);
    final b = await (db.select(
      db.localAsset,
    )..where((a) => a.name.equals('b.mp4'))).getSingle();
    expect(
      [b.source, b.generation, b.size, b.mtime, b.mime, b.bucketName, b.taken],
      [
        'mediastore',
        '2',
        1005,
        1700000000000,
        'video/mp4',
        'Camera',
        1600000000000,
      ],
    );
    expect(b.id, hasLength(16));
    expect(b.added, uuidTime(b.id));
    expect(b.added, closeTo(DateTime.now().millisecondsSinceEpoch, 60000));
    expect(
      {
        for (final c in await db.select(db.volumeCursor).get())
          c.volume: c.root,
      },
      {
        '0000-0000': '/storage/0000-0000',
        'external_primary': '/storage/external_primary',
      },
    );
  });

  test('a delta reads only what changed since the stored generation', () async {
    final v = store.mounted['external_primary'] = FakeVolume();
    v
      ..add('a.jpg')
      ..add('b.jpg')
      ..add('c.jpg');
    await indexer.sync();
    await hash('a.jpg');
    await hash('b.jpg');
    final before = await uuids();
    store.queries.clear();

    v
      ..add('d.jpg')
      ..change(1)
      ..change(2, trashed: true, size: 5);
    await indexer.sync();

    expect(store.queries, [
      'items external_primary since 3 after 0',
      'items external_primary since 3 after 2',
    ]);
    final rows = await (db.select(
      db.localAsset,
    )..orderBy([(a) => OrderingTerm.asc(a.sourceId)])).get();
    expect(
      [
        for (final a in rows)
          '${a.name} ${a.favorite} ${a.trashed} ${a.expires} ${a.size}',
      ],
      [
        'a.jpg 1 0 null 1005',
        'b.jpg 1 1 1800000000000 5',
        'c.jpg 0 0 null 1005',
        'd.jpg 0 0 null 1005',
      ],
    );
    expect(await hashed(), ['a.jpg'], reason: 'only b.jpg changed bytes');
    expect(await uuids(), {...before, 'external_primary/4': anything});
    await indexer.sync();
    expect(store.queries, hasLength(2), reason: 'nothing changed');
  });

  test(
    'a changed file is extracted again; what MediaStore lacks survives its other changes',
    () async {
      final v = store.mounted['external_primary'] = FakeVolume()
        ..add('a.jpg')
        ..add('b.jpg');
      await indexer.sync();
      await db
          .update(db.localAsset)
          .write(
            LocalAssetCompanion(
              extracted: const Value(1),
              width: const Value(640),
              fingerprint: Value(Uint8List(32)),
            ),
          );

      v
        ..change(1)
        ..change(2, size: 5);
      await indexer.sync();

      final rows = await (db.select(
        db.localAsset,
      )..orderBy([(a) => OrderingTerm.asc(a.sourceId)])).get();
      expect(
        [
          for (final a in rows)
            (a.name, a.favorite, a.extracted, a.width, a.fingerprint?.length),
        ],
        [('a.jpg', 1, 1, 640, 32), ('b.jpg', 1, null, null, null)],
      );
    },
  );

  test(
    'a favourite of the index stays one when MediaStore has none, as for '
    'an item found again by its content; one MediaStore gains joins it',
    () async {
      final v = store.mounted['external_primary'] = FakeVolume()
        ..add('a.jpg')
        ..add('b.jpg');
      await indexer.sync();
      await (db.update(db.localAsset)..where((a) => a.name.equals('a.jpg')))
          .write(const LocalAssetCompanion(favorite: Value(1)));
      v
        ..change(1, favorite: false)
        ..change(2, favorite: true);
      await indexer.sync();
      expect(
        [
          for (final a in await (db.select(
            db.localAsset,
          )..orderBy([(a) => OrderingTerm.asc(a.sourceId)])).get())
            a.favorite,
        ],
        [1, 1],
      );
    },
  );

  test(
    'deletions, which bump no generation, are found by comparing counts',
    () async {
      final v = store.mounted['external_primary'] = FakeVolume();
      for (final name in ['a.jpg', 'b.jpg', 'c.jpg', 'd.jpg']) {
        v.add(name);
      }
      await indexer.sync();
      await db
          .into(db.backupState)
          .insert(
            BackupStateCompanion.insert(
              localAssetId: (await uuids())['external_primary/2']!,
              state: 'selected',
              updatedAt: 1,
            ),
          );
      store.queries.clear();

      v.items
        ..remove(2)
        ..remove(3);
      await indexer.sync();

      expect(store.queries, ['ids external_primary']);
      expect(await index(), [
        'external_primary/1 DCIM/Camera/a.jpg',
        'external_primary/4 DCIM/Camera/d.jpg',
      ]);
      expect(await db.select(db.backupState).get(), isEmpty);
    },
  );

  group('a card', () {
    late FakeVolume card;
    late Map<String, Uint8List> before;
    setUp(() async {
      store.mounted['external_primary'] = FakeVolume()..add('a.jpg');
      card = store.mounted['0000-0000'] = FakeVolume()
        ..add('c1.jpg')
        ..add('c2.jpg');
      await indexer.sync();
      await hash('c1.jpg');
      before = await uuids();

      store.mounted.remove('0000-0000');
      await indexer.sync();
    });

    test('that is removed leaves its items offline', () async {
      expect(await index(), [
        '0000-0000/1 DCIM/Camera/c1.jpg offline',
        '0000-0000/2 DCIM/Camera/c2.jpg offline',
        'external_primary/1 DCIM/Camera/a.jpg',
      ]);
    });

    test('that returns brings its items back, not copies of them', () async {
      card.add('c3.jpg');
      store.mounted['0000-0000'] = card;
      await indexer.sync();

      expect(await index(), [
        '0000-0000/1 DCIM/Camera/c1.jpg',
        '0000-0000/2 DCIM/Camera/c2.jpg',
        '0000-0000/3 DCIM/Camera/c3.jpg',
        'external_primary/1 DCIM/Camera/a.jpg',
      ]);
      expect(await uuids(), {...before, '0000-0000/3': anything});
      expect(await hashed(), ['c1.jpg']);
    });

    test(
      'whose items MediaStore indexed again under new ids keeps them',
      () async {
        // MediaStore dropped the card's rows, then scanned it again; c1.jpg went.
        card.items.clear();
        card
          ..add('c2.jpg')
          ..add('c1.jpg', path: 'DCIM/Moved/')
          ..add('c3.jpg');
        store.mounted['0000-0000'] = card;
        await indexer.sync();

        expect(await index(), [
          '0000-0000/3 DCIM/Camera/c2.jpg',
          '0000-0000/4 DCIM/Moved/c1.jpg',
          '0000-0000/5 DCIM/Camera/c3.jpg',
          'external_primary/1 DCIM/Camera/a.jpg',
        ]);
        final after = await uuids();
        expect(after['0000-0000/3'], before['0000-0000/2']);
        expect(after.values, isNot(contains(before['0000-0000/1'])));
        expect(after, hasLength(4));
      },
    );
  });

  test(
    'a new MediaStore version re-identifies every item by its file',
    () async {
      store.mounted['external_primary'] = FakeVolume()
        ..add('a.jpg')
        ..add('b.jpg')
        ..add('c.jpg');
      await indexer.sync();
      await hash('b.jpg');
      final before = await uuids();

      // A rebuilt database numbers ids and generations from the start again.
      store.mounted['external_primary'] = FakeVolume('v2')
        ..add('b.jpg')
        ..add('a.jpg')
        ..add('d.jpg');
      await indexer.sync();

      expect(await index(), [
        'external_primary/1 DCIM/Camera/b.jpg',
        'external_primary/2 DCIM/Camera/a.jpg',
        'external_primary/3 DCIM/Camera/d.jpg',
      ]);
      final after = await uuids();
      expect(
        [after['external_primary/1'], after['external_primary/2']],
        [before['external_primary/2'], before['external_primary/1']],
      );
      expect(await hashed(), ['b.jpg']);
    },
  );

  test('a generation that went back rescans the volume', () async {
    store.mounted['external_primary'] = FakeVolume()
      ..add('a.jpg')
      ..add('b.jpg');
    await indexer.sync();
    store.queries.clear();

    store.mounted['external_primary'] = FakeVolume()..add('a.jpg');
    await indexer.sync();

    expect(store.queries.first, 'items external_primary since 0 after 0');
    expect(await index(), ['external_primary/1 DCIM/Camera/a.jpg']);
  });

  test(
    'app data restored onto another phone makes no false duplicates',
    () async {
      store.mounted['external_primary'] = FakeVolume()
        ..add('a.jpg')
        ..add('b.jpg');
      await indexer.sync();
      await hash('a.jpg');
      await (db.update(
        db.localAsset,
      )).write(LocalAssetCompanion(assetId: Value(Uint8List(16))));
      await db
          .into(db.backupState)
          .insert(
            BackupStateCompanion.insert(
              localAssetId: (await uuids())['external_primary/1']!,
              state: 'backed_up',
              updatedAt: 1,
            ),
          );

      // The new phone's ids and generations name other files.
      store
        ..install = 'install-2'
        ..mounted['external_primary'] = (FakeVolume()
          ..add('x.jpg')
          ..add('a.jpg')
          ..add('y.jpg'));
      await indexer.sync();

      expect(await index(), [
        'external_primary/1 DCIM/Camera/x.jpg',
        'external_primary/2 DCIM/Camera/a.jpg',
        'external_primary/3 DCIM/Camera/y.jpg',
      ]);
      expect(await hashed(), isEmpty);
      expect(
        await (db.select(
          db.localAsset,
        )..where((a) => a.assetId.isNotNull())).get(),
        isEmpty,
      );
      expect(await db.select(db.backupState).get(), isEmpty);
    },
  );

  test('without access the index is left as it is', () async {
    final v = store.mounted['external_primary'] = FakeVolume()..add('a.jpg');
    await indexer.sync();
    store
      ..granted = MediaAccess.none
      ..queries.clear();
    v.items.clear();

    await indexer.sync();

    expect(store.queries, isEmpty);
    expect(await index(), ['external_primary/1 DCIM/Camera/a.jpg']);
  });

  test('with partial access every sync reads the whole selection', () async {
    store.granted = MediaAccess.partial;
    final v = store.mounted['external_primary'] = FakeVolume()
      ..add('a.jpg')
      ..add('b.jpg');
    final b = v.items.remove(2)!;
    await indexer.sync();

    // The user selects an older photo: no generation changes.
    v.items[2] = b;
    await indexer.sync();

    expect(await index(), [
      'external_primary/1 DCIM/Camera/a.jpg',
      'external_primary/2 DCIM/Camera/b.jpg',
    ]);
  });

  test(
    'buckets are the device albums, the latest first, without trashed or offline items',
    () async {
      store.mounted['external_primary'] = FakeVolume()
        ..add('a.jpg')
        ..add('s.png', path: 'Pictures/Screenshots/', taken: 1700000000000)
        ..add('b.jpg', taken: 1800000000000)
        ..change(3, trashed: true);
      store.mounted['0000-0000'] = FakeVolume()
        ..add('c.jpg', path: 'DCIM/Card/');
      await indexer.sync();
      store.mounted.remove('0000-0000');
      await indexer.sync();

      expect(
        [
          for (final b in await db.deviceBuckets().get())
            '${b.bucketName} ${b.items}',
        ],
        ['Screenshots 1', 'Camera 1'],
      );
    },
  );

  test(
    'a cold index of 100,000 items takes under 60 s and a small change under 1 s',
    () async {
      final dir = await Directory.systemTemp.createTemp('photolib-index-');
      addTearDown(() => dir.delete(recursive: true));
      final vault = Vault(
        location: '${dir.path}/store',
        keystore: MemoryKeystore(),
        files: storeFiles('${dir.path}/store'),
        keyring: kernel.keyring,
      );
      await vault.unlock();
      addTearDown(vault.lock);
      final replica = await vault.openReplica();
      final v = store.mounted['external_primary'] = FakeVolume();
      for (var i = 0; i < 100000; i++) {
        v.add('IMG_$i.jpg', path: 'DCIM/${i % 50}/');
      }
      final indexer = MediaStoreIndexer(replica, store);

      final cold = Stopwatch()..start();
      await indexer.sync();
      cold.stop();
      for (var i = 0; i < 5; i++) {
        v
          ..add('new_$i.jpg')
          ..change(1000 * i + 1)
          ..items.remove(1000 * i + 2);
      }
      final delta = Stopwatch()..start();
      await indexer.sync();
      delta.stop();

      print(
        'cold index of 100,000 items: ${cold.elapsedMilliseconds} ms, '
        'delta of 15 changes: ${delta.elapsedMilliseconds} ms',
      );
      final count = countAll();
      final rows = await (replica.selectOnly(
        replica.localAsset,
      )..addColumns([count])).getSingle();
      expect(rows.read(count), 100000);
      expect(cold.elapsed, lessThan(const Duration(seconds: 60)));
      expect(delta.elapsed, lessThan(const Duration(seconds: 1)));
    },
    // Measures the machine: beside the rest of the suite at load 50 the cold
    // index took 79 s.
    tags: 'alone',
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
