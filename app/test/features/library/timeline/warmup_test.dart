import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photolib/features/library/timeline/pipeline.dart';
import 'package:photolib/features/library/timeline/thumbnails.dart';
import 'package:photolib/features/library/timeline/warmup.dart';
import 'package:photolib_data/photolib_data.dart';

void main() {
  final warming = <String, Completer<Uint8List?>>{};
  Future<Uint8List?> warm(ThumbnailItem item) =>
      (warming[item.key] = Completer()).future;
  ThumbnailItem item(String key) => ThumbnailItem(
    key,
    Uri.file('/$key'),
    id: Uint8List.fromList(key.codeUnits),
  );
  setUp(warming.clear);

  test('warms [workers] tiles at once, pausing while the timeline is busy or '
      'scrolled and resuming once it is idle, and counts them', () async {
    final busy = ValueNotifier(false);
    final warmup = Warmup(warm, busy, workers: 2)
      ..add([for (final k in 'abcde'.split('')) item(k)]);
    await pumpEventQueue();
    expect(warming.keys, ['a', 'b']);
    expect(warmup.progress.value, (0, 5));
    busy.value = true;
    warming['a']!.complete(null);
    await pumpEventQueue();
    expect(warming.keys, ['a', 'b'], reason: 'paused');
    expect((warmup.pending, warmup.progress.value), (3, (1, 5)));
    busy.value = false;
    await pumpEventQueue();
    expect(warming.keys, ['a', 'b', 'c'], reason: 'resumed');
    warming['b']!.completeError(StateError('unreadable'));
    await pumpEventQueue();
    expect(warming.keys, ['a', 'b', 'c', 'd'], reason: 'a failure is no stop');
    for (final k in 'cde'.split('')) {
      warming[k]!.complete(null);
      await pumpEventQueue();
    }
    expect((warmup.pending, warmup.progress.value), (0, (0, 0)));
    warmup.dispose();
  });

  test('keeps the ThumbHashes it computes, a batch at a time', () async {
    final saved = <Map<Uint8List, Uint8List>>[];
    final warmup = Warmup(
      (item) async => item.key == 'b' ? null : Uint8List.fromList([7]),
      ValueNotifier(false),
      workers: 3,
      save: (hashes) async => saved.add(hashes),
    )..add([for (var n = 0; n < 300; n++) item('$n'), item('b')]);
    await pumpEventQueue(times: 100);
    expect([for (final batch in saved) batch.length], [256, 44]);
    expect(saved.last.values.last, [7]);
    expect(
      String.fromCharCodes(saved.last.keys.last),
      '299',
      reason: 'not b, which had one',
    );
    warmup.dispose();
  });

  test('once its queue drains, sums up what it warmed and why each of the '
      'rest has no tile, videos first', () async {
    final busy = ValueNotifier(false);
    final reports = <String>[];
    ThumbnailItem file(String name, {bool video = false}) =>
        ThumbnailItem(name, Uri.file('/p/$name'), video: video);
    final misses = {
      'a.mp4': const NoThumbnail(
        video: true,
        cause:
            'macos: refused a.mp4: AVFoundationErrorDomain -11829; '
            'vips: video',
      ),
      'b.mov': const NoThumbnail(video: true, cause: 'macos: cancelled b.mov'),
      'c.heic': StateError('corrupt'),
    };
    final warmup = Warmup(
      (item) async {
        if (misses[item.key] case final miss?) throw miss;
        return null;
      },
      busy,
      report: reports.add,
    );
    warmup.add([
      for (var i = 0; i < 1204; i++) file('$i.jpg'),
      file('a.mp4', video: true),
      file('b.mov', video: true),
      file('c.heic'),
    ]);
    await pumpEventQueue(times: 5000);
    expect(reports, [
      'warmed 1,204 of 1,207; 2 videos without a poster: '
          'a.mp4 (macos: refused a.mp4: AVFoundationErrorDomain -11829; '
          'vips: video) | b.mov (macos: cancelled b.mov); '
          '1 photo without a tile: c.heic (Bad state: corrupt)',
    ]);
    warmup.add([file('d.jpg')]);
    await pumpEventQueue();
    expect(reports.last, 'warmed 1 of 1', reason: 'each scan its own');
    warmup.dispose();
  });

  test('an item added while it waits is warmed once, and again once added '
      'after', () async {
    final warmup = Warmup(warm, ValueNotifier(false))
      ..add([item('a'), item('b')])
      ..add([item('b'), item('c')]);
    expect(warmup.progress.value, (0, 3));
    for (final k in 'abc'.split('')) {
      await pumpEventQueue();
      warming[k]!.complete(null);
    }
    await pumpEventQueue();
    expect(warming.keys, ['a', 'b', 'c']);
    warmup.add([item('a')]);
    expect(warmup.progress.value, (0, 1));
    warmup.dispose();
  });

  /// The folder [root] in [into], else a new replica, with its photos 1.jpg
  /// to [n].jpg a day apart, those of [hashed] with a ThumbHash.
  Future<Replica> folder(
    int n, {
    String root = '/p',
    Replica? into,
    Set<int> hashed = const {},
  }) async {
    final db = into ?? Replica(NativeDatabase.memory());
    if (into == null) addTearDown(db.close);
    await addFolder(db, root);
    for (var i = 1; i <= n; i++) {
      await db
          .into(db.localAsset)
          .insert(
            LocalAssetCompanion.insert(
              id: Uint8List(16)
                ..[0] = root.codeUnitAt(1)
                ..[15] = i,
              source: 'folder',
              volume: Value(root),
              sourceId: '$i',
              path: Value('$i.jpg'),
              size: 1,
              mtime: 0,
              takenLocal: Value('2024-05-0${i}T10:00:00'),
              thumbhash: Value(hashed.contains(i) ? Uint8List(5) : null),
            ),
          );
    }
    return db;
  }

  List<List<String>> paths(List<List<ThumbnailItem>> added) => [
    for (final page in added) [for (final i in page) i.uri.path],
  ];

  test('at start, warms the items of the folders not being scanned that have '
      'no ThumbHash, as those indexed before schema 8, newest first', () async {
    final db = await folder(4, hashed: {2});
    await folder(1, root: '/q', into: db);
    await (db.update(db.mediaSource)..where((s) => s.root.equals('/p'))).write(
      const MediaSourceCompanion(state: Value('online')),
    );
    final added = <List<ThumbnailItem>>[];
    final scans = warmScans(db, added.add, page: 2);
    addTearDown(scans.cancel);
    await pumpEventQueue(times: 100);
    expect(paths(added), [
      ['/p/4.jpg', '/p/3.jpg'],
      ['/p/1.jpg'],
    ], reason: '/q, still scanning, is warmed once its scan ends');
  });

  test('warms a folder once its scan ends, newest first', () async {
    final db = await folder(3);
    final added = <List<ThumbnailItem>>[];
    final scans = warmScans(db, added.add, page: 2);
    addTearDown(scans.cancel);
    await pumpEventQueue();
    expect(added, isEmpty, reason: 'still scanning');
    await (db.update(db.mediaSource)..where((s) => s.root.equals('/p'))).write(
      const MediaSourceCompanion(state: Value('online')),
    );
    await pumpEventQueue(times: 100);
    expect(paths(added), [
      ['/p/3.jpg', '/p/2.jpg'],
      ['/p/1.jpg'],
    ]);
  });
}
