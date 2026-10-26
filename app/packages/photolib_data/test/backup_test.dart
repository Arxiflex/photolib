@TestOn('vm')
library;

import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:photolib_api/photolib_api.dart';
import 'package:photolib_api/testing.dart';
import 'package:photolib_data/photolib_data.dart';
import 'package:photolib_data/src/backup_native.dart';
import 'package:photolib_data/src/blake3.dart';
import 'package:photolib_data/testing.dart' show MemoryKeystore;
import 'package:photolib_log/photolib_log.dart';
import 'package:test/test.dart';

import 'kernel.dart';

void main() {
  final kernel = testKernel();
  late Directory tmp;
  late String root;
  late SyncServer photolibd;
  late Server server;
  late Replica db;
  var now = DateTime.utc(2026, 10, 21, 12);
  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('photolib-backup-');
    root = '${tmp.path}/Photos';
    photolibd = await SyncServer.start();
    server = Server(NetworkConfig(endpoints: [photolibd.url]));
    db = Replica(NativeDatabase.memory());
    now = DateTime.utc(2026, 10, 21, 12);
  });
  tearDown(() async {
    await db.close();
    server.close();
    await photolibd.close();
    await tmp.delete(recursive: true);
  });

  /// Writes [files], path to content, under the folder and indexes it.
  Future<void> folder(Map<String, String> files, {DateTime? modified}) async {
    for (final MapEntry(key: path, value: content) in files.entries) {
      final file = File('$root/$path')
        ..createSync(recursive: true)
        ..writeAsStringSync(content);
      if (modified != null) file.setLastModifiedSync(modified);
    }
    await addFolder(db, root);
    await FolderIndexer(db).scan(root);
  }

  /// Every folder in the library, backed up.
  Future<Map<String, bool>> everyFolder() async => {
    for (final f in await backupFolders(db)) f.key: true,
  };

  Future<BackupRunData> backUp([
    BackupSelection? selection,
    BackupConditions conditions = const BackupConditions(),
  ]) async => await BackupEngine(
    db,
    server,
    hash: hashFile,
    read: readMedia,
    now: () => now,
  ).run(selection ?? BackupSelection(folders: await everyFolder()), conditions);

  /// path → `state reason` of each item.
  Future<Map<String, String>> states() async => {
    for (final row
        in await db
            .customSelect(
              'SELECT a.path, b.state, b.reason FROM local_asset a '
              'JOIN backup_state b ON b.local_asset_id = a.id ORDER BY a.path',
            )
            .get())
      row.read<String>('path'):
          '${row.read<String>('state')} ${row.readNullable<String>('reason')}',
  };

  String hex(List<int> bytes) =>
      [for (final b in bytes) b.toRadixString(16).padLeft(2, '0')].join();

  test('backs a folder up: each item hashed with BLAKE3 and uploaded from its '
      "path into the account's destination, once", () async {
    await folder({'a.jpg': 'one', 'Trip/b.jpg': 'two', 'Trip/c.mp4': 'three'});
    final run = await backUp();
    expect(
      [
        for (final u in photolibd.uploads)
          (u.path, u.library, u.hash, String.fromCharCodes(u.bytes.toBytes())),
      ],
      unorderedEquals([
        ('a.jpg', null, hex(blake3('one'.codeUnits)), 'one'),
        ('Trip/b.jpg', null, hex(blake3('two'.codeUnits)), 'two'),
        ('Trip/c.mp4', null, hex(blake3('three'.codeUnits)), 'three'),
      ]),
    );
    expect(photolibd.uploads.every((u) => u.complete), isTrue);
    expect(await states(), {
      'Trip/b.jpg': 'backed_up null',
      'Trip/c.mp4': 'backed_up null',
      'a.jpg': 'backed_up null',
    });
    expect(
      (run.uploaded, run.linked, run.failed, run.pending, run.stopped),
      (3, 0, 0, 0, null),
    );
    expect(run.ended, now.millisecondsSinceEpoch);

    final again = await backUp();
    expect(photolibd.uploads, hasLength(3), reason: 'nothing twice');
    expect((again.uploaded, again.pending), (0, 0));
  });

  test('hashes as many files at once as it uploads, as each holds a file '
      'open', () async {
    await folder({for (var n = 0; n < 20; n++) '$n.jpg': 'photo $n'});
    var open = 0;
    var most = 0;
    final run =
        await BackupEngine(
          db,
          server,
          hash: (file) async {
            most = max(most, ++open);
            await Future<void>.delayed(const Duration(milliseconds: 10));
            open--;
            return await hashFile(file);
          },
          read: readMedia,
          parallel: 3,
        ).run(
          BackupSelection(folders: await everyFolder()),
          const BackupConditions(),
        );
    expect((run.uploaded, most), (20, 3));
  });

  test('backs up the folders, media types and dates chosen, and says why the '
      'rest waits', () async {
    await folder({
      'Old/a.jpg': 'old',
      'Trip/b.jpg': 'b',
      'Trip/c.mp4': 'c',
      'Trip/Day 2/d.jpg': 'd',
      'Junk/e.jpg': 'e',
    });
    File('$root/Old/a.jpg').setLastModifiedSync(DateTime.utc(2001));
    await FolderIndexer(db).scan(root);
    final keys = {
      for (final f in await backupFolders(db)) f.dir: (f.key, f.items),
    };
    expect(keys.map((dir, f) => MapEntry(dir, f.$2)), {
      'Junk/': 1,
      'Old/': 1,
      'Trip/': 2,
      'Trip/Day 2/': 1,
    });
    final run = await backUp(
      BackupSelection(
        folders: {
          keys['Old/']!.$1: true,
          keys['Trip/']!.$1: true,
          keys['Junk/']!.$1: false,
        },
        videos: false,
        since: DateTime.utc(2010).millisecondsSinceEpoch,
      ),
    );
    expect(await states(), {
      'Junk/e.jpg': 'discovered folder_excluded',
      'Old/a.jpg': 'discovered before_date',
      'Trip/Day 2/d.jpg': 'discovered folder_new',
      'Trip/b.jpg': 'backed_up null',
      'Trip/c.mp4': 'discovered type_excluded',
    });
    expect((run.uploaded, run.pending), (1, 0));

    await backUp(BackupSelection(folders: await everyFolder()));
    expect(photolibd.uploads.map((u) => u.path), hasLength(5));
    expect((await states()).values.toSet(), {'backed_up null'});
  });

  test(
    'pauses what the network may not carry, and sends it once it may',
    () async {
      await folder({
        'a.jpg': 'photo',
        'b.mp4': 'video',
        'c.jpg': 'a large photo',
      });
      final metered = await backUp(
        null,
        const BackupConditions(videos: false, cap: 10),
      );
      expect(await states(), {
        'a.jpg': 'backed_up null',
        'b.mp4': 'paused metered',
        'c.jpg': 'paused metered_cap',
      });
      expect(metered.pending, 2);
      final started = now.millisecondsSinceEpoch;
      expect(await watchBackupStatus(db).first, (
        completed: null,
        first: started,
        stopped: null,
        pending: 2,
        contact: null,
      ));
      now = now.add(const Duration(hours: 1));
      await backUp();
      expect((await states()).values.toSet(), {'backed_up null'});
      expect(await watchBackupStatus(db).first, (
        completed: now.millisecondsSinceEpoch,
        first: started,
        stopped: null,
        pending: 0,
        contact: null,
      ));
    },
  );

  test(
    'a video due for its retry waits for a network that may carry it too',
    () async {
      await folder({'a.mp4': 'a video', 'b.mp4': 'another'});
      photolibd.refuseUploads = ('invalid_argument', 'field.invalid');
      await backUp();
      now = now.add(const Duration(hours: 1));
      photolibd.refuseUploads = null;
      await backUp(null, const BackupConditions(videos: false));
      expect(photolibd.uploads, isEmpty);
      expect(await states(), {
        'a.mp4': 'paused metered',
        'b.mp4': 'paused metered',
      });
      await backUp();
      expect(photolibd.uploads, hasLength(2));
    },
  );

  test('sends nothing while the device may not, and says why', () async {
    await folder({'a.jpg': 'photo'});
    final run = await backUp(null, const BackupConditions(stop: 'charging'));
    expect(photolibd.uploads, isEmpty);
    expect((run.stopped, run.pending), ('charging', 1));
    expect(await states(), {'a.jpg': 'selected null'});
  });

  test('links what the server holds and a copy of what is backed up, sending '
      'neither', () async {
    await folder({'a.jpg': 'held', 'b.jpg': 'new'});
    photolibd.hashes[hex(blake3('held'.codeUnits))] =
        '0190a3c2-0000-7000-8000-000000000001';
    await backUp();
    await folder({'Copy/b.jpg': 'new'});
    final run = await backUp();
    expect(photolibd.uploads.map((u) => u.path), ['b.jpg']);
    expect(await states(), {
      'Copy/b.jpg': 'linked duplicate',
      'a.jpg': 'linked null',
      'b.jpg': 'backed_up null',
    });
    expect((run.linked, run.uploaded), (1, 0));
    final held = await (db.select(
      db.localAsset,
    )..where((a) => a.path.equals('a.jpg'))).getSingle();
    expect(held.assetId, hasLength(16));
  });

  test('a refused item waits an hour, then later and later; a file that '
      'cannot be read says so and goes again in a minute', () async {
    await folder({'a.jpg': 'refused', 'b.jpg': 'gone'});
    File('$root/b.jpg').deleteSync();
    photolibd.refuseUploads = ('invalid_argument', 'field.invalid');
    final run = await backUp();
    expect(await states(), {
      'a.jpg': 'failed field.invalid',
      'b.jpg': 'failed unreadable',
    });
    expect((run.failed, run.pending, run.stopped), (2, 2, null));
    Future<Map<String, int>> retries() async => {
      for (final row
          in await db
              .customSelect(
                'SELECT a.path, b.retry_at FROM local_asset a '
                'JOIN backup_state b ON b.local_asset_id = a.id',
              )
              .get())
        row.read<String>('path'):
            row.read<int>('retry_at') - now.millisecondsSinceEpoch,
    };
    const minute = 60000;
    const hour = 60 * minute;
    expect(await retries(), {'a.jpg': hour, 'b.jpg': minute});

    photolibd.refuseUploads = null;
    now = now.add(const Duration(minutes: 1));
    await backUp();
    expect(photolibd.uploads, isEmpty, reason: 'not yet');
    expect(await retries(), {'a.jpg': hour - minute, 'b.jpg': 2 * minute});
    now = now.add(const Duration(minutes: 59));
    photolibd.refuseUploads = ('invalid_argument', 'field.invalid');
    await backUp();
    expect((await retries())['a.jpg'], 2 * hour);
    now = now.add(const Duration(hours: 2));
    photolibd.refuseUploads = null;
    await backUp();
    expect(await states(), {
      'a.jpg': 'backed_up null',
      'b.jpg': 'failed unreadable',
    });
  });

  test(
    'an item dated 2100 backs up, and a refusal then waits its hour',
    () async {
      now = DateTime.utc(2100, 6);
      final since = DateTime.utc(2099).millisecondsSinceEpoch;
      await folder({'a.jpg': 'future'}, modified: DateTime.utc(2100));
      await backUp(BackupSelection(folders: await everyFolder(), since: since));
      await folder({'b.jpg': 'refused'}, modified: DateTime.utc(2100));
      photolibd.refuseUploads = ('invalid_argument', 'field.invalid');
      await backUp(BackupSelection(folders: await everyFolder(), since: since));
      expect(await states(), {
        'a.jpg': 'backed_up null',
        'b.jpg': 'failed field.invalid',
      });
      final failed = await (db.select(
        db.backupState,
      )..where((s) => s.state.equals('failed'))).getSingle();
      expect(failed.retryAt, now.millisecondsSinceEpoch + 3600000);
    },
  );

  test('an item refused for months still waits a day', () async {
    await folder({'a.jpg': 'refused'});
    photolibd.refuseUploads = ('invalid_argument', 'field.invalid');
    await backUp();
    await db.customStatement('UPDATE backup_state SET attempts = 64');
    now = now.add(const Duration(days: 1));
    await backUp();
    final failed = await db.select(db.backupState).getSingle();
    expect(failed.retryAt, now.millisecondsSinceEpoch + 24 * 3600000);
  });

  test('a full quota stops the run at the first refusal', () async {
    await folder({'a.jpg': 'a', 'b.jpg': 'b', 'c.jpg': 'c'});
    photolibd.refuseUploads = ('resource_exhausted', 'quota.exceeded');
    final run = await backUp();
    expect((run.stopped, run.failed, run.pending), ('quota.exceeded', 1, 3));
    expect((await states()).values.where((s) => s.startsWith('failed')), [
      'failed quota.exceeded',
    ]);
  });

  test('a revoked session stops the run and fails nothing', () async {
    await folder({'a.jpg': 'a'});
    photolibd.revoked = true;
    final run = await backUp();
    expect((run.stopped, run.failed), ('signed_out', 0));
    expect(await states(), {'a.jpg': 'selected null'});
  });

  test('killed during an upload, it loses no state, resumes that upload from '
      'what the server holds and sends no file twice', () async {
    final path = '${tmp.path}/replica.db';
    await db.close();
    db = Replica(NativeDatabase(File(path)));
    final big = List.filled(appendBytes + 4096, 7);
    for (var n = 0; n < 4; n++) {
      File('$root/big$n.mp4')
        ..createSync(recursive: true)
        ..writeAsBytesSync([n, ...big]);
    }
    await folder({for (var n = 0; n < 6; n++) 'small$n.jpg': 'small $n'});
    await db.close();

    // A child process backs up one file at a time; it dies as the second
    // append of its second large file arrives, which the server drops.
    final dart = '${Platform.environment['FLUTTER_ROOT']}/bin/dart';
    final child = await Process.start(dart, [
      'run',
      'test/support/backup_child.dart',
      path,
      '${photolibd.url}',
    ]);
    addTearDown(child.kill);
    unawaited(child.stderr.drain<void>());
    unawaited(child.stdout.drain<void>());
    var resumes = 0;
    StandInUpload? cut;
    photolibd.onAppend = (upload, offset) {
      if (offset == 0 || cut != null) return true;
      if (++resumes < 2) return true;
      cut = upload;
      child.kill(ProcessSignal.sigkill);
      return false;
    };
    expect(await child.exitCode, isNot(0));
    final before = photolibd.uploads.length;
    expect(cut!.bytes.length, appendBytes);

    db = Replica(NativeDatabase(File(path)));
    final offsets = <int>[];
    photolibd.onAppend = (upload, offset) {
      if (identical(upload, cut)) offsets.add(offset);
      return true;
    };
    final run = await backUp();
    expect(offsets, [appendBytes], reason: 'resumed where the server was');
    expect(photolibd.uploads, hasLength(10), reason: 'no upload twice');
    expect(run.uploaded, 10 - before + 1);
    final complete = {
      for (final u in photolibd.uploads)
        if (u.complete) u.hash: hex(blake3(u.bytes.toBytes())),
    };
    expect(complete.length, 10);
    complete.forEach((announced, got) => expect(got, announced));
    expect((await states()).values.toSet(), {'backed_up null'});
  }, timeout: const Timeout(Duration(minutes: 3)));

  test(
    'a second device with a library of 100,000 the server holds links '
    'them all, sending nothing, and its next run touches only what is '
    'new: under 1%',
    () async {
      await addFolder(db, root);
      final ids = <Uint8List>[];
      Uint8List hashOf(String path) => blake3(path.codeUnits);
      await db.batch((b) {
        for (var n = 0; n < 100000; n++) {
          final id = Uint8List(16)
            ..buffer.asByteData().setUint32(12, n)
            ..[6] = 0x70;
          ids.add(id);
          final path = 'DCIM/${n ~/ 1000}/IMG_$n.jpg';
          photolibd.hashes[hex(hashOf(path))] =
              '0190a3c2-0000-7000-8000-${n.toRadixString(16).padLeft(12, '0')}';
          b.insert(
            db.localAsset,
            LocalAssetCompanion.insert(
              id: id,
              source: 'folder',
              volume: Value(root),
              sourceId: '$n',
              size: n,
              mtime: n,
              path: Value(path),
            ),
          );
        }
      });
      var hashed = 0;
      Future<BackupRunData> run(Map<String, bool> folders) => BackupEngine(
        db,
        server,
        hash: (file) async {
          hashed++;
          return hashOf(file.path);
        },
        read: readMedia,
      ).run(BackupSelection(folders: folders), const BackupConditions());
      final folders = await everyFolder();
      final onboarding = await run(folders);
      expect((onboarding.linked, onboarding.uploaded), (100000, 0));
      expect(hashed, 100000);

      // 500 new photos, in a folder of their own; the device counts every row
      // its next run writes.
      for (var n = 0; n < 500; n++) {
        File('$root/New/$n.jpg')
          ..createSync(recursive: true)
          ..writeAsStringSync('new $n');
      }
      await FolderIndexer(db).scan(root);
      await db.customStatement('CREATE TEMP TABLE touched (id BLOB)');
      for (final table in ['backup_state', 'local_asset']) {
        final id = table == 'local_asset' ? 'id' : 'local_asset_id';
        await db.customStatement(
          'CREATE TEMP TRIGGER touched_$table AFTER UPDATE ON $table '
          'BEGIN INSERT INTO touched VALUES (new.$id); END',
        );
      }
      hashed = 0;
      final checked = photolibd.checked;
      final next = await run({...folders, ...await everyFolder()});
      final touched = await db
          .customSelect('SELECT COUNT(DISTINCT id) AS n FROM touched')
          .getSingle();
      expect((next.uploaded, next.linked, hashed), (500, 0, 500));
      expect(touched.read<int>('n'), 500, reason: '0.5% of 100,500');
      expect(photolibd.checked - checked, 500, reason: 'only the new asked');
    },
    tags: 'alone',
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test('a server out of reach stops the run, which the next resumes, and the '
      'log says why it was out of reach', () async {
    await folder({'a.jpg': 'a'});
    photolibd.unavailable.addAll(['CheckHashes', 'upload']);
    final heard = <LogRecord>[];
    addTearDown(Log.records.listen(heard.add).cancel);
    final run = await backUp();
    expect((run.stopped, run.failed), ('offline', 0));
    final ended = heard.singleWhere((r) => r.message == 'backup ended');
    expect(ended.error, isA<Unreachable>());
    photolibd.unavailable.clear();
    expect((await backUp()).uploaded, 1);
  });

  test('tells photolibd what waits after each pass that reaches it, as the '
      "run's log counts it (ADR-0234)", () async {
    await folder({'a.jpg': 'photo', 'b.mp4': 'video'});
    final metered = await backUp(null, const BackupConditions(videos: false));
    expect(metered.pending, 1);
    expect(photolibd.backupReports, [1]);
    await backUp(null, const BackupConditions(stop: 'charging'));
    photolibd.unavailable.add('upload');
    expect((await backUp()).stopped, 'offline');
    expect(photolibd.backupReports, [1], reason: 'neither reached it');

    photolibd.unavailable
      ..clear()
      ..add('ReportBackup');
    final unheard = await backUp();
    expect((unheard.uploaded, unheard.stopped), (1, null));
    photolibd.unavailable.clear();
    await backUp();
    expect(photolibd.backupReports, [1, 0]);
  });

  test('a file changed after its backup is sent again once a scan sees the '
      'change', () async {
    await folder({'c.jpg': 'one'});
    await backUp();
    File('$root/c.jpg').writeAsStringSync('two!');
    await backUp();
    await FolderIndexer(db).scan(root);
    await backUp();
    expect(
      [
        for (final u in photolibd.uploads)
          if (u.path == 'c.jpg') String.fromCharCodes(u.bytes.toBytes()),
      ],
      ['one', 'two!'],
    );
  });

  test('backupReplica runs in the data isolate, hashing on a worker, into '
      "the account's destination", () async {
    final vault = Vault(
      location: '${tmp.path}/store',
      keystore: MemoryKeystore(),
      files: storeFiles('${tmp.path}/store'),
      keyring: kernel.keyring,
    );
    await vault.unlock();
    addTearDown(vault.lock);
    final ui = await vault.openReplica();
    File('$root/Trip/b.jpg')
      ..createSync(recursive: true)
      ..writeAsStringSync('two');
    await addFolder(ui, root);
    await FolderIndexer(ui).scan(root);
    final run = await backupReplica(
      ui,
      NetworkConfig(endpoints: [photolibd.url]),
      BackupSelection(
        folders: {for (final f in await backupFolders(ui)) f.key: true},
      ),
      const BackupConditions(),
    );
    expect(run.uploaded, 1);
    expect(
      [for (final u in photolibd.uploads) (u.library, u.path, u.hash)],
      [(null, 'Trip/b.jpg', hex(blake3('two'.codeUnits)))],
    );
  });
}
