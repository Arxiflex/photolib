@TestOn('vm')
library;

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:fixnum/fixnum.dart';
import 'package:photolib_api/photolib_api.dart';
import 'package:photolib_api/recipe.dart' as r;
import 'package:photolib_api/sync.dart' as pb;
import 'package:photolib_api/testing.dart';
import 'package:photolib_data/photolib_data.dart';
import 'package:test/test.dart';

import 'support/sync_rows.dart';

void main() {
  late SyncServer photolibd;
  late Server server;
  late Replica db;
  late Mutations outbox;
  const start = 1767225600000;
  var now = start;
  setUp(() async {
    photolibd = await SyncServer.start();
    photolibd.capabilities.add('sync.mutations.v1');
    photolibd.streams.addAll({
      for (final s in ['account', 'tags', 'people', 'faces/${uuid(1)}']) s: [],
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
      'albums': [
        [
          rows('albums', [
            {'id': uuid(50), 'owner_id': uuid(100), 'title': 'Trip'},
          ]),
        ],
      ],
    });
    server = Server(NetworkConfig(endpoints: [photolibd.url]));
    db = Replica(NativeDatabase.memory());
    now = start;
    outbox = Mutations(db, now: () => now);
    await SyncEngine(db, server).run();
  });
  tearDown(() async {
    await db.close();
    server.close();
    await photolibd.close();
  });

  Future<List<pb.Mutation>> waiting() async => [
    for (final o in await db.pendingOutbox(1 << 62, 1000).get())
      pb.Mutation.fromBuffer(o.mutation),
  ];

  Future<AssetData> assetRow(int n) =>
      (db.select(db.asset)..where((a) => a.id.equals(bytes(n)))).getSingle();

  Future<List<List<Object?>>> items() async => [
    for (final i
        in await (db.select(db.albumItem)..orderBy([
              (i) => OrderingTerm(expression: i.sortKey),
              (i) => OrderingTerm(expression: i.id),
            ]))
            .get())
      [i.id, i.assetId, i.sortKey],
  ];

  /// Answers every mutation as applied, with [rows] as what the server holds.
  pb.PushMutationsResponse Function(pb.PushMutationsRequest) applied(
    List<pb.Rows> rows, {
    int clock = 0,
  }) =>
      (request) => pb.PushMutationsResponse(
        results: [
          for (final m in request.mutations)
            pb.MutationResult(mutationId: m.mutationId),
        ],
        rows: rows,
        clock: pb.Hlc(physicalMs: Int64(clock)),
      );

  test('an edit shows at once and waits with a key of its own and a later '
      'reading of the clock each time, whatever the wall clock does', () async {
    await outbox.edit('assets', bytes(1), {'title': 'mine', 'rating': 4});
    await outbox.edit('asset_user_state', bytes(2), {'favorite': true});
    now -= 5000;
    await outbox.edit('assets', bytes(1), {'trashed_at': 0});
    final a = await assetRow(1);
    expect((a.title, a.rating, a.trashedAt), ('mine', 4, start));
    final favourite = await db.select(db.assetUserState).getSingle();
    expect([favourite.assetId, favourite.favorite], [bytes(2), 1]);

    final sent = await db.select(db.outbox).get();
    expect(
      [
        for (final o in sent) [o.entity, o.entityId],
      ],
      [
        ['assets', bytes(1)],
        ['asset_user_state', bytes(2)],
        ['assets', bytes(1)],
      ],
    );
    final mutations = await waiting();
    expect(
      [for (final m in mutations) (m.hlc.physicalMs.toInt(), m.hlc.counter)],
      [(start, 0), (start, 1), (start, 2)],
    );
    expect({for (final m in mutations) m.hlc.deviceId}, hasLength(1));
    expect({for (final m in mutations) m.mutationId}, hasLength(3));
    expect(mutations.first.edit.entity, 'assets');
    expect(mutations.first.edit.id, uuid(1));
    expect(mutations.first.edit.fields['title']?.text, 'mine');
    expect(mutations.first.edit.fields['rating']?.integer, Int64(4));
  });

  test('adds, moves and removals in an album show at once, each item with '
      'the id every device gives it', () async {
    final id = itemId(bytes(50), bytes(1));
    final other = itemId(bytes(50), bytes(2));
    await outbox.addToAlbum(bytes(50), bytes(1));
    await outbox.addToAlbum(bytes(50), bytes(2));
    expect(await items(), [
      [id, bytes(1), 'V'],
      [other, bytes(2), 'k'],
    ]);
    await outbox.moveInAlbum(other, before: id);
    expect(await items(), [
      [other, bytes(2), 'F'],
      [id, bytes(1), 'V'],
    ]);
    await outbox.removeFromAlbum(bytes(50), bytes(1));
    expect(await items(), [
      [other, bytes(2), 'F'],
    ]);
    final [add, _, move, remove] = await waiting();
    expect(
      (add.member.setId, add.member.elementId, add.member.present),
      (uuid(50), uuid(1), true),
    );
    expect(add.member.sortKey, 'V');
    expect(
      (move.edit.entity, move.edit.fields['sort_key']?.text),
      ('album_items', 'F'),
    );
    expect((remove.member.present, remove.member.sortKey), (false, ''));
    expect(
      [for (final o in await db.select(db.outbox).get()) o.entityId],
      [id, other, other, id],
    );

    Uint8List of(String uuid) => Uint8List.fromList([
      for (var i = 0; i < 32; i += 2)
        int.parse(uuid.replaceAll('-', '').substring(i, i + 2), radix: 16),
    ]);
    expect(
      itemId(
        of('00000000-0000-7000-8000-000000000001'),
        of('00000000-0000-7000-8000-000000000002'),
      ),
      of('5b1f6a53-e22f-8490-bfdc-e63a613abf90'),
      reason: 'as photolibd names it',
    );
  });

  test('a push sends what waits in order, shows what the server holds and '
      'catches the clock up with the server', () async {
    await outbox.edit('assets', bytes(1), {'title': 'mine'});
    await outbox.edit('assets', bytes(2), {'rating': 5});
    final sent = await waiting();
    final pushed = <pb.PushMutationsRequest>[];
    final answer = applied([
      rows('assets', [
        asset(1, title: 'theirs'),
        {...asset(2), 'rating': 5},
      ]),
    ], clock: start + 60000);
    photolibd.onPush = (request) {
      pushed.add(request);
      return answer(request);
    };
    await outbox.push(server);
    expect(pushed.single.mutations, sent);
    expect(
      ((await assetRow(1)).title, (await assetRow(2)).rating),
      ('theirs', 5),
      reason: 'a later edit from elsewhere won',
    );
    expect(await db.select(db.outbox).get(), isEmpty);
    await outbox.edit('assets', bytes(1), {'title': 'again'});
    final next = (await waiting()).single.hlc;
    expect((next.physicalMs.toInt(), next.counter), (start + 60000, 1));
  });

  test('a mutation the server refuses for good is rolled back, kept for its '
      'user until dismissed, and what still waits shows over it', () async {
    await outbox.edit('assets', bytes(1), {'title': 'refused'});
    await outbox.edit('asset_user_state', bytes(2), {'favorite': true});
    await outbox.edit('assets', bytes(1), {'rating': 3});
    final [refused, favourite, unanswered] = await waiting();
    photolibd.onPush = (request) => pb.PushMutationsResponse(
      results: [
        pb.MutationResult(
          mutationId: refused.mutationId,
          rejected: ErrorDetail(code: 'mutation.forbidden'),
        ),
        pb.MutationResult(mutationId: favourite.mutationId),
      ],
      rows: [
        rows('assets', [asset(1)]),
        rows('asset_user_state', [
          {'user_id': uuid(100), 'asset_id': uuid(2), 'favorite': true},
        ]),
      ],
    );
    await outbox.push(server);
    final a = await assetRow(1);
    expect((a.title, a.rating), (null, 3));
    expect((await db.select(db.assetUserState).getSingle()).favorite, 1);
    final rejected = await outbox.rejected().get();
    expect(
      [
        for (final r in rejected) [r.entity, r.entityId, r.error],
      ],
      [
        ['assets', bytes(1), 'mutation.forbidden'],
      ],
    );
    expect(await waiting(), [unanswered]);
    await outbox.dismiss();
    expect(await outbox.rejected().get(), isEmpty);
    expect(await waiting(), [unanswered]);
  });

  test('the albums this device made go to the account with their ids, titles '
      'and contents once every item is on the server, and only once', () async {
    Future<void> device(int n, {Uint8List? asset}) => db
        .into(db.localAsset)
        .insert(
          LocalAssetCompanion.insert(
            id: bytes(n),
            source: 'folder',
            sourceId: '$n',
            size: n,
            mtime: n,
            assetId: Value(asset),
          ),
        );
    await device(7, asset: bytes(2));
    await device(8);
    final trip = await createAlbum(db, 'Trip');
    await addToAlbum(db, trip, [bytes(1), bytes(7)]);
    final later = await createAlbum(db, 'Later');
    await addToAlbum(db, later, [bytes(8)]);
    final empty = await createAlbum(db, 'Empty');

    expect(await outbox.adoptAlbums(), 2, reason: 'not the one with item 8');
    expect(await outbox.adoptAlbums(), 0, reason: 'they wait in the outbox');
    final sent = await waiting();
    expect(
      [
        for (final m in sent)
          if (m.hasEdit())
            [m.edit.entity, m.edit.id, m.edit.fields['title']?.text]
          else
            [m.member.setId, m.member.elementId, m.member.sortKey],
      ],
      [
        ['albums', uuidOf(trip), 'Trip'],
        [uuidOf(trip), uuid(1), isNotEmpty],
        [uuidOf(trip), uuid(2), isNotEmpty],
        ['albums', uuidOf(empty), 'Empty'],
      ],
    );

    photolibd.onPush = applied([
      rows('albums', [
        {'id': uuidOf(trip), 'owner_id': uuid(100), 'title': 'Trip'},
        {'id': uuidOf(empty), 'owner_id': uuid(100), 'title': 'Empty'},
      ]),
    ]);
    await outbox.push(server);
    expect(await outbox.adoptAlbums(), 0, reason: 'the account holds them');
    await (db.update(db.localAsset)..where((a) => a.id.equals(bytes(8)))).write(
      LocalAssetCompanion(assetId: Value(bytes(1))),
    );
    expect(await outbox.adoptAlbums(), 1, reason: 'its item was uploaded');
    expect((await waiting()).first.edit.id, uuidOf(later));
  });

  test('emptying the trash asks the server, which answers the count to '
      'confirm before it deletes a large trash', () async {
    final asked = <String>[];
    photolibd.onEmptyTrash = (request) {
      asked.add(request.confirmToken);
      return request.confirmToken == 'T'
          ? pb.EmptyTrashResponse(queued: Int64(2000))
          : pb.EmptyTrashResponse(
              held: Confirmation(
                count: Int64(2000),
                total: Int64(2000),
                token: 'T',
              ),
            );
    };
    final first = await outbox.emptyServerTrash(server.rpc);
    expect((first.queued, first.held, first.token), (0, 2000, 'T'));
    final second = await outbox.emptyServerTrash(
      server.rpc,
      confirmToken: first.token,
    );
    expect((second.queued, second.held), (2000, null));
    expect(asked, ['', 'T']);
  });

  test('a sync batch shows the edits still waiting over its rows', () async {
    await outbox.edit('assets', bytes(1), {'title': 'mine'});
    await outbox.addToAlbum(bytes(50), bytes(2));
    photolibd.capabilities.remove('sync.mutations.v1');
    photolibd.streams['assets/${uuid(1)}'] = [
      ...?photolibd.streams['assets/${uuid(1)}'],
      [
        rows('assets', [asset(1, title: 'old'), asset(2, title: 'two')]),
      ],
    ];
    photolibd.streams['albums'] = [
      ...?photolibd.streams['albums'],
      [
        rows('album_items', [
          {'id': uuid(60)},
        ], deleted: true),
      ],
    ];
    await SyncEngine(db, server).run();
    expect(
      ((await assetRow(1)).title, (await assetRow(2)).title),
      ('mine', 'two'),
    );
    expect(await items(), hasLength(1));
  });

  test('an unreachable server keeps them waiting, tried again later and '
      'later', () async {
    await outbox.edit('assets', bytes(1), {'title': 'mine'});
    photolibd.unavailable.add('PushMutations');
    await expectLater(outbox.push(server), throwsA(isA<CallError>()));
    await expectLater(outbox.push(server), completes, reason: 'not yet');
    var pushes = 0;
    photolibd
      ..unavailable.clear()
      ..onPush = (request) {
        pushes++;
        return applied([])(request);
      };
    await outbox.push(server);
    expect(pushes, 0);
    final row = await db.select(db.outbox).getSingle();
    expect((row.attempts, row.retryAt), (1, start + 2000));
    now += 2000;
    await outbox.push(server);
    expect(pushes, 1);
    expect(await db.select(db.outbox).get(), isEmpty);
  });

  test('the sync engine pushes before it syncs, when the server takes '
      'mutations', () async {
    await outbox.edit('assets', bytes(1), {'title': 'mine'});
    final calls = <String>[];
    photolibd
      ..onPush = (request) {
        calls.add('push');
        return applied([])(request);
      }
      ..onSync = () => calls.add('sync');
    await SyncEngine(db, server).run();
    expect(calls.take(2), ['push', 'sync']);
    expect(await db.select(db.outbox).get(), isEmpty);
  });

  r.EditRecipe crop(double x) => r.EditRecipe(
    schemaVersion: 1,
    operations: [
      r.Operation(
        operationId: 'crop',
        crop: r.CropOperation(x: x, y: 0, width: 1 - x, height: 1),
      ),
    ],
  );

  Future<List<AssetVersionData>> versions() => (db.select(
    db.assetVersion,
  )..orderBy([(v) => OrderingTerm(expression: v.createdAt)])).get();

  test('a version shows at once, is made the current one by an edit of the '
      'asset, and a revert is one more edit that changes no version', () async {
    final first = await outbox.addVersion(
      bytes(1),
      crop(0.25).writeToBuffer(),
      label: 'Crop',
    );
    now += 10;
    final second = await outbox.addVersion(bytes(1), crop(0.5).writeToBuffer());
    final [a, b] = await versions();
    expect([a.id, a.kind, a.label, a.parentId], [first, 'edit', 'Crop', null]);
    expect([b.id, b.parentId, b.label], [second, first, null]);
    expect(r.EditRecipe.fromBuffer(b.recipe!), crop(0.5));
    expect((await assetRow(1)).currentVersionId, second);

    now += 10;
    await outbox.revert(bytes(1), first);
    expect((await assetRow(1)).currentVersionId, first);
    expect(await versions(), [a, b], reason: 'no version changed');

    final sent = await waiting();
    expect(
      sent.map((m) => m.hasVersion() ? 'version' : m.edit.entity).toList(),
      ['version', 'assets', 'version', 'assets', 'assets'],
    );
    expect(sent[0].version.assetId, uuid(1));
    expect(sent[0].version.versionId, uuidOf(first));
    expect(sent[0].version.label, 'Crop');
    expect(sent[2].version.parentId, uuidOf(first));
    expect(sent[4].edit.fields['current_version_id']?.text, uuidOf(first));
    final queued = await db.select(db.outbox).get();
    expect(
      [for (final o in queued) '${o.entity} ${uuidOf(o.entityId)}'],
      [
        'versions ${uuidOf(first)}',
        'assets ${uuid(1)}',
        'versions ${uuidOf(second)}',
        'assets ${uuid(1)}',
        'assets ${uuid(1)}',
      ],
    );
  });

  test('a version the server refuses is rolled back with the rest of its '
      'edit, and one it applies stays as it answers', () async {
    final id = await outbox.addVersion(bytes(1), crop(0.25).writeToBuffer());
    photolibd.onPush = (request) => pb.PushMutationsResponse(
      results: [
        for (final m in request.mutations)
          pb.MutationResult(
            mutationId: m.mutationId,
            rejected: m.hasVersion()
                ? ErrorDetail(code: 'mutation.invalid')
                : null,
          ),
      ],
      rows: [
        rows('versions', [
          {'id': uuidOf(id)},
        ], deleted: true),
      ],
      clock: pb.Hlc(physicalMs: Int64(start)),
    );
    await outbox.push(server);
    expect(await versions(), isEmpty, reason: 'the server holds none');
    final refused = await outbox.rejected().get();
    expect(refused.map((o) => o.error), ['mutation.invalid']);
  });
}
