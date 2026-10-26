@TestOn('vm')
library;

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:photolib_api/photolib_api.dart';
import 'package:photolib_api/sync.dart' as pb;
import 'package:photolib_api/testing.dart';
import 'package:photolib_data/photolib_data.dart';
import 'package:test/test.dart';

import 'support/sync_rows.dart';

/// Per-surface visibility (ORG-17): what an account hides by album or library
/// leaves its timeline, from the server's state or its own edit, with no join
/// of albums in the timeline's views.
void main() {
  late SyncServer photolibd;
  late Server server;
  late Replica db;
  late Mutations outbox;
  setUp(() async {
    photolibd = await SyncServer.start();
    photolibd.streams.addAll({
      for (final s in ['tags', 'people', 'albums', 'faces/${uuid(1)}']) s: [],
      'account': [],
      'libraries': [
        [
          rows('libraries', [library(1)]),
        ],
      ],
      'assets/${uuid(1)}': [
        [
          rows('assets', [asset(1), asset(2)]),
        ],
      ],
    });
    server = Server(NetworkConfig(endpoints: [photolibd.url]));
    db = Replica(NativeDatabase.memory());
    outbox = Mutations(db);
  });
  tearDown(() async {
    await db.close();
    server.close();
    await photolibd.close();
  });

  Future<void> sync(List<pb.Rows> batch) async {
    photolibd.streams['account'] = [...?photolibd.streams['account'], batch];
    await SyncEngine(db, server).run();
  }

  Map<String, Object?> state(int asset, {bool timeline = false}) => {
    'user_id': uuid(100),
    'asset_id': uuid(asset),
    'favorite': false,
    'hidden_from_memories': false,
    'album_hides_timeline': timeline,
    'album_hides_memories': false,
    'txid': 9,
  };

  Future<List<Object?>> cloud() async => [
    for (final r
        in await db.customSelect('SELECT id FROM cloud_item ORDER BY id').get())
      r.read<List<int>>('id')[15],
  ];

  Future<void> device(int n, {required int asset}) => db
      .into(db.localAsset)
      .insert(
        LocalAssetCompanion.insert(
          id: bytes(n + 50),
          source: 'folder',
          sourceId: '$n',
          size: n,
          mtime: n,
          assetId: Value(bytes(asset)),
        ),
      );

  Future<int> shown() async =>
      (await db
              .customSelect('SELECT count(*) AS n FROM timeline_item')
              .getSingle())
          .read<int>('n');

  test('an asset in an album the account hides leaves the server tiles and '
      'returns when the server says it is not', () async {
    await sync([]);
    expect(await cloud(), [1, 2]);
    await sync([
      rows('asset_user_state', [state(1, timeline: true)]),
    ]);
    expect(await cloud(), [2]);
    await sync([
      rows('asset_user_state', [state(1)]),
    ]);
    expect(await cloud(), [1, 2]);
  });

  test('a library the account hides is no tile, its own edit shows at once, '
      'and it waits in the outbox for the server', () async {
    await sync([]);
    await outbox.edit('library_user_state', bytes(1), {
      'hide_from_timeline': true,
    });
    expect(await cloud(), isEmpty);
    final [sent] = await db.pendingOutbox(1 << 62, 10).get();
    expect(sent.entity, 'library_user_state');
    expect(sent.entityId, orderedEquals(bytes(1)));
    await outbox.edit('library_user_state', bytes(1), {
      'hide_from_timeline': false,
    });
    expect(await cloud(), [1, 2]);
  });

  test('a device item whose asset is hidden by album or library leaves the '
      'timeline too, and comes back with it', () async {
    await sync([]);
    await device(1, asset: 1);
    await device(2, asset: 2);
    expect(await shown(), 2);
    await sync([
      rows('asset_user_state', [state(1, timeline: true)]),
    ]);
    expect(await shown(), 1, reason: 'asset 1 is in a hidden album');
    await sync([
      rows('asset_user_state', [state(1)]),
    ]);
    expect(await shown(), 2);
    await outbox.edit('library_user_state', bytes(1), {
      'hide_from_timeline': true,
    });
    expect(await shown(), 0, reason: 'the library is hidden');
    await outbox.edit('library_user_state', bytes(1), {
      'hide_from_timeline': false,
    });
    expect(await shown(), 2);
  });
}
