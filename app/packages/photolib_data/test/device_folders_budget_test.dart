@TestOn('vm')
@Tags(['alone'])
library;

import 'dart:async';
import 'dart:math';

import 'package:drift/native.dart';
import 'package:photolib_data/photolib_data.dart';
import 'package:test/test.dart';

/// docs/10 §2's budgets for the timeline of device folders (ADR-0210) under
/// the source tree (ADR-0290), fastest of several rounds, as a loaded machine
/// stalls any one.
void main() {
  late Replica db;
  setUp(() => db = Replica(NativeDatabase.memory()));
  tearDown(() => db.close());

  /// [n] MediaStore items, one every eight minutes back from 2025, in 50
  /// folders: ten under `Sub/A/B/` hold every [first]th item, the others
  /// `Top<i>/Folder<i>/`.
  Future<void> library(int n, {int first = 50}) async {
    await db.customStatement(
      'WITH RECURSIVE f(i) AS (SELECT 1 UNION ALL SELECT i + 1 FROM f '
      'WHERE i < 50) INSERT INTO device_folder (id, volume, path) '
      "SELECT i, 'external_primary', IIF(i <= 10, 'Sub/A/B/F' || i, "
      "'Top' || (i % 5) || '/Folder' || i) || '/' FROM f",
    );
    await db.customStatement(
      'WITH RECURSIVE n(i) AS (SELECT 0 UNION ALL SELECT i + 1 FROM n '
      'WHERE i < ?1 - 1) INSERT INTO local_asset '
      '(id, source, volume, source_id, size, mtime, taken, folder) '
      "SELECT randomblob(16), 'mediastore', 'external_primary', i, 1, 0, "
      '1735689600000 - i * 480000, '
      'IIF(i % ?2 = 0, 1 + i / ?2 % 10, 11 + i % 40) FROM n',
      [n, first],
    );
  }

  Future<int> fastest(int rounds, Future<void> Function() run) async {
    var best = 1 << 30;
    for (var i = 0; i < rounds; i++) {
      final watch = Stopwatch()..start();
      await run();
      best = min(best, watch.elapsedMilliseconds);
    }
    return best;
  }

  test("the timeline's day counts at 1M items, folders out above and below "
      'those shown, within 50 ms, by date taken and by date added', () async {
    await library(1000000, first: 10);
    await show(db, 'external_primary', 'Sub/', shown: false);
    await show(db, 'external_primary', 'Sub/A/B/F1/', shown: true);
    for (final top in ['Top1/', 'Top2/Folder12/']) {
      await show(db, 'external_primary', top, shown: false);
    }
    // The first index saw 900k items within a minute; the newest 100k came
    // after it, each added as it was taken, in a quarter hour and folder of
    // its own. Days at UTC+5:30.
    await db.customStatement(
      'UPDATE local_asset SET added = IIF(taken >= ?1, taken, '
      '?1 - 60000 + taken % 60000)',
      [1735689600000 - 100000 * 480000],
    );
    for (final (name, query) in [
      ('taken', () => db.timelineDays(false, null).get()),
      ('added', () => db.timelineAddedDays(19800000, false, null).get()),
    ]) {
      late List<dynamic> days;
      final ms = await fastest(7, () async {
        days = await query();
      });
      // ignore: avoid_print, for the gate's log
      print('day counts of 1M items by date $name: $ms ms');
      final count = days.fold(0, (n, d) => n + (d.count as int));
      expect(count, lessThan(1000000 * 0.85));
      expect(ms, lessThan(50), reason: 'by date $name');
    }
  }, timeout: const Timeout(Duration(minutes: 5)));

  test("Settings' indexing progress at 1M items, folders out, within docs/10's "
      '16 ms for a UI query', () async {
    await library(1000000);
    await show(db, 'external_primary', 'Top1/', shown: false);
    // Every 7th a video; every other one read, every 10th a failure, every
    // 6th of a version of its file that changed since.
    await db.customStatement(
      "UPDATE local_asset SET mime = 'video/mp4' WHERE source_id % 7 = 0",
    );
    await db.customStatement(
      'INSERT INTO local_ml (local_asset_id, model, size, mtime, failure, '
      "rt_flags) SELECT id, 'm@1', size + (source_id % 6 = 0), mtime, "
      "IIF(source_id % 10 = 0, 'unreadable', NULL), 'cpu' FROM local_asset "
      'WHERE source_id % 2 = 0',
    );
    final [expected] = await db
        .customSelect(
          'SELECT COUNT(*), COUNT(m.model), COUNT(m.failure) '
          'FROM local_asset a LEFT JOIN local_ml m ON m.local_asset_id = a.id '
          "AND m.model = 'm@1' "
          'AND m.size = a.size AND m.mtime = a.mtime WHERE a.trashed = 0 '
          "AND a.state = 'present' AND IFNULL(a.mime, '') NOT LIKE 'video/%' "
          'AND a.folder NOT IN (SELECT id FROM hidden_folder)',
        )
        .get();
    late MlProgressResult p;
    final ms = await fastest(7, () async {
      p = await mlProgress(db, null).getSingle();
    });
    // ignore: avoid_print, for the gate's log
    print('indexing progress of 1M items: $ms ms');
    expect([p.total, p.done, p.failed], expected.data.values);
    expect(p.total, lessThan(1000000 * 6 ~/ 7));
    expect(ms, lessThan(16));
  }, timeout: const Timeout(Duration(minutes: 5)));

  test("an eye three levels above a 50k-item subtree changes the timeline's "
      'counts and first page of a 200k-item index within 1 s', () async {
    await library(200000, first: 4);
    final first = await db.timelinePage(1 << 30, false, null, 128, 0).get();
    expect(first.where((i) => i.folder <= 10), isNotEmpty);
    final ms = await fastest(3, () async {
      for (final shown in [false, true]) {
        final changed = Completer<void>();
        final counts = db.timelineDays(false, null).watch().listen((days) {
          final n = days.fold(0, (n, d) => n + d.count);
          if (n == (shown ? 200000 : 150000)) changed.complete();
        });
        await show(db, 'external_primary', 'Sub/', shown: shown);
        await changed.future;
        await counts.cancel();
        final page = await db.timelinePage(1 << 30, false, null, 128, 0).get();
        expect(page.any((i) => i.folder <= 10), shown);
      }
    });
    // ignore: avoid_print, for the gate's log
    print('a 50k-item subtree out and in again: $ms ms');
    expect(ms, lessThan(2000), reason: 'out and in, under 1 s each');
  }, timeout: const Timeout(Duration(minutes: 5)));
}
