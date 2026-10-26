import 'dart:io';
import 'dart:isolate';

import 'package:drift/drift.dart';
import 'package:drift/isolate.dart';
import 'package:drift/native.dart';
import 'package:photolib_api/photolib_api.dart' show NetworkConfig, Server;
import 'package:photolib_data/ml.dart'
    show Decode, ImageInput, OcrSetup, prepareImage;
import 'package:photolib_data/photolib_data.dart' show MlIndexer;
import 'package:photolib_data/src/backup.dart';
import 'package:photolib_data/src/backup_native.dart';
import 'package:photolib_data/src/extract_native.dart';
import 'package:photolib_data/src/faces_native.dart';
import 'package:photolib_data/src/folder_watcher.dart';
import 'package:photolib_data/src/keyed.dart';
import 'package:photolib_data/src/keys.dart';
import 'package:photolib_data/src/metadata.dart';
import 'package:photolib_data/src/ml_isolate.dart';
import 'package:photolib_data/src/replica.dart';
import 'package:photolib_data/src/sync.dart';
import 'package:photolib_data/src/vault.dart' show TileCipher;
import 'package:photolib_kernel/photolib_kernel.dart';
import 'package:photolib_log/photolib_log.dart';
import 'package:photolib_ml/runner.dart';
import 'package:photolib_workers/photolib_workers.dart';
import 'package:sqlite3/sqlite3.dart';

const _log = Logger('photolib.workers');
final _dataIsolates = <String, Future<(DriftIsolate, SendPort, ReceivePort)>>{};
final _controls = Expando<SendPort>();

/// Opens the replica [name] in [directory] under [key] as a client of its data isolate, the one writer of the database
/// (docs/10-client-app.md §1.5). The first call for a path spawns that isolate, which keys and migrates the database
/// first and reports why it could not. Only the vault calls it, on the root isolate: another isolate has its own
/// memory, so it would spawn a second writer; it reaches the replica through `computeWithDatabase` instead.
Future<Replica> openKeyed(String directory, String name, Uint8List key) async {
  final path = _path(directory, name);
  final isolate = _dataIsolates[path] ??= _spawn(path, key);
  try {
    final (server, control, _) = await isolate;
    final replica = Replica(await server.connect());
    _controls[replica] = control;
    return replica;
  } catch (_) {
    _dataIsolates.remove(path);
    rethrow;
  }
}

/// Starts reading the metadata of the device index (metadata.dart) in the data isolate of [db], on a worker pool, with
/// the kernel library at [kernel] or the bundled one; it runs as long as the process. Later calls change nothing.
void extractMetadata(Replica db, {String? kernel}) =>
    _controls[db]?.send(('extract', kernel));

/// Has the data isolate of [db] read the items of [ids], those on screen, before any other.
void extractFirst(Replica db, List<Uint8List> ids) =>
    _controls[db]?.send(('first', ids));

/// Tells the data isolate of [db] whether the device allows background work (docs/09-ml-and-search.md §3.4).
void reportDeviceHealth(Replica db, {required bool healthy}) =>
    _controls[db]?.send(('healthy', healthy));

/// What on-device ML runs in the data isolate (ADR-0278); see [MlIndexer].
class MlSetup {
  /// A setup of [model].
  const MlSetup({
    required this.runtime,
    required this.model,
    required this.input,
    required this.decode,
    required this.decoder,
    required this.state,
    this.backlog = true,
    this.chunk = 8,
    this.kernel,
  });

  /// The ONNX Runtime library; null for the bundled one.
  final String? runtime;

  /// The model, with its golden.
  final RunnerModel model;

  /// How the kernel prepares a photo for it.
  final ImageInput input;

  /// The platform's decoder.
  final Decode decode;

  /// What [decode] is, such as `vips 8.15`.
  final String decoder;

  /// Where the runner keeps its quarantine.
  final String state;

  /// Whether it reads past the new captures.
  final bool backlog;

  /// Photos per run of the model.
  final int chunk;

  /// The kernel library; null for the bundled one.
  final String? kernel;
}

/// Starts on-device OCR in the data isolate of [db] as [setup] says, unless
/// it runs.
void startOcr(Replica db, OcrSetup setup) =>
    _controls[db]?.send(('ocr', setup));

/// Stops on-device OCR in the data isolate of [db] once the chunk under way is
/// stored.
void stopOcr(Replica db) => _controls[db]?.send(('ocr-stop', null));

