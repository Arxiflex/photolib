@TestOn('vm')
library;

import 'dart:async';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:photolib_data/photolib_data.dart';
import 'package:photolib_log/photolib_log.dart';
import 'package:test/test.dart';

/// Reads a file as the kernel would, by its path: `broken` ones cannot be read.
class _Files {
  final calls = <List<String>>[];
  final broken = <String>{};
  Completer<void>? gate;
  Exception? fail;
  void Function()? during;

  Future<List<LocalAssetCompanion?>> extract(
    List<MediaFile> files, {
    required bool visible,
  }) async {
    calls.add([for (final f in files) '${visible ? '!' : ''}${f.path}']);
    during?.call();
    await gate?.future;
    if (fail case final error?) throw error;
    return [
      for (final f in files)
        if (broken.contains(f.path))
          null
        else
          LocalAssetCompanion(
            takenLocal: Value('${f.root}/${f.path}'),
            width: const Value(640),
            height: const Value(480),
          ),
    ];
  }
}

Uint8List _id(int n) => Uint8List(16)..[15] = n;

void main() {
  late Replica db;
  late _Files files;
  setUp(() {
    db = Replica(NativeDatabase.memory());
    files = _Files();
  });
  tearDown(() => db.close());

  MetadataExtractor extractor({int chunk = 2}) {
    final e = MetadataExtractor(db, files.extract, chunk: chunk);
    addTearDown(e.stop);
    return e;
  }

  /// A file of the folder /r taken [taken] ms after the epoch, or modified then.
  Future<void> add(
    int n, {
    int? taken,
    String state = 'present',
    int? width,
    String source = 'folder',
  }) => db
      .into(db.localAsset)
      .insert(
        LocalAssetCompanion.insert(
          id: _id(n),
          source: source,
          volume: Value(source == 'folder' ? '/r' : 'external_primary'),
          sourceId: '$n',
          size: n,
          mtime: 1000 + n,
          path: Value(source == 'folder' ? 'd/$n.jpg' : 'DCIM/'),
          name: Value(source == 'folder' ? null : '$n.jpg'),
          taken: Value(taken),
          state: Value(state),
          width: Value(width),
        ),
      );

  Future<Map<int, String?>> extracted() async => {
    for (final a in await db.select(db.localAsset).get())
      a.id.last: a.extracted == null ? null : '${a.takenLocal}',
  };

  test('reads every waiting item newest first, a chunk at a time, and stores '
      'what it found', () async {
    await add(1, taken: 5000);
    await add(2);
    await add(3, taken: 3000);
    await add(4, state: 'missing');
    await add(5, taken: 2000);
    await (db.update(db.localAsset)..where((a) => a.id.equals(_id(5)))).write(
      const LocalAssetCompanion(extracted: Value(1)),
    );

    await extractor().run();

    expect(files.calls, [
      ['d/1.jpg', 'd/3.jpg'],
      ['d/2.jpg'],
    ]);
    expect(await extracted(), {
      1: '/r/d/1.jpg',
      2: '/r/d/2.jpg',
      3: '/r/d/3.jpg',
      4: null,
      5: 'null',
    });
  });

  test('reads MediaStore items under the root of their volume, and fills only '
      'what the platform left NULL', () async {
    await add(1, source: 'mediastore', width: 4000);
    await db
        .into(db.volumeCursor)
        .insert(
          VolumeCursorCompanion.insert(
            source: 'mediastore',
            volume: 'external_primary',
            installId: 'i',
            version: 'v',
            generation: 1,
            root: const Value('/storage/emulated/0'),
          ),
        );

    await extractor().run();

    final a = await db.select(db.localAsset).getSingle();
    expect(
      [a.takenLocal, a.width, a.height],
      ['/storage/emulated/0/DCIM/1.jpg', 4000, 480],
    );
  });

  test(
    'a file that changes while it is read waits for the next pass',
    () async {
      await add(1);
      files.during = () => db.customStatement(
        'UPDATE local_asset SET size = 9, extracted = NULL',
      );

      await extractor().run();
      expect(await extracted(), {1: null});

      files.during = null;
      await extractor().run();
      expect(await extracted(), {1: '/r/d/1.jpg'});
    },
  );

  test('a file that cannot be read waits for the next pass, without stopping '
      'this one', () async {
    await add(1, taken: 2);
    await add(2, taken: 1);
    files.broken.add('d/1.jpg');
    final e = extractor(chunk: 1);

    await e.run();
    expect(await extracted(), {1: null, 2: '/r/d/2.jpg'});

    files.broken.clear();
    await e.run();
    expect(await extracted(), {1: '/r/d/1.jpg', 2: anything});
    expect(files.calls, [
      ['d/1.jpg'],
      ['d/2.jpg'],
      ['d/1.jpg'],
    ]);
  });

  test(
    'a failed chunk ends the pass, leaves its items waiting and says why',
    () async {
      await add(1, taken: 2);
      await add(2, taken: 1);
      files.fail = Exception('no kernel');
      final heard = <LogRecord>[];
      addTearDown(Log.records.listen(heard.add).cancel);

      await extractor(chunk: 1).run();

      expect(files.calls, [
        ['d/1.jpg'],
      ]);
      expect(await extracted(), {1: null, 2: null});
      expect(
        [for (final r in heard) (r.logger, r.level, r.message, '${r.error}')],
        [
          (
            'photolib.extract',
            LogLevel.warning,
            'extraction failed',
            'Exception: no kernel',
          ),
        ],
      );
    },
  );

  test('visible items go first', () async {
    for (var n = 1; n <= 4; n++) {
      await add(n, taken: 10 - n);
    }
    final e = extractor(chunk: 1);
    files.gate = Completer();
    final done = e.run();
    await pumpEventQueue();

    e.prioritise([_id(4), _id(1), _id(9)]);
    files.gate!.complete();
    await done;

    expect(files.calls, [
      ['d/1.jpg'],
      ['!d/4.jpg'],
      ['d/2.jpg'],
      ['d/3.jpg'],
    ]);
  });

  test(
    'while the device is unhealthy only visible items are read, and the rest '
    'when it recovers',
    () async {
      await add(1, taken: 2);
      await add(2, taken: 1);
      final e = extractor()
        ..healthy = false
        ..start()
        ..prioritise([_id(2)]);
      await pumpEventQueue();
      expect(await extracted(), {1: null, 2: anything});

      e.healthy = true;
      await pumpEventQueue();
      expect(files.calls, [
        ['!d/2.jpg'],
        ['d/1.jpg'],
      ]);
      expect((await extracted())[1], isNotNull);
    },
  );

  test(
    'an item dated 2100 is read first, like any newer one, and kept',
    () async {
      await add(1, taken: 1700000000000);
      await add(2, taken: DateTime.utc(2100).millisecondsSinceEpoch);

      await extractor().run();

      expect(files.calls, [
        ['d/2.jpg', 'd/1.jpg'],
      ]);
      expect(await extracted(), {1: '/r/d/1.jpg', 2: '/r/d/2.jpg'});
    },
  );

  test('items indexed while it runs are read too', () async {
    await add(1);
    extractor().start();
    await pumpEventQueue();

    await add(2);
    await pumpEventQueue();

    expect(files.calls, [
      ['d/1.jpg'],
      ['d/2.jpg'],
    ]);
  });
}
