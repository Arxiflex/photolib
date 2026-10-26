@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:photolib_data/photolib_data.dart';
import 'package:photolib_data/testing.dart' show MemoryKeystore;
import 'package:photolib_workers/testing.dart';
import 'package:test/test.dart';

import 'kernel.dart';

/// A row of PhotoKit's JSON (photo_kit.dart).
List<Object?> _asset(
  String id, {
  String? cloudId,
  bool video = false,
  int modified = 1700000000000,
  int? created,
  int? width,
  int? height,
  int? durationMs,
  double? lat,
  double? lon,
  int subtypes = 0,
  String? burstId,
  bool favorite = false,
  bool edited = false,
}) => [
  id,
  cloudId,
  video,
  modified,
  created,
  width,
  height,
  durationMs,
  lat,
  lon,
  subtypes,
  burstId,
  favorite,
  edited,
];

/// A photo library: every change appends the ids it touched to the persistent history, whose length is the token.
class _Library implements PhotoKit {
  var granted = MediaAccess.full;
  var install = 'install-1';
  final shown = <String, List<Object?>>{};
  final history = <List<String>>[];

  /// Tokens before this one are no longer in the history.
  var kept = 0;
  final calls = <String>[];
  var _snapshot = <List<Object?>>[];

  void add(String id, {int modified = 1700000000000}) =>
      put(_asset(id, modified: modified));

  void put(List<Object?> asset) {
    final id = asset.first! as String;
    history.add([id]);
    shown[id] = asset;
  }

  @override
  Future<MediaAccess> access() async => granted;
  @override
  Future<String> installId() async => install;
  @override
  Future<String> token() async => '${history.length}';
  @override
  Future<List<String>?> changedSince(String token) async {
    calls.add('changes $token');
    final since = int.parse(token);
    return since < kept
        ? null
        : {for (final c in history.skip(since)) ...c}.toList();
  }

  @override
  Future<String> assets(int offset, int limit) async {
    calls.add('assets $offset');
    if (offset == 0) _snapshot = [...shown.values];
    return jsonEncode(_snapshot.skip(offset).take(limit).toList());
  }

  @override
  Future<String> assetsOf(List<String> ids) async {
    calls.add('assetsOf ${ids.join(' ')}');
    return jsonEncode([for (final id in ids) ?shown[id]]);
  }
}

/// A library of [size] assets that makes each page when asked, as the channel does, and then changes 20 favourites.
class _Large implements PhotoKit {
  _Large(this.size, this.install);

  final int size;
  final String install;
  var changed = false;

  /// The channel hands over a page as one string.
  String _page(Iterable<int> assets) {
    final page = StringBuffer('[');
    for (final i in assets) {
      final favourite = changed && i % 997 == 0 && i < 20 * 997;
      page.write(
        '${page.length > 1 ? ',' : ''}["$i/L0/001",null,false,$i,$i,4032,3024,'
        'null,null,null,8,null,$favourite,false]',
      );
    }
    return (page..write(']')).toString();
  }

  @override
  Future<MediaAccess> access() async => MediaAccess.full;
  @override
  Future<String> installId() async => install;
  @override
  Future<String> token() async => changed ? '1' : '0';
  @override
  Future<List<String>?> changedSince(String token) async => [
    for (var i = 0; i < 20; i++) '${i * 997}/L0/001',
  ];
  @override
  Future<String> assets(int offset, int limit) async =>
      _page([for (var i = offset; i < min(offset + limit, size); i++) i]);
  @override
  Future<String> assetsOf(List<String> ids) async =>
      _page([for (final id in ids) int.parse(id.split('/').first)]);
}

/// Indexes [size] assets under a new install on a client of [replica]'s data isolate, as the app does, then 20
/// favourites; returns how long each took.
Future<(Duration, Duration)> _timed(
  Replica replica,
  int size,
  String install,
) => onDataConnection(replica, (db) async {
  final library = _Large(size, install);
  final indexer = PhotoKitIndexer(db, library);
  final cold = Stopwatch()..start();
  await indexer.sync();
  cold.stop();
  library.changed = true;
  final delta = Stopwatch()..start();
  await indexer.sync();
  return (cold.elapsed, delta.elapsed);
});

