// The local store in browsers: `MOZ_HEADLESS=1 dart test -p chrome -p firefox
// -c dart2js -c dart2wasm test/web_test.dart` (the `web` part of
// tools/check.sh).
@TestOn('browser')
@Timeout(Duration(minutes: 5))
library;

import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:math';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/wasm.dart';
import 'package:photolib_data/browser.dart';
import 'package:photolib_data/photolib_data.dart';
import 'package:photolib_data/src/open_web.dart'
    show keyedConnection, openKeyed;
import 'package:photolib_data/testing.dart';
import 'package:photolib_harness/photolib_harness.dart';
import 'package:photolib_kernel/photolib_kernel_web.dart';
import 'package:photolib_log/photolib_log.dart';
import 'package:photolib_workers/photolib_workers.dart' show JobCancelled;
import 'package:sqlite3/wasm.dart';
import 'package:test/test.dart';
import 'package:web/web.dart' as web;

import 'web_folders.dart';

@JS('navigator.userAgent')
external String get _userAgent;

/// The schema of the next release.
class _Next extends Replica {
  _Next(super.executor, {super.openBackup});

  @override
  int get schemaVersion => super.schemaVersion + 1;

  @override
  Future<void> migrate(Migrator m, int from, int to) async {}
}

void main() {
  strict();
  late Uri assets;
  late Kernel kernel;
  late Vault vault;
  final key = Uint8List.fromList(List.generate(32, (i) => i));
  final mutation = OutboxCompanion.insert(
    mutationId: Uint8List(16),
    entity: 'album',
    entityId: Uint8List(16),
    mutation: Uint8List(1),
    createdAt: 1,
  );

  setUpAll(() async {
    final path = await spawnHybridUri('web_assets.dart').stream.first;
    assets = Uri.base.resolve('../$path');
    kernel = await Kernel.load(assets.resolve('photolib_kernel_wasm.js'));
  });
  setUp(() async {
    vault = Vault(
      location: assets.toString(),
      keystore: webKeystore(),
      files: storeFiles(''),
      keyring: kernel.keyring,
    );
    await vault.unlock();
  });
  tearDown(() => vault.erase());

  test('the offline store keeps sealed chunks in IndexedDB, within its budget, '
      'and finds them again after a reload', () async {
    final files = storeFiles('');
    Future<OfflineStore> open() =>
        OfflineStore.open(vault, files, budget: 5000, chunkSize: 1000);
    final bytes = Uint8List.fromList([for (var i = 0; i < 2500; i++) i % 251]);
    var store = await open();
    await store.putBytes('a', bytes);
    await expectLater(
      store.putBytes('b', Uint8List(4000)),
      throwsA(isA<BudgetExceeded>()),
    );
    expect(store.used, lessThanOrEqualTo(5000));
    expect(
      await store.read('a', start: 900, end: 2100),
      bytes.sublist(900, 2100),
    );
    // Reloaded: the listing finds the blob, and nothing stays in the clear.
    store = await open();
    expect(store.has('a'), isTrue);
    expect(await store.read('a'), bytes);
    for (final name in await files.list('offline/')) {
      expect(
        name,
        matches(RegExp(r'^offline/[0-9a-f]{32}/\d+\.\d+\.\d+\.\d+$')),
        reason: 'names are hashed',
      );
    }
    await store.retain({});
    expect(store.used, 0);
    expect(await files.list('offline/'), isEmpty);
  });

  test(
    'the replica conforms in OPFS, and persists there under its key',
    () async {
      expect(await probeReplica(await vault.openReplica()), expectedProbe);
      await vault.lock();
      expect(
        (await storedBytes('')).keys,
        contains('opfs:/photolib/replica/database'),
      );
      await vault.unlock();
      final db = await vault.openReplica();
      expect(await db.select(db.localAsset).get(), hasLength(3));
    },
  );

  test('IndexedDB, the fallback where OPFS is missing, conforms too', () async {
    final name = 'fallback-${Random().nextInt(1 << 30)}';
    final db = Replica(
      keyedConnection(assets.toString(), name, key, indexedDb: true),
    );
    expect(await probeReplica(db), expectedProbe);
    await db.close();
    expect(
      (await storedBytes('')).keys,
      contains(startsWith('indexeddb:photolib/$name/')),
    );
  });

  test('a migration backs the local-only data up '
      'into a database beside the replica', () async {
    final name = 'migrated-${Random().nextInt(1 << 30)}';
    final old = await openKeyed(assets.toString(), name, key);
    await old.into(old.outbox).insert(mutation);
    await old.close();

    final backups = <String>[];
    final next = _Next(
      keyedConnection(assets.toString(), name, key),
      openBackup: (suffix) => keyedConnection(
        assets.toString(),
        (backups..add('$name$suffix')).last,
        key,
      ),
    );
    await next.customSelect('SELECT 1').get();
    await next.close();

    expect(backups.single, startsWith('$name.before-v${next.schemaVersion}-'));
    final backup = Unmigrated(
      keyedConnection(assets.toString(), backups.single, key),
    );
    addTearDown(backup.close);
    expect(
      await backup.customSelect('SELECT * FROM outbox').get(),
      hasLength(1),
    );
  });

  test(
    'a replica that cannot be opened says why, and the next opening works',
    () async {
      final name = 'rekeyed-${Random().nextInt(1 << 30)}';
      await (await openKeyed(assets.toString(), name, key)).close();
      await expectLater(
        openKeyed(assets.toString(), name, Uint8List(32)),
        throwsA(predicate((e) => '$e'.contains('not a database'))),
      );
      await (await openKeyed(assets.toString(), name, key)).close();
    },
    timeout: const Timeout(Duration(minutes: 1)),
  );

  test('a replica closed under open transactions has its worker roll them '
      'back before it closes the database', () async {
    final name = 'abandoned-${Random().nextInt(1 << 30)}';
    final db = await openKeyed(assets.toString(), name, key);
    final (open, hold) = (Completer<void>(), Completer<void>());
    // The outer transaction waits behind the nested one (photolib-design#511).
    final transaction = db.transaction(() async {
      await db.into(db.outbox).insert(mutation);
      await db.transaction(() async {
        await db.customSelect('SELECT 1').get();
        open.complete();
        await hold.future;
      });
    });
    await open.future;
    await db.close();
    hold.complete();
    await expectLater(transaction, throwsA(anything));
    final again = await openKeyed(assets.toString(), name, key);
    addTearDown(again.close);
    expect(await again.select(again.outbox).get(), isEmpty);
  });

  test(
    'a database worker that cannot start fails the open, its error reaches '
    'the log with its cause, file, line and stack, and the next opening works',
    () async {
      final name = 'unstarted-${Random().nextInt(1 << 30)}';
      final logged = expectLater(
        Log.records.where((r) => r.message == 'database worker error').take(2),
        emitsInOrder([
          isA<LogRecord>()
              .having((r) => '${r.error}', 'error', contains('sqlite3mc.wasm'))
              .having(
                (r) => '${r.stackTrace}',
                'stack',
                matches(RegExp(r'drift_worker\.js:\d+:\d+')),
              ),
          isA<LogRecord>()
              .having((r) => r.error, 'error', 'the worker could not be loaded')
              .having(
                (r) => r.fields['uri'],
                'uri',
                '${assets}none/drift_worker.js',
              ),
        ]),
      );
      // A worker without its SQLite fails once it holds the database's lock.
      await expectLater(
        openKeyed('${assets}nowasm/', name, key),
        throwsA(predicate((e) => '$e'.contains('sqlite3mc.wasm'))),
      );
      await expectLater(
        openKeyed('${assets}none/', name, key),
        throwsA(predicate((e) => '$e'.contains('could not be loaded'))),
      );
      await (await openKeyed(assets.toString(), name, key)).close();
      await logged;
      expect(takeProblems(), hasLength(2));
    },
    timeout: const Timeout(Duration(minutes: 1)),
  );

  test('nothing Photolib stores in the browser holds plaintext: '
      'the replica and the cached files', () async {
    await storeMarkers(vault, await vault.openReplica());
    await vault.lock();
    expect(await markerHits(''), isEmpty);

    await storeFiles('').write('control', utf8.encode(markers.join()));
    expect((await markerHits('')).values.single, markers);
  });

  test('locking drops the keys and closes the replica; '
      'class B objects stay readable', () async {
    final db = await vault.openReplica();
    await vault.write('token', utf8.encode('refresh'), keyClass: KeyClass.b);
    await vault.write('thumbnail', utf8.encode('pixels'));
    await vault.lock();

    await expectLater(db.select(db.outbox).get(), throwsA(anything));
    await expectLater(vault.read('thumbnail'), throwsStateError);
    expect(
      utf8.decode((await vault.read('token', keyClass: KeyClass.b))!),
      'refresh',
    );
    await vault.unlock();
    expect(utf8.decode((await vault.read('thumbnail'))!), 'pixels');
  });

  test(
    'crypto-erase deletes the keystore keys, the lockbox and the databases',
    () async {
      final name = 'erased-${Random().nextInt(1 << 30)}';
      await vault.openReplica(name: name);
      await vault.erase();
      expect(await webKeystore().read('dev'), isNull);
      expect(await storeFiles('').read('lockbox'), isNull);
      expect(
        (await storedBytes('')).keys.where((path) => path.contains(name)),
        isEmpty,
      );
    },
  );

  test('only Chromium has File System Access to keep folders', () {
    expect(browserFolders != null, _chrome);
  });

  group('folders', testOn: 'chrome', () => folderTests(() => assets, key));

  group('posters', () {
    // MP4/H.264, WebM, an HEVC MOV, a motion photo's video and ProRes.
    const corpus = [
      'video/pixel.mp4',
      'video/vp9.webm',
      'video/iphone.mov',
      'compound/motion/PXL_20230514_100000000.MP.mp4',
      'video/prores.mov',
    ];
    late Map<Object?, Object?> twins;
    setUpAll(() async {
      twins =
          await spawnHybridUri('video_twins.dart', message: corpus).stream.first
              as Map;
    });
    Map<Object?, Object?> about(String name) => twins[name]! as Map;
    Future<web.File> twin(String name) async {
      final url = Uri.base.resolve('../${about(name)['file']}').toString();
      final blob = await (await web.window.fetch(url.toJS).toDart)
          .blob()
          .toDart;
      return web.File(
        [blob].toJS,
        name,
        web.FilePropertyBag(type: about(name)['type']! as String),
      );
    }

    // The size and mean luma of an encoded image.
    Future<(int, int, double)> measure(Uint8List bytes) async {
      final image = await web.window
          .createImageBitmap(web.Blob([bytes.toJS].toJS))
          .toDart;
      final (w, h) = (image.width, image.height);
      final canvas = web.OffscreenCanvas(w, h);
      final context =
          canvas.getContext('2d')! as web.OffscreenCanvasRenderingContext2D
            ..drawImage(image, 0, 0);
      final rgba = context.getImageData(0, 0, w, h).data.toDart;
      var luma = 0.0;
      for (var i = 0; i < rgba.length; i += 4) {
        luma += 0.2126 * rgba[i] + 0.7152 * rgba[i + 1] + 0.0722 * rgba[i + 2];
      }
      return (w, h, luma / (w * h));
    }

    test('a video gets a frame of its picture past a fade from black, '
        'its short side at the tier, never larger', () async {
      final poster = await browserPoster(await twin('fade'), 128);
      final (w, h, luma) = await measure(poster.bytes);
      expect((w, h), (228, 128));
      expect(luma, greaterThan(64));
      expect(poster.duration, const Duration(seconds: 3));
      final (fw, fh, _) = await measure(
        (await browserPoster(await twin('fade'), 1024)).bytes,
      );
      expect((fw, fh), (320, 180));
    });

    test('every corpus video gets a poster or is unplayable in this browser, '
        'with its duration', () async {
      final unplayable = <String>[];
      for (final path in corpus) {
        final record = about(path);
        final (width, height) = (
          (record['width']! as num).toInt(),
          (record['height']! as num).toInt(),
        );
        Duration? duration;
        try {
          final poster = await browserPoster(await twin(path), 128);
          final (w, h, luma) = await measure(poster.bytes);
          expect(min(w, h), 128, reason: path);
          expect(w / h, closeTo(width / height, 0.02), reason: path);
          expect(luma, greaterThan(32), reason: path);
          duration = poster.duration;
        } on Unplayable catch (e) {
          unplayable.add(path);
          duration = e.duration;
        }
        expect(
          duration?.inMilliseconds,
          closeTo(record['duration_ms']! as num, 50),
          reason: path,
        );
      }
      // HEVC plays where the platform decodes it: Firefox on Linux does,
      // Chrome there does not.
      expect(unplayable..remove('video/iphone.mov'), ['video/prores.mov']);
    });

    test(
      'a poster is kept sealed in the store, and found there after a reload',
      () async {
        final poster = await browserPoster(await twin('video/pixel.mp4'), 128);
        final cache = await VaultCache.open(vault);
        await cache.put('pixel-128', poster.bytes);
        await cache.close();
        expect(
          await (await VaultCache.open(vault)).get('pixel-128'),
          poster.bytes,
        );
      },
    );

    test(
      'a decode gives up when it is cancelled or takes longer than its timeout',
      () async {
        final file = await twin('video/pixel.mp4');
        await expectLater(
          browserPoster(file, 128, cancelled: Future.value()),
          throwsA(isA<JobCancelled>()),
        );
        await expectLater(
          browserPoster(file, 128, timeout: Duration.zero),
          throwsA(isA<TimeoutException>()),
        );
      },
    );
  });

  // The browsers' database runs in drift_worker.js, which tools/data/web.sh
  // compiles with dart2js for either build of the app; sqlite3mc's WebAssembly
  // build has ChaCha20 only, so it is held to absolute budgets (ADR-0090).
  test('the local store’s database and an unlock meet their budgets '
      'with ChaCha20 pages', () async {
    final sqlite3 = await WasmSqlite3.loadFromUrl(
      assets.resolve('sqlite3mc.wasm'),
    );
    sqlite3.registerVirtualFileSystem(InMemoryFileSystem(name: 'cost'));
    CommonDatabase open(String name, List<String> keying) {
      final db = sqlite3.open('/$name', vfs: 'multipleciphers-cost');
      keying.forEach(db.execute);
      return db;
    }

    final watch = Stopwatch()..start();
    final cost = databaseCost(
      open,
      await replicaSchema(WasmDatabase.inMemory(sqlite3)),
      assets: const int.fromEnvironment('assets', defaultValue: 30000),
      clock: () => watch.elapsedMicroseconds,
    );
    final unlock = unlockCost(kernel.keyring, open, ciphers['chacha20']!);
    // The measurements are the run's report.
    // ignore: avoid_print
    print(
      jsonEncode({
        'target': '$_userAgent dart2js',
        'ms': cost.ms,
        'overhead_percent': cost.overhead,
        ...unlock,
      }),
    );
    expect(brokenBudgets(cost.ms['chacha20']!), isEmpty);
    expect(unlock['unlock_ms'], lessThanOrEqualTo(600));
  }, testOn: 'dart2js');

  test('cached thumbnails are read within their budget', () async {
    final start = await storeOpenCost(vault, vault.openReplica);
    final thumbnails = await thumbnailCost(vault, storeFiles(''));
    const compiler = bool.fromEnvironment('dart.tool.dart2wasm')
        ? 'dart2wasm'
        : 'dart2js';
    // The measurements are the run's report.
    // ignore: avoid_print
    print(
      jsonEncode({
        'target': '$_userAgent $compiler',
        'store_open_ms': start,
        ...thumbnails,
      }),
    );
    expect(thumbnails['thumbnail_p95_ms'], lessThanOrEqualTo(12));
    expect(thumbnails['thumbnail_tiles_s'], greaterThanOrEqualTo(320));
  });
}

final bool _chrome = web.window.navigator.userAgent.contains('Chrome/');