/// Starts finding faces in the data isolate of [db] as [setup] says, unless it
/// runs; the caller does so only for a user who agreed to it, and stops it
/// with [stopFaces] when they withdraw.
void startFaces(Replica db, FacesSetup setup) =>
    _controls[db]?.send(('faces', setup));

/// Stops finding faces in the data isolate of [db] once the chunk under way is
/// stored, and ends its runner.
void stopFaces(Replica db) => _controls[db]?.send(('faces-stop', null));

/// Starts on-device ML in the data isolate of [db] as [setup] says, unless it
/// runs; it runs as long as the process, or until [stopMl].
void startMl(Replica db, MlSetup setup) => _controls[db]?.send(('ml', setup));

/// Stops on-device ML in the data isolate of [db] once the chunk under way is
/// stored, and ends its runner.
void stopMl(Replica db) => _controls[db]?.send(('ml-stop', null));

/// Holds on-device ML in the data isolate of [db] back, or lets it go: the
/// device's gates (docs/09-ml-and-search.md §3.4).
void holdMl(Replica db, {required bool held}) =>
    _controls[db]?.send(('ml-hold', held));

/// Tells the data isolate of [db] that the user scrolls or edits: on-device ML
/// waits until 5 s after the last time.
void reportInteraction(Replica db) =>
    _controls[db]?.send(('interaction', null));

/// Tells the data isolate of [db] whether an upload batch runs, which
/// on-device ML yields to.
void reportUploads(Replica db, {required bool active}) =>
    _controls[db]?.send(('uploads', active));

/// Syncs the replica of [db] with the server that [config] reaches as [instance], in its data isolate, one sync at a
/// time (docs/10-client-app.md §1.5); completes once every stream has caught up, or with what stopped it.
Future<void> syncReplica(
  Replica db,
  NetworkConfig config, {
  String? instance,
}) async {
  final control = _controls[db];
  if (control == null) throw StateError('not a replica of the vault');
  final reply = ReceivePort();
  control.send(('sync', config, instance, reply.sendPort));
  final Object? error = await reply.first;
  reply.close();
  if (error != null) _rethrow(error);
}

/// Forgets what a server synced into [db] (forgetServer), once its account is
/// removed (ADR-0234): in its data isolate, after the syncs and backups asked
/// for before, so that one still running writes nothing after it.
Future<void> forgetReplica(Replica db) async {
  final control = _controls[db];
  if (control == null) throw StateError('not a replica of the vault');
  final reply = ReceivePort();
  control.send(('forget', reply.sendPort));
  final Object? error = await reply.first;
  reply.close();
  if (error != null) _rethrow(error);
}

/// Backs the device's items up by [selection] to the server that [config]
/// reaches as [instance], as far as [conditions] allow, in the data isolate of
/// [db], one run at a time and never during a sync (ADR-0226); completes with
/// the run's log entry.
Future<BackupRunData> backupReplica(
  Replica db,
  NetworkConfig config,
  BackupSelection selection,
  BackupConditions conditions, {
  String? instance,
}) async {
  final control = _controls[db];
  if (control == null) throw StateError('not a replica of the vault');
  final reply = ReceivePort();
  control.send((
    'backup',
    config,
    instance,
    (selection, conditions),
    reply.sendPort,
  ));
  final Object? answer = await reply.first;
  reply.close();
  if (answer is BackupRunData) return answer;
  _rethrow(answer);
}

/// Shuts the data isolates of the databases in [directory] down and waits for them to exit, which closes the databases
/// and drops their keys; those of other stores keep running.
Future<void> closeDatabases(String directory) async {
  final prefix = _path(directory, '');
  bool inStore(String path) => path.startsWith(prefix);
  final isolates = [
    for (final MapEntry(:key, :value) in _dataIsolates.entries)
      if (inStore(key)) value,
  ];
  _dataIsolates.removeWhere((path, _) => inStore(path));
  for (final spawned in isolates) {
    final (isolate, _, exit) = await spawned;
    await isolate.shutdownAll();
    await exit.first;
  }
}

/// Nothing to do natively: erasing deletes the store's directory.
Future<void> deleteDatabases() async {}

