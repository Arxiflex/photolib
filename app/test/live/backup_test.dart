// The desktop app backs a folder of 10,000 photos up to a real photolibd:
// it signs in as the app does (OPAQUE through the kernel), a backup in a
// child process is killed half-way, and the app's own backup finishes it
// over the same session.
// main builds photolibd (untimed): setUpAll has 12 minutes whatever @Timeout
// says, which cargo may spend waiting on locks other checkouts share.
@Timeout(Duration(minutes: 30))
library;

import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photolib/core/replica.dart';
import 'package:photolib/features/backup/backup.dart';
import 'package:photolib/features/servers/servers.dart';
import 'package:photolib_api/photolib_api.dart';
import 'package:photolib_data/photolib_data.dart';
import 'package:photolib_data/src/backup_native.dart';
import 'package:photolib_harness/photolib_harness.dart';
import 'package:photolib_log/photolib_log.dart';

import '../support/photolibd.dart';
import '../support/pump_app.dart';

const _files = 10000;

void main() {
  HttpOverrides.global = null;
  final binary = Photolibd.build();
  late Photolibd photolibd;
  late Directory tmp;
  setUpAll(() async => photolibd = await Photolibd.start(binary));
  tearDownAll(() => photolibd.stop());
  setUp(() async => tmp = await Directory.systemTemp.createTemp('backup-'));
  tearDown(() => tmp.delete(recursive: true));

  Future<int> count(String where) async =>
      int.parse(await photolibd.sql('SELECT count(*) FROM uploads $where'));

  test("backs 10,000 folder items up resumably over the app's session, "
      'into a library made at the first, each file once', () async {
    final path = '${tmp.path}/replica.db';
    // In WAL mode, as the data isolate opens the replica.
    Replica open() => Replica(
      NativeDatabase(
        File(path),
        setup: (db) => db.execute('PRAGMA journal_mode = WAL'),
      ),
    );
    var db = open();
    final app = ProviderContainer(
      overrides: [
        serverStoreProvider.overrideWithValue(MemoryStore()),
        backupStoreProvider.overrideWithValue(MemoryStore()),
        replicaProvider.overrideWith((ref) async => db),
        backupSupportedProvider.overrideWithValue(true),
        deviceStateProvider.overrideWithValue(() async => anyDevice),
        runBackupProvider.overrideWithValue((
          db,
          config,
          selection,
          conditions, {
          instance,
        }) async {
          final server = Server(config, instance: instance);
          try {
            return await BackupEngine(
              db,
              server,
              hash: hashFile,
              read: readMedia,
            ).run(selection, conditions);
          } finally {
            server.close();
          }
        }),
      ],
    );
    addTearDown(app.dispose);

    // Signed in as the first administrator, as the app's server page does.
    final info = await Server(NetworkConfig(endpoints: [photolibd.url]))
        .selectEndpoint();
    final servers = app.read(accountsProvider.notifier);
    await app.read(accountsProvider.future);
    await servers.add(
      SavedServer(
        endpoints: [photolibd.url],
        instance: info.epoch.split('.').first,
      ),
    );
    await servers.setUp(
      photolibd.setupToken,
      User(handle: 'ann', displayName: 'Ann', email: 'ann@example.org'),
      'correct horse',
    );
    final session = app.read(serverProvider).value?.account?.token ?? '';
    expect(
      await photolibd.sql('SELECT count(*) FROM libraries'),
      '0',
      reason: 'the account has no library before its first backup',
    );

    // A folder the desktop app indexes: 10,000 photos in 100 sub-folders.
    final root = '${tmp.path}/Pictures';
    for (var n = 0; n < _files; n++) {
      File('$root/${n ~/ 100}/IMG_$n.jpg')
        ..createSync(recursive: true)
        ..writeAsStringSync('photo $n ' * (n % 50 + 1));
    }
    await addFolder(db, root);
    await FolderIndexer(db).scan(root);
    final folders = {for (final f in await backupFolders(db)) f.key: true};
    app
        .read(backupSettingsProvider.notifier)
        .edit((s) => s.copyWith(enabled: true, folders: folders));
    await db.close();

    // A backup over the app's session, eight files at once, killed once
    // photolibd holds 3,000 of the files.
    final child = await Process.start(
      '${Platform.environment['FLUTTER_ROOT']}/bin/dart',
      [
        ...['run', 'test/support/backup_child.dart', path],
        ...['${photolibd.url}', session, '8'],
      ],
      workingDirectory: 'packages/photolib_data',
    );
    addTearDown(child.kill);
    final said = [
      child.stdout,
      child.stderr,
    ].map((s) => s.transform(systemEncoding.decoder).join());
    final output = Future.wait(said).then((o) => o.join());
    var exited = false;
    unawaited(child.exitCode.then((_) => exited = true));
    while (await count('WHERE completed_at IS NOT NULL') < 3000) {
      expect(
        exited,
        isFalse,
        reason: await output.timeout(Duration.zero, onTimeout: () => ''),
      );
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    child.kill(ProcessSignal.sigkill);
    await child.exitCode;
    final before = await count('WHERE completed_at IS NOT NULL');
    expect(before, lessThan(_files));

    // The app backs up the rest; again, as its next run would, when a stop
    // of this process (SIGSTOP) timed a call out, three runs at most.
    db = open();
    addTearDown(db.close);
    final causes = <String>[];
    addTearDown(
      Log.records
          .where((r) => r.error != null)
          .listen((r) => causes.add(r.toJson()))
          .cancel,
    );
    var runs = 0;
    final run = await thawed(() {
      runs++;
      causes.clear();
      return app.read(backupProvider.notifier).run();
    }, again: (run) => run?.stopped == 'offline');
    expect(
      (run?.pending, run?.failed, run?.stopped),
      (0, 0, null),
      reason: causes.join('\n'),
    );
    final complete = await photolibd.sql(
      'SELECT count(*), count(DISTINCT hash), count(DISTINCT library_id) '
      'FROM uploads WHERE completed_at IS NOT NULL',
    );
    expect(complete, '$_files|$_files|1', reason: 'each file once');
    expect(
      await count(''),
      lessThanOrEqualTo(_files + 8 * runs),
      reason:
          'at most each of the eight uploads under way as the child died, or '
          'as a stop cut a run of the app, created unrecorded',
    );
    expect(
      await count('WHERE completed_at IS NULL AND received > 0'),
      0,
      reason: 'no byte goes before its upload is recorded',
    );
    expect(
      await photolibd.sql(
        'SELECT kind, name FROM libraries l JOIN users u ON u.id = l.owner_id '
        "WHERE u.handle = 'ann'",
      ),
      'managed|Photos',
    );
    expect(
      await photolibd.sql('SELECT pending FROM device_backups'),
      '0',
      reason: "the device's last pass reported to photolibd's watchdog",
    );
    final states = await db
        .customSelect(
          'SELECT state, count(*) AS n FROM backup_state GROUP BY 1',
        )
        .get();
    expect(
      {for (final s in states) s.read<String>('state'): s.read<int>('n')},
      {'backed_up': _files},
    );
  });
}
