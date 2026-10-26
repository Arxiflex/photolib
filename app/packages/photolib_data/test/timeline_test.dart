@TestOn('vm')
library;

import 'dart:io';
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

  const hour = 3600000;
  // 2 May 2024 22:00 UTC.
  const may2 = 1714687200000;

  Future<void> add(
    int n, {
    String? takenLocal,
    int? takenUtc,
    int? taken,
    int mtime = may2,
    int added = may2,
    String state = 'present',
    int trashed = 0,
    int hidden = 0,
    int archived = 0,
  }) => db
      .into(db.localAsset)
      .insert(
        LocalAssetCompanion.insert(
          id: _id(n),
          source: 'folder',
          sourceId: '$n',
          size: n,
          mtime: mtime,
          takenLocal: Value(takenLocal),
          takenUtc: Value(takenUtc),
          taken: Value(taken),
          added: Value(added),
          state: Value(state),
          trashed: Value(trashed),
          hidden: Value(hidden),
          archived: Value(archived),
        ),
      );

  Future<List<(int, int)>> days(Selectable<dynamic> query) async => [
    for (final r in await query.get()) (r.day as int, r.count as int),
  ];

  List<int> ids(List<TimelineItemData> items) => [
    for (final i in items) i.id[15],
  ];

  test('the timeline: what is present, newest local day first, then '
      'capture time; an item not yet read at its platform date or file '
      'time, as a UTC day', () async {
    // On 3 May in Lisbon, but 2 May in UTC.
    await add(1, takenLocal: '2024-05-03T00:30:00', takenUtc: may2 + 1 * hour);
    await add(2, takenLocal: '2024-05-03T08:00:00', takenUtc: may2 + 9 * hour);
    await add(3, taken: may2 + 30 * hour); // MediaStore's, 4 May 04:00 UTC
    await add(4, mtime: may2); // 2 May 22:00 UTC
    await add(5, takenLocal: '2024-05-02T23:00:00', takenUtc: may2 + 2 * hour);
    await add(6, state: 'missing');
    await add(7, trashed: 1);
    await add(8, takenLocal: '0000-00-00T00:00:00'); // no date: its file's
    expect(await days(db.timelineDays(false, null)), [
      (20240504, 1),
      (20240503, 2),
      (20240502, 3),
    ]);
    final all = await db.timelinePage(20240504, false, null, 100, 0).get();
    expect(ids(all), [3, 2, 1, 5, 8, 4]);
    expect(all.first.day, 20240504);
    expect(ids(await db.timelinePage(20240503, false, null, 2, 1).get()), [
      1,
      5,
    ], reason: 'from the second of 3 May on');
  });

  test('date added: each local day, from where a page of one starts', () async {
    await add(1, added: may2); // 3 May 00:00 at UTC+2
    await add(2, added: may2 - hour);
    await add(3, added: may2 + 5 * hour);
    expect(await days(db.timelineAddedDays(0, false, null)), [
      (20240503, 1),
      (20240502, 2),
    ]);
    expect(await days(db.timelineAddedDays(2 * hour, false, null)), [
      (20240503, 2),
      (20240502, 1),
    ]);
    // Before 3 May at UTC+2, skipping none.
    expect(ids(await db.timelineAddedPage(may2, false, null, 10, 0).get()), [
      2,
    ]);
    expect(
      ids(
        await db.timelineAddedPage(may2 + 22 * hour, false, null, 10, 0).get(),
      ),
      [3, 1, 2],
    );
  });

  test('hidden and archived items are left out unless veiled ones are '
      'shown', () async {
    await add(1, takenLocal: '2024-05-03T08:00:00');
    await add(2, takenLocal: '2024-05-03T09:00:00', hidden: 1);
    await add(3, takenLocal: '2024-05-02T09:00:00', archived: 1);
    await add(4, added: may2 + hour, hidden: 1, archived: 1);
    expect(await days(db.timelineDays(false, null)), [(20240503, 1)]);
    expect(await days(db.timelineDays(true, null)), [
      (20240503, 2),
      (20240502, 2),
    ]);
    expect(ids(await db.timelinePage(20240503, false, null, 10, 0).get()), [1]);
    expect(ids(await db.timelinePage(20240503, true, null, 10, 0).get()), [
      2,
      1,
      4,
      3,
    ]);
    expect(await days(db.timelineAddedDays(0, false, null)), [(20240502, 1)]);
    expect(ids(await db.timelineAddedPage(may2 * 2, true, null, 10, 0).get()), [
      4,
      3,
      2,
      1,
    ]);
  });

  test("date added's day counts are the items', at every offset, through "
      'whatever happens to them', () async {
    final random = Random(603);
    final present = {for (var n = 1; n <= 60; n++) n: false};
    // The days counted item by item at an offset, as the counts must be.
    const byItem =
        "SELECT CAST(strftime('%Y%m%d', (added + ?) / 86400000 * 86400, "
        "'unixepoch') AS INTEGER) AS day, COUNT(*) AS count FROM "
        'timeline_item WHERE folder NOT IN (SELECT id FROM hidden_folder) '
        'GROUP BY 1 ORDER BY 1 DESC';
    Future<List<(int, int)>> counted(int offset) async => [
      for (final r
          in await db.customSelect(byItem, variables: [Variable(offset)]).get())
        (r.read<int>('day'), r.read<int>('count')),
    ];
    await db.customStatement(
      "INSERT INTO device_folder (id, volume, path) VALUES (1, 'v', 'a/')",
    );
    for (var round = 0; round < 300; round++) {
      final n = random.nextInt(60) + 1;
      final id = Uint8List(16)..[15] = n;
      final where = db.update(db.localAsset)..where((a) => a.id.equals(id));
      // Within two days, in minutes, on either side of midnight anywhere.
      final added = may2 + (random.nextInt(2880) - 1440) * 60000;
      if (!present[n]!) {
        await add(n, added: added);
        present[n] = true;
      } else {
        switch (random.nextInt(6)) {
          case 0:
            await (db.delete(
              db.localAsset,
            )..where((a) => a.id.equals(id))).go();
            present[n] = false;
          case 1:
            await where.write(LocalAssetCompanion(added: Value(added)));
          case 2:
            await where.write(
              LocalAssetCompanion(trashed: Value(random.nextInt(2))),
            );
          case 3:
            await where.write(
              LocalAssetCompanion(
                state: Value(random.nextBool() ? 'present' : 'missing'),
              ),
            );
          case 4:
            await where.write(
              LocalAssetCompanion(folder: Value(random.nextInt(2))),
            );
          case _:
            await showFolder(db, 1, shown: random.nextBool());
        }
      }
      for (final offset in [0, 330 * 60000, 345 * 60000, -570 * 60000]) {
        expect(
          await days(db.timelineAddedDays(offset, false, null)),
          await counted(offset),
          reason: 'round $round at offset $offset',
        );
      }
    }
  });

  group('device and server', () {
    // Libraries 1 (managed) and 2 (external) are the account's; assets in
    // library 3 reach it through a share.
    setUp(() async {
      for (final (n, kind) in [(1, 'managed'), (2, 'external')]) {
        await db.customStatement(
          'INSERT INTO library (id, owner_id, kind, privacy, access, state, '
          "txid) VALUES (?, ?, '$kind', 'standard', 'rw', 'online', 1)",
          [_id(n), _id(9)],
        );
      }
    });

    Future<void> asset(
      int n, {
      int library = 1,
      String kind = 'image',
      int taken = may2,
      int created = 0,
      int? trashedAt,
      int archived = 0,
    }) => db.customStatement(
      'INSERT INTO asset (id, library_id, owner_id, original_filename, source, '
      'media_kind, taken_utc, file_size_total, created_at, trashed_at, '
      "archived, txid) VALUES (?, ?, ?, ?, 'upload', ?, ?, ?, ?, ?, ?, 1)",
      [
        _id(100 + n),
        _id(library),
        _id(9),
        'IMG_$n.jpg',
        kind,
        taken,
        n * 100,
        created,
        trashedAt,
        archived,
      ],
    );

    Future<void> link(int local, int? asset) => db.customStatement(
      'UPDATE local_asset SET asset_id = ? WHERE id = ?',
      [if (asset == null) null else _id(100 + asset), _id(local)],
    );

    Future<List<int>> counts([String? backup]) async => [
      for (final d in await db.timelineDays(false, backup).get()) d.count,
    ];

    // Each tile's id, the device item's or else the asset's, and backup state;
    // the days count as many, whatever changed the tiles (timeline_day,
    // timeline_added).
    Future<List<String>> tiles([String? backup]) async {
      final page = [
        for (final t
            in await db.timelinePage(99999999, false, backup, 100, 0).get())
          "${t.id[15] >= 100 ? 'a${t.id[15] - 100}' : 'd${t.id[15]}'} ${t.backup}",
      ];
      expect((await counts(backup)).fold(0, (n, c) => n + c), page.length);
      final added = await db.timelineAddedDays(0, false, backup).get();
      expect(added.fold(0, (n, d) => n + d.count), page.length);
      return page;
    }

    test('a photo on the device and the server is one tile: the device '
        "item's, backed up when its asset is in a managed library; an asset "
        'no present device item links is cloud only', () async {
      for (var n = 1; n <= 7; n++) {
        await add(n, takenUtc: may2 - n * hour);
      }
      await asset(1, taken: may2 - 30 * hour); // linked: the device's time
      await asset(2, taken: may2 - 3 * hour - 1); // only on the server
      await asset(3, library: 2); // an external library holds no backup
      await asset(4, trashedAt: 5); // deleted in the library
      await asset(5); // in two folders of the device
      await asset(6, taken: may2 - 6 * hour - 1); // in the device's trash
      await asset(7, archived: 1);
      await asset(8, library: 3); // a share's, not the account's library
      await asset(9, kind: ''); // a file that is no photo or video
      for (final (local, a) in [
        (1, 1),
        (3, 3),
        (4, 4),
        (5, 5),
        (6, 5),
        (7, 6),
      ]) {
        await link(local, a);
      }
      await db.customStatement(
        'UPDATE local_asset SET trashed = 1 '
        'WHERE id = ?',
        [_id(7)],
      );
      expect(await tiles(), [
        'd1 backed_up',
        'd2 not_backed_up',
        'd3 not_backed_up',
        'a2 cloud_only',
        'd5 backed_up',
        'a6 cloud_only',
      ]);
      expect(await counts(), [6]);
      expect(await tiles('cloud_only'), ['a2 cloud_only', 'a6 cloud_only']);
      expect(await tiles('backed_up'), ['d1 backed_up', 'd5 backed_up']);
      expect(await tiles('not_backed_up'), [
        'd2 not_backed_up',
        'd3 not_backed_up',
      ]);
      expect(await counts('cloud_only'), [2]);
      expect(await counts('backed_up'), [2]);
    });

    test(
      'tiles follow links, presence and the assets as they change',
      () async {
        await add(1, takenUtc: may2 - hour);
        await add(2, takenUtc: may2 - 2 * hour);
        await link(1, 1); // linked before its asset arrives by sync
        expect(await tiles(), ['d1 not_backed_up', 'd2 not_backed_up']);
        await asset(1, taken: may2 - hour);
        await asset(2, taken: may2 - 2 * hour);
        expect(await tiles(), [
          'd1 backed_up',
          'a2 cloud_only',
          'd2 not_backed_up',
        ]);
        await link(2, 2); // the backup found it on the server
        expect(await tiles(), ['d1 backed_up', 'd2 backed_up']);
        for (final trashed in [1, 0]) {
          await db.customStatement(
            'UPDATE local_asset SET trashed = ? WHERE id = ?',
            [trashed, _id(2)],
          );
          expect(await tiles(), [
            'd1 backed_up',
            if (trashed == 1) 'a2 cloud_only' else 'd2 backed_up',
          ]);
        }
        await db.customStatement(
          "UPDATE local_asset SET state = 'missing' WHERE id = ?",
          [_id(1)],
        );
        expect(await tiles(), ['a1 cloud_only', 'd2 backed_up']);
        await db.customStatement(
          'UPDATE asset SET trashed_at = 5 WHERE id = ?',
          [_id(102)],
        );
        expect(await tiles(), [
          'a1 cloud_only',
        ], reason: 'deleted in the library');
        await db.customStatement('DELETE FROM asset WHERE id = ?', [_id(101)]);
        expect(await tiles(), isEmpty);
        await db.customStatement('DELETE FROM asset WHERE id = ?', [_id(102)]);
        expect(await tiles(), [
          'd2 not_backed_up',
        ], reason: 'its asset deleted forever: no longer backed up');
        await db.customStatement('DELETE FROM local_asset');
        await asset(3);
        expect(await tiles(), ['a3 cloud_only']);
      },
    );

    test("signed out, the server's rows and cursors go, the device's stay, "
        'no longer backed up', () async {
      await add(1);
      await asset(1);
      await link(1, 1);
      await db.customStatement(
        "INSERT INTO sync_cursor VALUES ('albums', x'01', 1, 'e')",
      );
      await db.customStatement('INSERT INTO partner_library VALUES (?, ?, 0)', [
        _id(8),
        _id(1),
      ]);
      expect(await tiles(), ['d1 backed_up']);
      await forgetServer(db);
      expect(await tiles(), ['d1 not_backed_up']);
      for (final table in [
        'library',
        'asset',
        'sync_cursor',
        'partner_library',
      ]) {
        expect(
          await db.customSelect('SELECT * FROM $table').get(),
          isEmpty,
          reason: table,
        );
      }
    });

    test('a device copy that goes hands its tile to the next', () async {
      await add(1);
      await add(2);
      await asset(1);
      await link(1, 1);
      await link(2, 1);
      expect(await tiles(), ['d1 backed_up']);
      await db.customStatement('DELETE FROM local_asset WHERE id = ?', [
        _id(1),
      ]);
      expect(await tiles(), ['d2 backed_up']);
      await link(2, null);
      expect(await tiles(), ['a1 cloud_only', 'd2 not_backed_up']);
    });

    test(
      'by date added, the server adds its assets when it made them',
      () async {
        await add(1);
        await asset(1, created: may2 + hour);
        await asset(2, created: may2 - hour);
        expect(await days(db.timelineAddedDays(0, false, null)), [
          (20240502, 3),
        ]);
        expect(await days(db.timelineAddedDays(0, false, 'cloud_only')), [
          (20240502, 2),
        ]);
        expect(
          [
            for (final t
                in await db
                    .timelineAddedPage(may2 + 2 * hour, false, null, 10, 0)
                    .get())
              t.id[15],
          ],
          [101, 1, 102],
        );
      },
    );
  });

  test(
    'pages merge the timeline indexes; day counts scan them in order',
    () async {
      Future<String> plan(String sql) async => [
        for (final r
            in await db
                .customSelect(
                  'EXPLAIN QUERY PLAN $sql',
                  variables: [const Variable(false)],
                )
                .get())
          r.read<String>('detail'),
      ].join('; ');
      for (final (where, order, device, server) in [
        ('day <= 20240503', 'day DESC, sort_key DESC', 'timeline', 'timeline'),
        ('added < 5', 'added DESC', 'added', 'added'),
      ]) {
        expect(
          await plan(
            "SELECT * FROM timeline_item WHERE $where AND backup = 'x' "
            'AND (? OR hidden + archived = 0) '
            'UNION ALL SELECT * FROM cloud_item WHERE $where '
            'ORDER BY $order, id DESC LIMIT 10 OFFSET 5',
          ),
          allOf(
            contains('MERGE (UNION ALL)'),
            contains('USING INDEX local_asset_$device'),
            contains('USING INDEX asset_$server'),
            isNot(contains('TEMP B-TREE')),
          ),
        );
      }
      for (final (view, index) in [
        ('timeline_item', 'local_asset_timeline'),
        ('cloud_item', 'asset_timeline'),
      ]) {
        expect(
          await plan(
            "SELECT day, COUNT(*) FROM $view WHERE backup = 'x' "
            'AND (? OR hidden + archived = 0) GROUP BY day',
          ),
          allOf(contains('USING INDEX $index'), isNot(contains('TEMP B-TREE'))),
        );
      }
      final drift = File('lib/src/replica.drift').readAsStringSync();
      for (final days in ['timelineDays', 'timelineAddedDays']) {
        final sql = RegExp(
          '^$days(?:\\(.*?\\))?:(.*?);',
          multiLine: true,
          dotAll: true,
        ).firstMatch(drift)![1]!;
        // Every tile's days, less the part that runs for one backup state.
        final all = sql
            .split('UNION ALL')
            .where((part) => !part.contains(':backup IS NOT NULL'))
            .join('UNION ALL');
        expect(
          await plan(
            all.replaceAll(':offset', '0').replaceAll(':backup', 'NULL'),
          ),
          isNot(contains('local_asset')),
          reason: '$days counts what the triggers counted, never every item',
        );
      }
    },
  );
}