/// Re-keys the plaintext replica [name] that a build before the encrypted store left in [from] into [directory]
/// under [key] (docs/21 §9): a copy is encrypted, verified with `quick_check` and every table's row count, and moved
/// into place, then the plaintext files are deleted. Returns whether there was one. An interrupted run is redone.
Future<bool> rekeyPlaintext(
  String from,
  String directory,
  String name,
  Uint8List key,
) async {
  final plain = _path(from, name);
  final header = File(plain).existsSync()
      ? File(plain).openSync().readSync(16)
      : const <int>[];
  if (String.fromCharCodes(header) != 'SQLite format 3\x00') return false;
  final target = _path(directory, name);
  final rekey = keyStatements(key, pragma: 'hexrekey');
  final keyed = keyStatements(key);
  await Isolate.run(() {
    Database open(String path, List<String> statements) {
      // unkeyed-ok: the plaintext replica, or a copy that [statements] key
      final db = sqlite3.open(path);
      statements.forEach(db.execute);
      return db;
    }

    final copy = '$target.rekey';
    Directory(directory).createSync(recursive: true);
    _delete(copy);
    final source = open(plain, const []);
    final Map<String, int> counts;
    try {
      counts = _counts(source);
      source.execute('VACUUM INTO ?', [copy]);
    } finally {
      source.close();
    }
    open(copy, rekey).close();
    final check = open(copy, keyed);
    try {
      final ok = check.select('PRAGMA quick_check').single.values.single;
      if (ok != 'ok' || '${_counts(check)}' != '$counts') {
        throw StateError('the re-keyed copy of $plain differs: $ok');
      }
    } finally {
      check.close();
    }
    for (final suffix in ['-wal', '-shm']) {
      _delete('$target$suffix');
    }
    File(copy).renameSync(target);
    for (final suffix in ['', '-wal', '-shm', '-journal']) {
      _delete('$plain$suffix');
    }
  });
  return true;
}

Map<String, int> _counts(Database db) => {
  for (final row in db.select(
    "SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name",
  ))
    row['name'] as String:
        db.select('SELECT count(*) AS n FROM "${row['name']}"').single['n']
            as int,
};

void _delete(String path) {
  // deletion-ok: a database file of the store's own
  if (File(path).existsSync()) File(path).deleteSync();
}

String _path(String directory, String name) =>
    Uri.directory(directory).resolve(name).toFilePath();

Future<(DriftIsolate, SendPort, ReceivePort)> _spawn(
  String path,
  Uint8List key,
) async {
  final reply = ReceivePort();
  final exit = ReceivePort();
  final logs = _logsFrom('data isolate');
  final took = Stopwatch()..start();
  final isolate = await Isolate.spawn(
    _serve,
    (reply.sendPort, logs.sendPort, Log.redact, path, key),
    onExit: reply.sendPort,
    onError: logs.sendPort,
    debugName: 'photolib data',
  );
  isolate
    ..addOnExitListener(exit.sendPort)
    ..addOnExitListener(logs.sendPort);
  final ports = await reply.first;
  if (ports is! (SendPort, SendPort)) {
    exit.close();
    _log.error(
      'data isolate failed to open',
      fields: {'path': path},
      error: ports,
    );
    throw StateError('cannot open $path: $ports');
  }
  _log.info(
    'data isolate started',
    fields: {'path': path, 'ms': took.elapsedMilliseconds},
  );
  return (DriftIsolate.fromConnectPort(ports.$1), ports.$2, exit);
}

/// A port that logs here what another isolate's log sends it, and the errors that end it, until it sends null or
/// exits.
RawReceivePort _logsFrom(String name) {
  late final RawReceivePort port;
  return port = RawReceivePort((Object? message) {
    switch (message) {
      case final String line:
        Log.emit(LogRecord.fromJson(line));
      case [final error, final stack]:
        _log.error(
          '$name error',
          error: error,
          stackTrace: StackTrace.fromString('$stack'),
        );
      default:
        _log.debug('$name exited');
        port.close();
    }
  });
}

/// Sends this isolate's log to [port] under the policy of the isolate that started it, [release] or not.
void _logTo(SendPort port, bool release) {
  Log.configure(release: release);
  Log.records.listen((record) => port.send(record.toJson()));
}

