@TestOn('vm')
library;

import 'dart:math';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:photolib_data/photolib_data.dart';
import 'package:test/test.dart';

Uint8List _id(int n) => Uint8List(16)..[15] = n;

void main() {
  late Replica db;
  setUp(() => db = Replica(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<void> item(
    int n, {
    String path = 'a/',
    bool trashed = false,
    int hidden = 0,
  }) => db
      .into(db.localAsset)
      .insert(
        LocalAssetCompanion.insert(
          id: _id(n),
          source: 'folder',
          volume: const Value('/p'),
          sourceId: '$n',
          size: n,
          mtime: n,
          path: Value('$path$n.jpg'),
          trashed: Value(trashed ? 1 : 0),
          hidden: Value(hidden),
        ),
      );

  group('keyBetween', () {
    test('orders keys between their neighbours, at the ends and between', () {
      expect(keyBetween(null, null), isNotEmpty);
      final first = keyBetween(null, null);
      final after = keyBetween(first, null);
      final before = keyBetween(null, first);
      final middle = keyBetween(first, after);
      expect([after, middle, before, first]..sort(), [
        before,
        first,
        middle,
        after,
      ]);
    });

    test('never runs out between keys inserted at one place', () {
      final random = Random(7);
      final keys = [keyBetween(null, null)];
      for (var i = 0; i < 2000; i++) {
        final at = random.nextInt(keys.length + 1);
        final key = keyBetween(
          at == 0 ? null : keys[at - 1],
          at == keys.length ? null : keys[at],
        );
        keys.insert(at, key);
      }
      expect([...keys]..sort(), keys);
      expect(keys.toSet(), hasLength(keys.length));
      expect(keys.every((k) => k.length < 40), isTrue);
    });

    test('refuses neighbours out of order', () {
      expect(() => keyBetween('b', 'a'), throwsArgumentError);
      expect(() => keyBetween('a', 'a'), throwsArgumentError);
    });
  });

  test('album folders nest five deep offline, with UUIDv7 ids of their own, '
      'which no server has confirmed', () async {
    Uint8List? parent;
    final folders = <Uint8List>[];
    for (var depth = 0; depth < 5; depth++) {
      parent = await createAlbumFolder(db, 'level $depth', parent: parent);
      folders.add(parent);
    }
    final album = await createAlbum(db, 'Beach', folder: parent);
    for (final id in [...folders, album]) {
      expect(id, hasLength(16));
      expect(id[6] >> 4, 7, reason: 'version 7');
      expect(id[8] >> 6, 2, reason: 'RFC 4122 variant');
    }
    expect(await albumChildren(db, null).first, [
      isA<AlbumEntry>()
          .having((e) => e.name, 'name', 'level 0')
          .having((e) => e.folder, 'folder', isTrue)
          .having((e) => e.items, 'entries', 1),
    ]);
    final deepest = await albumChildren(db, folders.last).first;
    expect(deepest.single.id, album);
    expect(deepest.single.folder, isFalse);
    final path = [for (var depth = 0; depth < 5; depth++) 'level $depth'];
    expect(await albumPath(db, album), path);
    expect(
      [for (final a in await allAlbums(db)) (a.title, a.path.join('/'))],
      [('Beach', path.join('/'))],
    );
    for (final f in await db.select(db.albumFolder).get()) {
      expect(f.txid, isNull);
      expect(f.ownerId, localOwner);
    }
    final row = await db.select(db.album).getSingle();
    expect((row.txid, row.title), (null, 'Beach'));
    expect(row.ownerId, localOwner);
  });

  test('a folder moves anywhere but into itself or below itself', () async {
    final a = await createAlbumFolder(db, 'a');
    final b = await createAlbumFolder(db, 'b', parent: a);
    final album = await createAlbum(db, 'x', folder: b);
    expect(await moveAlbumEntry(db, a, b), isFalse);
    expect(await moveAlbumEntry(db, a, a), isFalse);
    expect(await moveAlbumEntry(db, b, null), isTrue);
    expect(await moveAlbumEntry(db, album, a), isTrue);
    expect(
      [for (final e in await albumChildren(db, null).first) e.name],
      ['a', 'b'],
    );
    expect([for (final e in await albumChildren(db, a).first) e.name], ['x']);
  });

  test('an album holds device items once each, in the order added, '
      'its first present one as cover until one is chosen', () async {
    for (final n in [1, 2, 3]) {
      await item(n);
    }
    await item(4, trashed: true);
    // An item of a folder the library hides (ADR-0210) is held, not shown.
    await db
        .into(db.deviceFolder)
        .insert(
          DeviceFolderCompanion.insert(
            id: const Value(7),
            volume: 'v',
            path: 'p/',
            visibility: const Value('hidden'),
          ),
        );
    await item(5);
    await (db.update(db.localAsset)..where((a) => a.id.equals(_id(5)))).write(
      const LocalAssetCompanion(folder: Value(7)),
    );
    final album = await createAlbum(db, 'Trip');
    await addToAlbum(db, album, [_id(3), _id(1), _id(4)]);
    await addToAlbum(db, album, [_id(1), _id(2), _id(5)]);
    expect(
      [for (final a in await albumItems(db, album).first) a.sourceId],
      ['3', '1', '2'],
    );
    final keys = [
      for (final i in await (db.select(
        db.albumItem,
      )..orderBy([(i) => OrderingTerm(expression: i.sortKey)])).get())
        (i.kind, i.assetId?.last, i.txid),
    ];
    expect(keys, [
      ('asset', 3, null),
      ('asset', 1, null),
      ('asset', 4, null),
      ('asset', 2, null),
      ('asset', 5, null),
    ]);
    var entry = (await albumChildren(db, null).first).single;
    expect((entry.items, entry.cover?.sourceId), (3, '3'));
    await setAlbumCover(db, album, _id(2));
    entry = (await albumChildren(db, null).first).single;
    expect(entry.cover?.sourceId, '2');
  });

  test("an item's albums list, by title, their folders, counts and sharing "
      'as they change, and it leaves one alone', () async {
    for (final n in [1, 2]) {
      await item(n);
    }
    final trips = await createAlbumFolder(db, 'Trips');
    final greece = await createAlbum(db, 'Greece', folder: trips);
    final best = await createAlbum(db, 'Best');
    await addToAlbum(db, greece, [_id(1), _id(2)]);
    await addToAlbum(db, best, [_id(1)]);
    final seen = <List<String>>[];
    final heard = itemAlbums(db, _id(1)).listen(
      (albums) => seen.add([
        for (final a in albums)
          '${a.path.join('/')} ${a.title} ${a.items} ${a.shared}',
      ]),
    );
    await pumpEventQueue();
    await removeFromAlbum(db, best, _id(1));
    await pumpEventQueue();
    await heard.cancel();
    expect(seen.first, [' Best 1 false', 'Trips Greece 2 false']);
    expect(seen.last, ['Trips Greece 2 false']);
    expect(
      [for (final a in await albumItems(db, greece).first) a.sourceId],
      ['1', '2'],
      reason: 'left the other album alone',
    );
  });

  test('an album keeps its sort and layout in its row', () async {
    final album = await createAlbum(db, 'Trip');
    expect(await albumView(db, album), ('custom', 'grid'));
    await setAlbumView(db, album, sort: 'name_desc', layout: 'list');
    expect(await albumView(db, album), ('name_desc', 'list'));
  });

  test('an album counts, covers and lists a hidden item only while hidden '
      'items show, its chosen cover too', () async {
    await item(1, hidden: 1);
    await item(2);
    final album = await createAlbum(db, 'Trip');
    await addToAlbum(db, album, [_id(1), _id(2)]);
    // The album's count and cover, then the ids of its items.
    Future<List<Object?>> seen({required bool veiled}) async {
      final entry = (await albumChildren(
        db,
        null,
        veiled: veiled,
      ).first).single;
      return [
        entry.items,
        entry.cover?.id.last,
        for (final a in await albumItems(db, album, veiled: veiled).first)
          a.sourceId,
      ];
    }

    expect(await seen(veiled: false), [1, 2, '2']);
    expect(await seen(veiled: true), [2, 1, '1', '2']);
    await setAlbumCover(db, album, _id(1));
    expect(await seen(veiled: false), [1, 2, '2']);
    expect(await seen(veiled: true), [2, 1, '1', '2']);
  });

  group('an album of server assets', () {
    Uint8List asset(int n) => Uint8List(16)
      ..[0] = 9
      ..[15] = n;

    Future<void> serverAsset(
      int n, {
      bool trashed = false,
      bool onDevice = false,
      bool locked = false,
    }) async {
      await db
          .into(db.asset)
          .insert(
            AssetCompanion.insert(
              id: asset(n),
              libraryId: Uint8List(16),
              ownerId: Uint8List(16),
              originalFilename: 'server-$n.jpg',
              source: 'upload',
              mediaKind: n == 4 ? 'video' : 'image',
              createdAt: 100 + n,
              fileSizeTotal: Value(1000 * n),
              trashedAt: Value(trashed ? 5 : null),
              onDevice: Value(onDevice ? 1 : 0),
              locked: Value(locked ? 1 : 0),
            ),
          );
    }

    Future<void> inAlbum(Uint8List album, Uint8List id, String key) => db
        .into(db.albumItem)
        .insert(
          AlbumItemCompanion.insert(
            id: Uint8List(16)
              ..[0] = 8
              ..[15] = key.codeUnitAt(0),
            albumId: album,
            kind: 'asset',
            assetId: Value(id),
            sortKey: key,
          ),
        );

    test('lists the assets no device item shows with the device items, in '
        'its order, and counts them', () async {
      await item(1);
      for (final n in [1, 2, 3, 4, 5, 6]) {
        await serverAsset(n, trashed: n == 2, onDevice: n == 3, locked: n == 5);
      }
      final album = await createAlbum(db, 'Trip');
      await addToAlbum(db, album, [_id(1)]);
      await inAlbum(album, asset(1), 'a');
      await inAlbum(album, asset(2), 'b');
      await inAlbum(album, asset(3), 'c');
      await inAlbum(album, asset(4), 'd');
      await inAlbum(album, asset(5), 'e');
      await inAlbum(album, asset(6), 'f');
      // The device item came first by its key; then the server's in theirs.
      final rows = await albumItems(db, album).first;
      expect(
        [for (final r in rows) r.source],
        ['folder', 'server', 'server', 'server'],
      );
      final server = rows.skip(1).toList();
      expect(
        [for (final r in server) r.path],
        ['server-1.jpg', 'server-4.jpg', 'server-6.jpg'],
      );
      expect(server[0].assetId, asset(1));
      expect(server[0].id, asset(1));
      expect([for (final r in server) r.size], [1000, 4000, 6000]);
      expect(
        [for (final r in server) r.mime],
        ['image/*', 'video/*', 'image/*'],
      );
      expect((await albumChildren(db, null).first).single.items, 4);
    });
  });
}
