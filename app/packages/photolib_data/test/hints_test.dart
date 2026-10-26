// Real-time hints (design 05 §9): a device in the foreground syncs at each.
@TestOn('vm')
library;

import 'dart:async';

import 'package:drift/native.dart';
import 'package:photolib_api/photolib_api.dart';
import 'package:photolib_api/sync.dart' as pb;
import 'package:photolib_api/testing.dart';
import 'package:photolib_data/photolib_data.dart';
import 'package:test/test.dart';

import 'support/sync_rows.dart';

void main() {
  late SyncServer photolibd;
  late Server server;
  late Replica db;
  late Completer<void> stop;
  setUp(() async {
    photolibd = await SyncServer.start();
    photolibd.streams.addAll({
      for (final s in ['account', 'libraries', 'albums', 'tags', 'people'])
        s: [],
    });
    server = Server(NetworkConfig(endpoints: [photolibd.url]));
    db = Replica(NativeDatabase.memory());
    stop = Completer();
  });
  tearDown(() async {
    if (!stop.isCompleted) stop.complete();
    await db.close();
    server.close();
    await photolibd.close();
  });

  /// Tag [n] of Ann (100), as photolibd sends it.
  List<pb.Rows> tag(int n) => [
    rows('tags', [
      {'id': uuid(n), 'owner_id': uuid(100), 'name': 't$n', 'path': 't$n'},
    ]),
  ];

  Future<List<String>> tags() async => [
    for (final t in await db.select(db.tag).get()) t.name,
  ];

  /// Follows photolibd's hints into the replica until the test stops it.
  Future<void> follow() {
    final engine = SyncEngine(db, server);
    return followHints(
      server.hints,
      streams: engine.streams,
      sync: engine.run,
      stop: stop.future,
    );
  }

  test('a change reaches the replica within 2 s of its hint, after the first '
      'hint of the channel synced what changed while it was closed', () async {
    photolibd.streams['tags'] = [tag(1)];
    final following = follow();
    final synced = db
        .select(db.tag)
        .watch()
        .map((rows) => rows.length)
        .timeout(const Duration(seconds: 10));
    final counts = StreamIterator(synced);
    while (await counts.moveNext() && counts.current < 1) {}
    expect(await tags(), ['t1']);

    photolibd.streams['tags'] = [tag(1), tag(2)];
    final hinted = Stopwatch()..start();
    await photolibd.hint(['tags']);
    while (await counts.moveNext() && counts.current < 2) {}
    expect(hinted.elapsed, lessThan(const Duration(seconds: 2)));
    expect(await tags(), ['t1', 't2']);
    await counts.cancel();
    stop.complete();
    await following;
    expect(photolibd.follows, hasLength(1));
  }, tags: 'alone');

  test('a sync that opens streams opens the channel again with them', () async {
    photolibd.streams.addAll({
      'libraries': [
        [
          rows('libraries', [library(1)]),
        ],
      ],
      'assets/${uuid(1)}': [],
      'faces/${uuid(1)}': [],
    });
    final following = follow();
    while (photolibd.follows.length < 2) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    stop.complete();
    await following;
    const account = ['account', 'libraries', 'albums', 'tags', 'people'];
    expect(photolibd.follows, [
      account,
      [...account, 'assets/${uuid(1)}', 'faces/${uuid(1)}'],
    ]);
  });

  group('with channels the test opens', () {
    late List<StreamController<List<String>>> channels;
    late List<Duration> waits;
    late int syncs;
    late Future<void> Function() sync;
    setUp(() {
      (channels, waits, syncs) = ([], [], 0);
      sync = () async => syncs++;
    });

    /// Follows the channels that [open] gives, the ith for the ith attempt,
    /// recording its waits instead of waiting.
    Future<void> follow(Stream<List<String>> Function(int attempt) open) =>
        followHints(
          (streams) => open(channels.length + waits.length),
          streams: () async => {'account'},
          sync: () => sync(),
          stop: stop.future,
          wait: (delay) async => waits.add(delay),
        );

    Stream<List<String>> channel() =>
        (channels..add(StreamController())).last.stream;

    test('a lost channel opens again after 1 s, doubling to a minute, and a '
        'hint resets the wait', () async {
      final following = follow(
        (attempt) =>
            attempt < 8 ? Stream.error(Unreachable('down')) : channel(),
      );
      while (channels.isEmpty) {
        await pumpEventQueue();
      }
      channels.single
        ..add(['account'])
        ..addError(Unreachable('lost'));
      while (waits.length < 9) {
        await pumpEventQueue();
      }
      stop.complete();
      await following;
      expect(waits, [
        for (final s in [1, 2, 4, 8, 16, 32, 60, 60, 1]) Duration(seconds: s),
      ]);
      expect(syncs, 1);
    });

    test('hints that arrive during a sync fold into one more, and stopping '
        'closes the channel', () async {
      final release = Completer<void>();
      sync = () async {
        syncs++;
        if (syncs == 1) await release.future;
      };
      final following = follow((_) => channel());
      while (channels.isEmpty) {
        await pumpEventQueue();
      }
      final hints = channels.single..add(['account']);
      await pumpEventQueue();
      for (var i = 0; i < 3; i++) {
        hints.add(['account']);
      }
      await pumpEventQueue();
      release.complete();
      await pumpEventQueue();
      expect(syncs, 2);
      stop.complete();
      await following;
      expect(hints.hasListener, isFalse);
    });

    test('a sync that fails waits for the next hint', () async {
      sync = () async {
        if (++syncs < 3) {
          throw syncs == 1
              ? Unreachable('offline')
              : const FormatException('a broken batch');
        }
      };
      final following = follow((_) => channel());
      while (channels.isEmpty) {
        await pumpEventQueue();
      }
      for (var i = 0; i < 3; i++) {
        channels.single.add(['account']);
        await pumpEventQueue();
      }
      expect(syncs, 3);
      stop.complete();
      await following;
    });

    test('a revoked session ends following with its error', () async {
      final revoked = ServerError(
        'unauthenticated',
        ErrorDetail(code: 'auth.session_revoked'),
      );
      await expectLater(
        follow((_) => Stream.error(revoked)),
        throwsA(same(revoked)),
      );
      sync = () => throw revoked;
      final following = follow((_) => channel());
      while (channels.isEmpty) {
        await pumpEventQueue();
      }
      channels.single.add(['account']);
      await expectLater(following, throwsA(same(revoked)));
    });
  });
}