Future<void> _serve((SendPort, SendPort, bool, String, Uint8List) args) async {
  final (reply, logs, release, path, key) = args;
  _logTo(logs, release);
  QueryExecutor open(String file) => NativeDatabase(
    File(file),
    enableMigrations: false,
  ).interceptWith(keying(key, ['PRAGMA journal_mode = WAL']));
  final executor = open(path);
  try {
    final replica = Replica(
      executor,
      openBackup: (suffix) => open('$path$suffix'),
    );
    await replica.customSelect('SELECT 1').get();
  } catch (error) {
    await executor.close();
    return reply.send('$error');
  }
  // Every client's statements, timed where they run.
  final server = DriftIsolate.inCurrent(
    () => DatabaseConnection(executor.interceptWith(SlowQueries())),
    killIsolateWhenDone: true,
  );
  final control = ReceivePort();
  reply.send((server.connectPort, control.sendPort));
  // The replica that migrated is done; the clients here are the folder watchers' and the extractor's.
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  Future<Replica> client() async => Replica(await server.connect());
  if (Platform.isLinux || Platform.isMacOS || Platform.isWindows) {
    watchLibraryFolders(await client());
  }
  MetadataExtractor? extractor;
  var healthy = true;
  final ml = MlIsolate(client, _workers);
  (Replica, Replica)? sync;
  // Network work writes on this isolate's own connection, which spares copying
  // each batch to the drift server, and tells the others through a client.
  Future<(Replica, Replica)> writers() async =>
      sync ??= (Replica(executor), Replica(await server.connect()));
  var syncs = Future<void>.value();
  await for (final message in control) {
    _log.debug('data isolate message', fields: {'message': _kind(message)});
    if (await ml.handle(message)) continue;
    switch (message) {
      case ('extract', final String? kernel) when extractor == null:
        extractor = _extractor(await client(), kernel)
          ..healthy = healthy
          ..start();
      case ('first', final List<Uint8List> ids):
        extractor?.prioritise(ids);
      case ('healthy', final bool value):
        healthy = value;
        extractor?.healthy = value;
      case (
        'sync',
        final NetworkConfig config,
        final String? instance,
        final SendPort reply,
      ):
        syncs = syncs.then(
          (_) => _online(writers(), (config, instance), reply, (db, api, n) {
            return SyncEngine(db, api, notify: n).run();
          }),
        );
      case ('forget', final SendPort reply):
        syncs = syncs.then((_) => _forget(writers(), reply));
      case (
        'backup',
        final NetworkConfig config,
        final String? instance,
        (final BackupSelection selection, final BackupConditions conditions),
        final SendPort reply,
      ):
        // After the syncs asked for before it: a restore's re-verification
        // decides what is uploaded again.
        syncs = syncs.then(
          (_) => _online(writers(), (config, instance), reply, (db, api, n) {
            return _backup(db, api, n).run(selection, conditions);
          }),
        );
    }
  }
}

WorkerPool? _pool;
WorkerPool? _hashing;

/// A backup engine on [db], which hashes on a worker of its own.
BackupEngine _backup(
  Replica db,
  Server api,
  void Function(Set<TableUpdate>) notify,
) {
  final pool = _hashing ??= WorkerPool(const [hashMedia], size: 1);
  return BackupEngine(
    db,
    api,
    hash: (file) => pool.run(hashMedia, file).result,
    read: readMedia,
    notify: notify,
  );
}

/// The data isolate's workers: metadata extraction's and on-device ML's. Two:
/// the data isolate's writes bound the speed, and every worker of the isolate
/// group pauses the others, the UI's included, when the machine is busy.
WorkerPool _workers() => _pool ??= WorkerPool(const [
  readMetadata,
  prepareImage,
  prepareFaceDetection,
  readFaces,
  alignFaces,
  normalizeEmbeddings,
], size: (Platform.numberOfProcessors - 1).clamp(1, 2));

/// Reads metadata on the data isolate's [_workers].
MetadataExtractor _extractor(Replica db, String? kernel) =>
    MetadataExtractor(db, kernelExtract(_workers(), kernel: kernel));

/// The kind of a message to a data isolate, its first field.
Object? _kind(Object? message) => switch (message) {
  (final String kind, _) ||
  (final String kind, _, _, _) ||
  (final String kind, _, _, _, _) => kind,
  _ => null,
};

/// Runs [work] against the server that a configuration reaches as an
/// instance, on the replica [writers] gives with the notifier of the other's
/// clients, and answers [reply] with what it returns or why it failed.
Future<void> _online(
  Future<(Replica, Replica)> writers,
  (NetworkConfig, String?) server,
  SendPort reply,
  Future<Object?> Function(
    Replica db,
    Server api,
    void Function(Set<TableUpdate>) notify,
  )
  work,
) async {
  final api = Server(server.$1, instance: server.$2);
  try {
    final (writer, client) = await writers;
    reply.send(await work(writer, api, client.notifyUpdates));
  } on Object catch (error) {
    try {
      reply.send(error);
    } on ArgumentError {
      reply.send(StateError('$error'));
    }
  } finally {
    api.close();
  }
}