void main() {
  final kernel = testKernel();
  late Replica db;
  late _Library library;
  late PhotoKitIndexer indexer;
  setUp(() {
    db = Replica(NativeDatabase.memory());
    library = _Library();
    indexer = PhotoKitIndexer(db, library, page: 2);
  });
  tearDown(() => db.close());

  Future<List<String>> index() async => [
    for (final a in await (db.select(
      db.localAsset,
    )..orderBy([(a) => OrderingTerm.asc(a.sourceId)])).get())
      '${a.sourceId} ${a.favorite}',
  ];

  Future<Map<String, Uint8List>> uuids() async => {
    for (final a in await db.select(db.localAsset).get()) a.sourceId: a.id,
  };

  test('a full index writes what PhotoKit says of every asset', () async {
    library
      ..put(
        _asset(
          'A/L0/001',
          cloudId: 'A:001:AV3x',
          created: 1600000000000,
          width: 4032,
          height: 3024,
          lat: 48.8584,
          lon: 2.2945,
          subtypes: 1 << 3 | 1 << 1,
          favorite: true,
          edited: true,
        ),
      )
      ..put(
        _asset(
          'B/L0/001',
          modified: 1700000001000,
          video: true,
          durationMs: 1500,
          subtypes: 1 << 17,
        ),
      )
      // The frame that represents its burst, which the user picked too.
      ..put(
        _asset('C/L0/001', modified: 1, burstId: 'burst-1', subtypes: 3 << 32),
      )
      // An animated GIF, by its playback style.
      ..put(_asset('D/L0/001', modified: 1, subtypes: 1 << 34));

    await indexer.sync();

    final rows = await (db.select(
      db.localAsset,
    )..orderBy([(a) => OrderingTerm.asc(a.sourceId)])).get();
    expect(
      [
        for (final a in rows)
          [
            a.source,
            a.volume,
            a.sourceId,
            a.cloudId,
            a.mime,
            a.size,
            a.mtime,
            a.taken,
            a.width,
            a.height,
            a.durationMs,
            a.lat,
            a.lon,
            a.facets,
            a.burstId,
            a.favorite,
            a.edited,
            a.state,
            a.extracted,
          ],
      ],
      [
        [
          'photokit', '', 'A/L0/001', 'A:001:AV3x', 'image/*', 0, //
          1700000000000, 1600000000000, 4032, 3024, null, 48.8584, 2.2945,
          'hdr,live', null, 1, 1, 'present', null,
        ],
        [
          'photokit', '', 'B/L0/001', null, 'video/*', 0, 1700000001000, //
          null, null, null, 1500, null, null, 'high_frame_rate', null, 0, 0,
          'present', null,
        ],
        [
          'photokit', '', 'C/L0/001', null, 'image/*', 0, 1, null, null, //
          null, null, null, null, 'burst_cover,burst_pick', 'burst-1', 0, 0,
          'present', null,
        ],
        [
          'photokit', '', 'D/L0/001', null, 'image/*', 0, 1, null, null, //
          null, null, null, null, 'animated', null, 0, 0, 'present', null,
        ],
      ],
    );
    expect(rows.map((a) => a.id.length), [16, 16, 16, 16]);
    expect(
      [for (final a in rows) a.added == uuidTime(a.id)],
      [true, true, true, true],
    );
    final cursor = await db.select(db.volumeCursor).getSingle();
    expect(
      [cursor.source, cursor.volume, cursor.installId, cursor.version],
      ['photokit', '', 'install-1', '4'],
    );
    expect(library.calls, ['assets 0', 'assets 2', 'assets 4']);
  });

  test('a delta reads only the assets changed since the stored token', () async {
    for (final id in ['a', 'b', 'c', 'd']) {
      library.add(id);
    }
    await indexer.sync();
    await (db.update(db.localAsset)..where((a) => a.sourceId.equals('a')))
        .write(LocalAssetCompanion(contentHash: Value(Uint8List(32))));
    await db
        .into(db.backupState)
        .insert(
          BackupStateCompanion.insert(
            localAssetId: (await uuids())['c']!,
            state: 'selected',
            updatedAt: 1,
          ),
        );
    final before = await uuids();
    library.calls.clear();

    // Favourited, then added, deleted and hidden: the library no longer shows the last two.
    library
      ..put(_asset('a', modified: 2, favorite: true))
      ..add('e')
      ..history.add(['c'])
      ..history.add(['d']);
    library.shown
      ..remove('c')
      ..remove('d');
    await indexer.sync();

    expect(library.calls, ['changes 4', 'assetsOf a e', 'assetsOf c d']);
    expect(await index(), ['a 1', 'b 0', 'e 0']);
    final after = await uuids();
    expect([after['a'], after['b']], [before['a'], before['b']]);
    expect(
      await (db.select(
        db.localAsset,
      )..where((a) => a.contentHash.isNotNull())).map((a) => a.sourceId).get(),
      ['a'],
      reason: 'an edit in Photos keeps the original',
    );
    expect(await db.select(db.backupState).get(), isEmpty);

    library.calls.clear();
    await indexer.sync();
    expect(library.calls, ['changes 8']);
  });

  test(
    'a token the history no longer reaches reads the whole library again',
    () async {
      for (final id in ['a', 'b', 'c']) {
        library.add(id);
      }
      await indexer.sync();
      final before = await uuids();
      library.calls.clear();

      library
        ..add('d')
        ..shown.remove('b')
        ..kept = 4;
      await indexer.sync();

      expect(library.calls, ['changes 3', 'assets 0', 'assets 2']);
      expect(await index(), ['a 0', 'c 0', 'd 0']);
      expect((await uuids())['c'], before['c']);
    },
  );

  test(
    'app data restored onto another phone makes no false duplicates',
    () async {
      library
        ..add('a')
        ..add('b');
      await indexer.sync();
      await db
          .update(db.localAsset)
          .write(
            LocalAssetCompanion(
              contentHash: Value(Uint8List(32)),
              assetId: Value(Uint8List(16)),
            ),
          );
      await db
          .into(db.backupState)
          .insert(
            BackupStateCompanion.insert(
              localAssetId: (await uuids())['a']!,
              state: 'backed_up',
              updatedAt: 1,
            ),
          );

      // The new phone's history seems to reach the old token.
      library = _Library()
        ..install = 'install-2'
        ..add('x')
        ..add('a')
        ..add('y');
      await PhotoKitIndexer(db, library, page: 2).sync();

      expect(library.calls, ['assets 0', 'assets 2']);
      expect(await index(), ['a 0', 'x 0', 'y 0']);
      expect(
        await (db.select(db.localAsset)
              ..where((a) => a.contentHash.isNotNull() | a.assetId.isNotNull()))
            .get(),
        isEmpty,
      );
      expect(await db.select(db.backupState).get(), isEmpty);
      expect(
        (await db.select(db.volumeCursor).getSingle()).installId,
        'install-2',
      );
    },
  );

  test('without access the index is left as it is', () async {
    library.add('a');
    await indexer.sync();
    library
      ..granted = MediaAccess.none
      ..shown.clear()
      ..kept = 9
      ..calls.clear();

    await indexer.sync();

    expect(library.calls, isEmpty);
    expect(await index(), ['a 0']);
  });

  test('with limited access every sync reads the whole selection', () async {
    library
      ..granted = MediaAccess.partial
      ..add('a')
      ..add('b');
    await indexer.sync();
    library.calls.clear();

    // The user changes the selection in the picker: the history shows nothing.
    library.shown
      ..remove('a')
      ..['c'] = _asset('c');
    await indexer.sync();

    expect(library.calls, ['assets 0', 'assets 2']);
    expect(await index(), ['b 0', 'c 0']);
  });

  test(
    '100,000 assets are indexed on an isolate of their own, adding at most 1% to the 60 Hz frames this one misses '
    'idle; a change lands within 1 s',
    () async {
      final dir = await Directory.systemTemp.createTemp('photolib-photokit-');
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

      // Tests run JIT, which pauses every isolate while it installs code run for the first time; release builds are
      // compiled ahead of time.
      await _timed(replica, 1000, 'warm-up');
      var run = 0;
      late Duration cold, delta;
      await withinFrameBudget(() async {
        (cold, delta) = await _timed(replica, 100000, 'run ${run++}');
        print(
          'cold index of 100,000 assets: $cold, delta of 20 changes: $delta',
        );
      });
      expect(cold, lessThan(const Duration(seconds: 60)));
      expect(delta, lessThan(const Duration(seconds: 1)));
      final favourites = await (replica.select(
        replica.localAsset,
      )..where((a) => a.favorite.equals(1))).get();
      expect(favourites, hasLength(20));
      expect(
        await replica
            .customSelect('SELECT COUNT(*) AS n FROM local_asset')
            .map((r) => r.read<int>('n'))
            .getSingle(),
        100000,
      );
    },
    tags: 'alone',
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
