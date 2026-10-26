import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show AppLifecycleListener;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photolib/core/replica.dart';
import 'package:photolib/features/backup/backup.dart' as backups;
import 'package:photolib/features/servers/servers.dart';
import 'package:photolib_api/photolib_api.dart';
import 'package:photolib_data/photolib_data.dart';
import 'package:photolib_log/photolib_log.dart';

/// Syncs [db] with the server [config] reaches as [instance]. Tests fake it.
typedef Sync = Future<void> Function(
  Replica db,
  NetworkConfig config,
  String instance,
);

/// [syncReplica], in the replica's data isolate, or its data worker in a
/// browser (ADR-0120).
final syncProvider = Provider<Sync?>(
  (ref) =>
      (db, config, instance) => syncReplica(db, config, instance: instance),
);

/// Backs the device up after a sync of [db] with the server [config] reaches
/// as [instance], signed in as [owner]. Tests fake it.
typedef Backup = Future<void> Function(
  Replica db,
  NetworkConfig config,
  String instance,
  String owner,
);

/// A run of the backup state machine (`BackupNotifier`, ADR-0226), on
/// desktops, whose folders the app indexes (ADR-0042).
final backupProvider = Provider<Backup?>(
  (ref) =>
      !kIsWeb &&
          const {
            TargetPlatform.linux,
            TargetPlatform.macOS,
            TargetPlatform.windows,
          }.contains(defaultTargetPlatform)
      ? (db, config, instance, owner) async {
          await ref.read(backups.backupProvider.notifier).run();
        }
      : null,
);

const _log = Logger('photolib.sync');

/// Keeps the replica of the account in use in sync with its server (ADR-0120,
/// ADR-0234), so the timeline shows what only the server has (ADR-0267), and
/// backs the folders up after each sync: at start, sign-in or a switch, on
/// every resume, then every five minutes while the app runs. Offline it tries
/// at the next; a revocation signs that account out. A renewed session starts
/// over with its new token. Signed out, the replica forgets what the server
/// sent: it belongs to one account (docs/10 §2).
final syncingProvider = Provider<void>((ref) {
  final (replica, token) = ref.watch(
    serverProvider.select((s) => (s.value?.replica, s.value?.account?.token)),
  );
  final db = replica == null ? null : replicaOf(ref, replica);
  final server = ref.read(serverProvider).value;
  if (db == null || server == null) return;
  if (token == null) {
    unawaited(_forget(db));
    return;
  }
  final sync = ref.read(syncProvider);
  if (sync == null) return;
  final notifier = ref.read(accountsProvider.notifier);
  final backup = ref.read(backupProvider);
  final owner = server.account?.userId;
  Future<void>? running;
  Future<void> run() async {
    try {
      await sync(db, server.config, server.instance);
      if (backup != null && owner != null) {
        await backup(db, server.config, server.instance, owner);
      }
    } on Object catch (error) {
      _log.warning('sync stopped', error: error);
      if (error is CallError && error.logsOut) {
        await notifier.ended(token);
      }
    }
  }

  void start() => running ??= run().whenComplete(() => running = null);
  final timer = Timer.periodic(const Duration(minutes: 5), (_) => start());
  final lifecycle = AppLifecycleListener(onResume: start);
  ref.onDispose(() {
    timer.cancel();
    lifecycle.dispose();
  });
  start();
});

/// Syncs the account in use once, now, which pushes the edits that wait
/// before it reads (ADR-0265): for an edit whose result the user waits for,
/// such as a new version. Offline it does nothing; the periodic sync tries
/// again.
final syncNowProvider = Provider<Future<void> Function()>(
  (ref) => () async {
    final server = ref.read(serverProvider).value;
    final replica = server?.replica;
    final sync = ref.read(syncProvider);
    if (server == null ||
        replica == null ||
        sync == null ||
        server.account?.token == null) {
      return;
    }
    final db = replicaOf(ref, replica);
    if (db == null) return;
    try {
      await sync(db, server.config, server.instance);
    } on Object catch (error) {
      _log.warning('sync stopped', error: error);
    }
  },
);

Future<void> _forget(Replica db) async {
  try {
    await forgetServer(db);
  } on Object catch (error, stack) {
    _log.warning('replica not cleared', error: error, stackTrace: stack);
  }
}