/// Forgets what a server synced, on the data isolate's own connection, and
/// says so to [reply].
Future<void> _forget(Future<(Replica, Replica)> writers, SendPort reply) async {
  try {
    final (writer, client) = await writers;
    await forgetServer(writer, notify: client.notifyUpdates);
    reply.send(null);
  } on Object catch (error) {
    reply.send(StateError('$error'));
  }
}

/// Throws what a data isolate answered as an error.
Never _rethrow(Object? error) => switch (error) {
  final Exception e => throw e,
  final Error e => throw e,
  _ => throw StateError('$error'),
};

/// Runs [work] on an isolate of its own with its own client of [db]'s data isolate: long jobs such as indexing
/// neither block the caller nor add a writer.
Future<T> onDataConnection<T>(Replica db, Future<T> Function(Replica) work) {
  final logs = _logsFrom('data connection').sendPort;
  final release = Log.redact;
  return db.computeWithDatabase(
    computation: (db) async {
      _logTo(logs, release);
      try {
        return await work(db);
      } finally {
        logs.send(null);
      }
    },
    connect: Replica.new,
  );
}

/// A [TileCipher] on an isolate of its own, with the kernel library at
/// [kernel] or the bundled one: it opens [lockbox] with the keystore key
/// [secret], keeps only the cache key, and drops it when the returned
/// function closes it.
Future<(TileCipher, void Function())> spawnTileCipher(
  Uint8List lockbox,
  Uint8List secret,
  String? kernel,
) async {
  final replies = ReceivePort();
  final transfer = TransferableTypedData.fromList([secret]);
  secret.fillRange(0, secret.length, 0);
  await Isolate.spawn(_tileWorker, (
    replies.sendPort,
    lockbox,
    transfer,
    kernel,
  ), debugName: 'tile cipher');
  final started = await replies.first;
  if (started is! SendPort) throw StateError('$started');
  final cipher = _TileCipher(started);
  return (cipher, cipher._close);
}

final class _TileCipher implements TileCipher {
  _TileCipher(this._worker);

  final SendPort _worker;
  var _closed = false;

  @override
  Future<Uint8List?> seal(String name, Uint8List tile) =>
      _ask(true, name, tile);

  @override
  Future<Uint8List?> open(String name, Uint8List envelope) =>
      _ask(false, name, envelope);

  Future<Uint8List?> _ask(bool seal, String name, Uint8List bytes) async {
    if (_closed) return null;
    final reply = ReceivePort();
    _worker.send((
      seal,
      name,
      TransferableTypedData.fromList([bytes]),
      reply.sendPort,
    ));
    return switch (await reply.first) {
      final TransferableTypedData data => data.materialize().asUint8List(),
      (final int code, final String reason) => throw KernelError(code, reason),
      _ => null,
    };
  }

  void _close() {
    _closed = true;
    _worker.send(null);
  }
}

// Holds the cache key until told to close, then zeroizes it and exits.
void _tileWorker((SendPort, Uint8List, TransferableTypedData, String?) start) {
  final (replies, lockbox, secret, path) = start;
  final keys = Keys((path == null ? Kernel() : Kernel.open(path)).keyring());
  final int cache;
  try {
    final factor = keys.import(secret.materialize().asUint8List());
    final ddk = keys.openLockbox(lockbox, factor);
    keys.drop(factor);
    cache = keys.cacheKey(ddk);
    keys.drop(ddk);
  } on Object catch (e) {
    keys.keyring.close();
    replies.send('$e');
    return;
  }
  final requests = ReceivePort();
  replies.send(requests.sendPort);
  requests.listen((request) {
    if (request case (
      final bool seal,
      final String name,
      final TransferableTypedData data,
      final SendPort reply,
    )) {
      final key = keys.objectKey(cache, name);
      try {
        final bytes = data.materialize().asUint8List();
        reply.send(
          TransferableTypedData.fromList([
            if (seal)
              keys.encryptBlob(key, bytes, randomBytes(32))
            else
              keys.decryptBlob(key, bytes),
          ]),
        );
      } on KernelError catch (e) {
        reply.send((e.code, e.reason));
      } finally {
        keys.drop(key);
      }
    } else {
      keys.keyring.close();
      requests.close();
    }
  });
}
