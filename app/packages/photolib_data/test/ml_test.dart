@TestOn('vm')
library;

import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:photolib_data/photolib_data.dart';
import 'package:test/test.dart';

const _model = 'model@1';

/// A runner that answers each item with its number, and with nothing for
/// `broken` ones.
class _Runner {
  final calls = <List<int>>[];
  final broken = <int>{};
  Error? fail;
  void Function()? during;

  Future<List<Float32List?>> embed(List<LocalAssetData> items) async {
    calls.add([for (final a in items) a.id.last]);
    during?.call();
    if (fail case final error?) throw error;
    return [
      for (final a in items)
        if (broken.contains(a.id.last))
          null
        else
          Float32List.fromList([a.id.last.toDouble(), .5]),
    ];
  }
}

Uint8List _id(int n) => Uint8List(16)..[15] = n;

void main() {
  late Replica db;
  late _Runner runner;
  setUp(() {
    db = Replica(NativeDatabase.memory());
    runner = _Runner();
  });
  tearDown(() => db.close());

  // 2026-10-21, noon UTC.
  final now = DateTime.utc(2026, 10, 21, 12);
  MlIndexer indexer({
    bool backlog = true,
    String decoder = 'vips 8.15',
    Duration idle = const Duration(seconds: 5),
  }) {
    final i = MlIndexer(
      db,
      model: _model,
      rtFlags: 'ort 1.31.0 CPU fp32',
      embed: runner.embed,
      decoder: decoder,
      chunk: 2,
      backlog: backlog,
      idle: idle,
      clock: () => now,
    );
    addTearDown(i.stop);
    return i;
  }

  /// A file of the folder /r, taken [n] ms after the epoch.
  Future<void> add(
    int n, {
    String path = 'p.jpg',
    String? mime,
    String state = 'present',
    bool favorite = false,
    bool trashed = false,
    int? taken,
    DateTime? added,
  }) => db
      .into(db.localAsset)
      .insert(
        LocalAssetCompanion.insert(
          id: _id(n),
          source: 'folder',
          volume: const Value('/r'),
          sourceId: '$n',
          size: n,
          mtime: 1000 + n,
          path: Value('$n/$path'),
          mime: Value(mime),
          taken: Value(taken ?? n),
          added: Value(added?.millisecondsSinceEpoch),
          state: Value(state),
          favorite: Value(favorite ? 1 : 0),
          trashed: Value(trashed ? 1 : 0),
        ),
      );

  Future<(int, int, int)> progress([String? model = _model]) async {
    final p = await mlProgress(db, model).getSingle();
    return (p.total, p.done, p.failed);
  }

  test('the photos the library shows are indexed, favourites first, then '
      'newest first, each output kept with its model and runtime', () async {
    for (final n in [1, 2, 3, 4]) {
      await add(n);
    }
    await add(5, favorite: true);
    await add(6, path: 'v.mp4');
    await add(7, mime: 'video/mp4');
    await add(8, state: 'missing');
    await add(9, trashed: true);
    await add(10, mime: 'image/heic');

    await indexer().run();

    expect(runner.calls, [
      [5],
      [10, 4],
      [3, 2],
      [1],
    ]);
    final rows = await db.select(db.localMl).get();
    expect(rows, hasLength(6));
    final three = rows.firstWhere((r) => r.localAssetId.last == 3);
    expect(
      (three.model, three.size, three.mtime, three.rtFlags, three.failure),
      (_model, 3, 1003, 'ort 1.31.0 CPU fp32', null),
    );
    // Half floats, little-endian, as the server keeps them: 3.0 and 0.5.
    expect(three.vec, [0x00, 0x42, 0x00, 0x38]);
    expect(await progress(), (6, 6, 0));
  });

  test('thermal pressure pauses indexing once the chunk under way is stored; '
      'it resumes where it stopped', () async {
    for (var n = 1; n <= 6; n++) {
      await add(n);
    }
    final ml = indexer();
    runner.during = () {
      if (runner.calls.length == 2) ml.paused = true;
    };

    await ml.run();
    expect(runner.calls, [
      [6, 5],
      [4, 3],
    ]);
    expect(await progress(), (6, 4, 0));

    // Nothing runs while it is paused, whatever wakes it.
    await add(7);
    await ml.run();
    expect(runner.calls, hasLength(2));

    ml.paused = false;
    await ml.run();
    expect(runner.calls, [
      [6, 5],
      [4, 3],
      [7, 2],
      [1],
    ]);
    expect(await progress(), (7, 7, 0));
  });

  test('a new indexer goes on where a stopped one left off', () async {
    for (var n = 1; n <= 4; n++) {
      await add(n);
    }
    final first = indexer();
    runner.during = () => unawaited(first.stop());
    await first.run();
    expect(runner.calls, [
      [4, 3],
    ]);

    runner.during = null;
    await indexer().run();
    expect(runner.calls, [
      [4, 3],
      [2, 1],
    ]);
  });

  test('an unreadable photo is kept as failed until its file changes, when it '
      'is indexed again', () async {
    await add(1);
    await add(2);
    runner.broken.add(1);
    final ml = indexer();
    await ml.run();
    expect(
      [
        for (final r in await db.select(db.localMl).get())
          (r.localAssetId.last, r.vec != null, r.failure),
      ],
      [(2, true, null), (1, false, 'unreadable by vips 8.15')],
    );
    expect(await progress(), (2, 2, 1));

    await ml.run();
    expect(runner.calls, hasLength(1));

    runner.broken.clear();
    await (db.update(db.localAsset)..where((a) => a.id.equals(_id(1)))).write(
      const LocalAssetCompanion(mtime: Value(5)),
    );
    await ml.run();
    expect(runner.calls.last, [1]);
    expect(await progress(), (2, 2, 0));
  });

  test('a photo that could not be read is read again by another decoder, and '
      'listed with why until then', () async {
    await add(1, path: 'broken.dng');
    await add(2);
    runner.broken.add(1);
    await indexer().run();
    final failed = await mlFailures(db, null).get();
    expect(
      [for (final f in failed) (f.a.path, f.failure)],
      [('1/broken.dng', 'unreadable by vips 8.15')],
    );

    await indexer().run();
    expect(runner.calls, hasLength(1), reason: 'the same decoder');

    runner.broken.clear();
    await indexer(decoder: 'vips 8.16').run();
    expect(runner.calls.last, [1]);
    expect(await mlFailures(db, null).get(), isEmpty);
  });

  test('new captures come first, then favourites, then the last 12 months, '
      'then the rest; without the backlog only new captures', () async {
    final day = now.millisecondsSinceEpoch;
    await add(1, taken: day - 400 * 86400000);
    await add(2, taken: day - 300 * 86400000);
    await add(3, taken: day - 500 * 86400000, favorite: true);
    await add(4, taken: day - 600 * 86400000, added: now);
    await add(
      5,
      taken: day - 30 * 86400000,
      added: now.subtract(const Duration(hours: 25)),
    );
    await add(6, taken: day - 700 * 86400000);

    await indexer(backlog: false).run();
    expect(runner.calls, [
      [4],
    ]);

    await indexer().run();
    expect(runner.calls, [
      [4],
      [3],
      [5, 2],
      [1, 6],
    ]);
  });

  test('the user scrolling or editing holds the next chunk until 5 s after '
      'the last of it', () async {
    for (var n = 1; n <= 4; n++) {
      await add(n);
    }
    final ml = indexer(idle: const Duration(milliseconds: 300));
    final since = Stopwatch();
    int? held;
    runner.during = () {
      if (runner.calls.length == 1) {
        ml.interacted();
        since.start();
      } else {
        held ??= since.elapsedMilliseconds;
      }
    };
    await ml.run();
    expect(runner.calls, [
      [4, 3],
    ]);
    await expectLater(
      mlProgress(db, _model).watchSingle().map((p) => p.done),
      emitsThrough(4),
    );
    expect(held, greaterThanOrEqualTo(300));
    expect(runner.calls, [
      [4, 3],
      [2, 1],
    ]);
  }, tags: 'alone');

  test('a runner that fails ends the pass with nothing stored; the next pass '
      'tries again', () async {
    await add(1);
    runner.fail = StateError('the runtime died');
    final ml = indexer();
    await ml.run();
    expect(await progress(), (1, 0, 0));

    runner.fail = null;
    await ml.run();
    expect(await progress(), (1, 1, 0));
  });

  test('progress is of the model given, or of the model run last', () async {
    await add(1);
    await add(2);
    expect(await progress(null), (2, 0, 0));
    await indexer().run();
    expect(await progress(null), (2, 2, 0));
    await MlIndexer(
      db,
      model: 'other@1',
      rtFlags: '',
      embed: (items) async => [null],
      chunk: 1,
    ).run();

    expect(await progress(null), (2, 2, 2));
    expect(await progress(), (2, 2, 0));
  });

  test('progress counts as search finds photos, whatever is inserted, '
      'replaced, changed, deleted or hidden', () async {
    final random = Random(26);
    T any<T>(List<T> of) => of[random.nextInt(of.length)];
    for (final (id, path) in [(1, 'a/'), (2, 'b/')]) {
      await db
          .into(db.deviceFolder)
          .insert(
            DeviceFolderCompanion.insert(
              id: Value(id),
              volume: 'v',
              path: path,
            ),
          );
    }
    // Mostly photos, a video by its mime type or, without one, its path.
    String? path() => random.nextInt(4) > 0
        ? any([null, 'a.jpg', 'b.HEIC', 'c.mov.jpg'])
        : any([
            'd.jpg.mov',
            for (final e in videoExtensions) 'v.${e.toUpperCase()}',
          ]);
    LocalAssetCompanion item() => LocalAssetCompanion(
      state: Value(any(['present', 'present', 'present', 'missing'])),
      trashed: Value(any([0, 0, 0, 1])),
      folder: Value(any([0, 1, 2])),
      size: Value(any([1, 1, 2])),
      mtime: Value(any([1, 1, 2])),
      mime: Value(
        any([null, '', 'image/jpeg', 'image/heic', 'video/mp4', 'Video/qt']),
      ),
      path: Value(path()),
    );
    Future<(int, int, int)> expected(String? given) async {
      final last = await db
          .customSelect('SELECT model FROM local_ml ORDER BY rowid DESC')
          .get();
      final model = given ?? last.firstOrNull?.read<String>('model');
      final hidden = {
        for (final r
            in await db.customSelect('SELECT id FROM hidden_folder').get())
          r.read<int>('id'),
      };
      final photos =
          await (db.select(db.localAsset)..where(
                (a) =>
                    a.state.equals('present') &
                    a.trashed.equals(0) &
                    videoOf(a).not(),
              ))
              .get();
      final read = {
        for (final m in await db.select(db.localMl).get())
          if (m.model == model) m.localAssetId.last: m,
      };
      var (total, done, failed) = (0, 0, 0);
      for (final a in photos.where((a) => !hidden.contains(a.folder))) {
        total++;
        if (read[a.id.last] case final m?
            when m.size == a.size && m.mtime == a.mtime) {
          done++;
          if (m.failure != null) failed++;
        }
      }
      return (total, done, failed);
    }

    for (var step = 0; step < 800; step++) {
      final n = random.nextInt(32);
      final asset = db.localAsset.id.equals(_id(n));
      final ml = db.localMl.localAssetId.equals(_id(n));
      switch (random.nextInt(12)) {
        case 0 || 1 || 2:
          await db
              .into(db.localAsset)
              .insert(
                item().copyWith(
                  id: Value(_id(n)),
                  source: const Value('folder'),
                  sourceId: Value('$n'),
                ),
                mode: InsertMode.insertOrIgnore,
              );
        case 3 || 4:
          await (db.update(db.localAsset)..where((_) => asset)).write(item());
        case 5:
          await (db.delete(db.localAsset)..where((_) => asset)).go();
        case 6 || 7 || 8:
          await db
              .into(db.localMl)
              .insert(
                LocalMlCompanion.insert(
                  localAssetId: _id(n),
                  model: any(['a@1', 'b@1']),
                  size: any([1, 1, 2]),
                  mtime: any([1, 1, 2]),
                  failure: Value(any([null, 'x'])),
                  rtFlags: '',
                ),
                mode: InsertMode.insertOrReplace,
              );
        case 9:
          await (db.update(db.localMl)..where((_) => ml)).write(
            LocalMlCompanion(
              size: Value(any([1, 2])),
              failure: Value(any([null, 'x'])),
            ),
          );
        case 10:
          await (db.delete(
            db.localMl,
          )..where((m) => ml & m.model.equals(any(['a@1', 'b@1'])))).go();
        case _:
          await show(db, 'v', any(['a/', 'b/']), shown: random.nextBool());
      }
      for (final model in ['a@1', 'b@1', null]) {
        final p = await mlProgress(db, model).getSingle();
        expect(
          (p.total, p.done, p.failed),
          await expected(model),
          reason: 'step $step, $model',
        );
      }
    }
  });

  test('started, it indexes what the device index adds', () async {
    indexer().start();
    await add(1);
    await expectLater(
      mlProgress(db, _model).watchSingle().map((p) => p.done),
      emitsThrough(1),
    );
  });

  test('an indexer of text keeps what it reads with a folded copy to search, '
      'and a picture it cannot read as failed', () async {
    for (final n in [1, 2, 3]) {
      await add(n);
    }
    final reads = <List<int>>[];
    final i = MlIndexer.text(
      db,
      model: ocrModel,
      rtFlags: 'ort 1.31.0 CPU fp32',
      read: (items) async {
        reads.add([for (final a in items) a.id.last]);
        return [
          for (final a in items)
            switch (a.id.last) {
              1 => 'Lisboa Estação',
              2 => 'Красная ПЛОЩАДЬ',
              _ => null,
            },
        ];
      },
      decoder: 'vips 8.15',
      chunk: 2,
      clock: () => now,
    );
    addTearDown(i.stop);
    await i.run();
    expect(reads, [
      [3, 2],
      [1],
    ]);
    final rows = {
      for (final r in await db.select(db.localMl).get()) r.localAssetId.last: r,
    };
    expect(rows[1]!.ocrText, 'Lisboa Estação');
    expect(rows[1]!.ocrFolded, 'lisboa estação');
    expect(rows[2]!.ocrFolded, 'красная площадь');
    expect(rows[1]!.vec, isNull);
    expect(
      (rows[3]!.ocrText, rows[3]!.failure),
      (null, 'unreadable by vips 8.15'),
    );
    expect(await progress(ocrModel), (3, 3, 1));
  });
}
