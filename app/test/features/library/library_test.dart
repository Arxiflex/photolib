import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photolib/features/library/library.dart';
import 'package:photolib/features/library/timeline/buckets.dart';
import 'package:photolib/features/library/timeline/pipeline.dart';
import 'package:photolib_data/photolib_data.dart';

void main() {
  late Replica db;
  setUp(() => db = Replica(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<void> add(int n, String taken, {int added = 0}) => db
      .into(db.localAsset)
      .insert(
        LocalAssetCompanion.insert(
          id: Uint8List(16)..[15] = n,
          source: 'folder',
          volume: const Value('/p'),
          sourceId: '$n',
          path: Value('$n.jpg'),
          size: n,
          mtime: 0,
          takenLocal: Value(taken),
          added: Value(added),
        ),
      );

  List<int> ids(List<Object?> items) => [
    for (final i in items) (i! as ThumbnailItem).id![15],
  ];

  test(
    'the device index by day taken, a page at a time, anew on a change',
    () async {
      for (var n = 1; n <= 5; n++) {
        await add(n, '2024-05-0${n % 3 + 1}T12:00:0$n');
      }
      final snapshots = libraryTimeline(db, pageSize: 2).asBroadcastStream();
      var (buckets, pages) = await snapshots.first;
      expect(buckets.days, [20240503, 20240502, 20240501]);
      expect(buckets.counts, [2, 2, 1]);
      expect(
        [for (var p = 0; p < 5; p++) pages[p] != null],
        [true, true, false, false, false],
        reason: 'the first page comes with the snapshot',
      );
      await pumpEventQueue();
      expect(ids([for (var p = 0; p < 5; p++) pages[p]]), [5, 2, 4, 1, 3]);
      expect(
        (pages[0]! as ThumbnailItem).uri,
        Uri.file('/p/5.jpg'),
        reason: 'the original, for the thumbnail pipeline',
      );

      final next = snapshots.first;
      await add(6, '2024-05-04T00:00:00');
      (buckets, pages) = await next;
      expect(buckets.days.first, 20240504);
      pages[0];
      await pumpEventQueue();
      expect(ids([pages[0]]), [6]);
    },
  );

  test('the timeline follows a scan, which commits a directory at a time, at '
      'most once a second, ending with what the scan left', () async {
    final snapshots = <TimelineBuckets>[];
    // From before the first, so that n snapshots a second apart fit.
    final took = Stopwatch()..start();
    final sub = libraryTimeline(db).listen((s) => snapshots.add(s.$1));
    addTearDown(sub.cancel);
    while (snapshots.isEmpty) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    for (var n = 1; n <= 50; n++) {
      await add(n, '2024-05-01T12:00:00');
    }
    while (snapshots.last.assets < 50) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(
      snapshots.length,
      lessThanOrEqualTo(1 + took.elapsed.inSeconds),
      reason: 'a snapshot of a large library costs more than a directory',
    );
  });

  test('by date added: days in the local time zone, newest first', () async {
    final now = DateTime(2024, 5, 3, 12).millisecondsSinceEpoch;
    const day = Duration.millisecondsPerDay;
    await add(1, '2020-01-01T00:00:00', added: now - day);
    await add(2, '2021-01-01T00:00:00', added: now);
    await add(3, '2019-01-01T00:00:00', added: now - day + 1);
    final (buckets, pages) = await libraryTimeline(db, added: true).first;
    expect(buckets.days, [20240503, 20240502]);
    expect(buckets.counts, [1, 2]);
    for (var p = 0; p < 3; p++) {
      pages[p];
    }
    await pumpEventQueue();
    expect(ids([for (var p = 0; p < 3; p++) pages[p]]), [2, 3, 1]);
  });

  test('an item knows when it was taken, and whether it is animated: as '
      'extraction or PhotoKit says, a GIF until one has', () async {
    final taken = DateTime.utc(2024, 5, 3, 12);
    for (final (n, path, mime, facets) in [
      (1, '1.gif', null, null),
      (2, '2.bin', 'image/gif', null),
      (3, '3.jpg', 'image/jpeg', null),
      (4, '4.webp', null, 'animated'),
      (5, '5.gif', null, ''),
      (6, '6.png', null, 'panorama'),
    ]) {
      await db
          .into(db.localAsset)
          .insert(
            LocalAssetCompanion.insert(
              id: Uint8List(16)..[15] = n,
              source: 'folder',
              volume: const Value('/p'),
              sourceId: '$n',
              path: Value(path),
              mime: Value(mime),
              facets: Value(facets),
              size: n,
              mtime: 0,
              takenUtc: Value(taken.millisecondsSinceEpoch + n),
            ),
          );
    }
    final (_, pages) = await libraryTimeline(db).first;
    final items = [for (var p = 0; p < 6; p++) pages[p]! as ThumbnailItem];
    expect(
      [for (final i in items) i.animated],
      [false, false, true, false, true, true],
    );
    expect(items.last.taken, taken.add(const Duration(milliseconds: 1)));
  });

  test("the server's photos join the device's, one tile each, in one backup "
      'state or all, anew as sync changes them', () async {
    await db.customStatement(
      'INSERT INTO library (id, owner_id, kind, privacy, access, state, txid) '
      "VALUES (x'01', x'09', 'managed', 'standard', 'rw', 'online', 1)",
    );
    Future<void> asset(int n, String taken) => db.customStatement(
      'INSERT INTO asset (id, library_id, owner_id, original_filename, source, '
      "media_kind, taken_local, created_at, txid) VALUES (?, x'01', x'09', "
      "'a.jpg', 'upload', 'image', ?, 0, 1)",
      [Uint8List(16)..[15] = n, taken],
    );
    await add(1, '2024-05-01T12:00:00');
    await add(2, '2024-05-02T12:00:00');
    await asset(11, '2024-05-01T12:00:00');
    await asset(12, '2024-05-03T12:00:00');
    await db.customStatement(
      'UPDATE local_asset SET asset_id = ? WHERE id = ?',
      [Uint8List(16)..[15] = 11, Uint8List(16)..[15] = 1],
    );
    Future<List<(int, Availability)>> tiles([Availability? backup]) async {
      final (buckets, pages) = await libraryTimeline(db, backup: backup).first;
      await pages.preload(0);
      return [
        for (var p = 0; p < buckets.assets; p++)
          switch (pages[p]! as ThumbnailItem) {
            final i => ((i.id ?? i.asset!)[15], i.backup),
          },
      ];
    }

    expect(await tiles(), [
      (12, Availability.cloudOnly),
      (2, Availability.notBackedUp),
      (1, Availability.backedUp),
    ]);
    expect(await tiles(Availability.cloudOnly), [(12, Availability.cloudOnly)]);
    expect(await tiles(Availability.backedUp), [(1, Availability.backedUp)]);
    expect(await tiles(Availability.notBackedUp), [
      (2, Availability.notBackedUp),
    ]);

    final snapshots = libraryTimeline(db).asBroadcastStream();
    await snapshots.first;
    final next = snapshots.first;
    await db.customUpdate(
      'UPDATE asset SET trashed_at = 1',
      updates: {db.asset},
    );
    final (buckets, _) = await next;
    expect(buckets.days, [20240502], reason: 'deleted in the library');
  });

  test('items are equal by content version, so thumbnails follow them', () {
    final a = ThumbnailItem('k', Uri.file('/a'));
    expect(a, ThumbnailItem('k', Uri.file('/b')));
    expect(a.hashCode, ThumbnailItem('k', Uri.file('/b')).hashCode);
    expect(a, isNot(ThumbnailItem('j', Uri.file('/a'))));
  });
}
