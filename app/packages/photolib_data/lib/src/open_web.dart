// photolib_data.dart exports its API to browsers in place of
// open_native.dart's, which is all that analysis resolves.
// ignore_for_file: unused-code
import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:drift/drift.dart';
// drift's isolates and web workers are built on its remote protocol too.
// ignore: experimental_member_use
import 'package:drift/remote.dart';
import 'package:photolib_api/photolib_api.dart'
    show ErrorDetail, NetworkConfig, ServerError;
import 'package:photolib_data/src/backup.dart';
import 'package:photolib_data/src/browser_folders.dart';
import 'package:photolib_data/src/keyed.dart';
import 'package:photolib_data/src/port_channel.dart';
import 'package:photolib_data/src/replica.dart';
import 'package:photolib_data/src/sync.dart' show forgetServer;
import 'package:photolib_data/src/vault.dart' show TileCipher;
import 'package:photolib_log/photolib_log.dart';
import 'package:web/web.dart';

/// Opens the replica [name] under [key] in this browser, in a worker of its own
/// that is its one writer for the origin (web/drift_worker.dart), in OPFS, else
/// IndexedDB, else memory (docs/10-client-app.md §7.5), and scans its folders
/// where the browser can keep them. [location] is the URL that serves
/// sqlite3mc.wasm and drift_worker.js (tools/data/web.sh).
Future<Replica> openKeyed(String location, String name, Uint8List key) async {
  final client = _Client();
  final replica = _Watched(
    location,
    client,
    _keyed(location, name, key, client),
    openBackup: (suffix) => keyedConnection(location, '$name$suffix', key),
  );
  try {
    await replica.customSelect('SELECT 1').get();
  } catch (_) {
    // Closing ends the worker, which would otherwise hold the database's lock.
    await replica.close();
    rethrow;
  }
  replica._share(await client.connection.future);
  if (browserFolders != null) replica._unwatch = watchLibraryFolders(replica);
  return replica;
}

/// A replica that stops scanning and reading its folders before it closes.
class _Watched extends Replica {
  _Watched(this.location, this._client, super.executor, {super.openBackup});

  final String location;
  final _Client _client;
  (Worker, Future<void>)? _data;
  final _syncs = <int, Completer<void>>{};
  var _asked = 0;
  Future<void> Function()? _unwatch;

  /// Relays table updates between this replica, whose queries the page
  /// watches, and [remote], the drift client that hears the drift worker's
  /// other clients (the data worker) and tells them.
  void _share(DatabaseConnection remote) {
    var relaying = false;
    void relay(Set<TableUpdate> updates, void Function(Set<TableUpdate>) to) {
      if (relaying) return;
      relaying = true;
      try {
        to(updates);
      } finally {
        relaying = false;
      }
    }

    tableUpdates().listen(
      (u) => relay(u, remote.streamQueries.handleTableUpdates),
    );
    remote.streamQueries
        .updatesForSync(const TableUpdateQuery.any())
        .listen((u) => relay(u, notifyUpdates));
  }

  @override
  Future<void> close() async {
    await _unwatch?.call();
    if (_data case (final worker, final stopped)) {
      worker.postMessage('stop'.toJS);
      // A batch is atomic in the drift worker: one cut short is read again.
      await stopped.timeout(const Duration(seconds: 10), onTimeout: () {});
      worker.terminate();
    }
    await super.close();
  }
}

/// A connection to the database [file] in a worker that its first statement
/// starts, keyed by its first statements; with [indexedDb] the worker skips
/// OPFS.
QueryExecutor keyedConnection(
  String location,
  String file,
  Uint8List key, {
  bool indexedDb = false,
}) => _keyed(location, file, key, _Client(), indexedDb: indexedDb);

QueryExecutor _keyed(
  String location,
  String file,
  Uint8List key,
  _Client client, {
  bool indexedDb = false,
}) => _Started(
  () => _connect(Uri.parse(location), file, indexedDb, client),
).interceptWith(keying(key)).interceptWith(SlowQueries());

/// A client of a drift worker, once it started: the worker, and the connection
/// to it.
class _Client {
  late final Worker worker;
  final connection = Completer<DatabaseConnection>();
}

/// Not drift's delayed connection, which leaves a worker's failed start
/// uncaught, nor its lazy database, whose close throws it again: nothing
/// started, so there is nothing to close.
class _Started extends LazyDatabase {
  _Started(super.opener);

  @override
  Future<void> close() => super.close().onError<StateError>((_, _) {});
}

/// Nothing more to close: each worker closes its database and exits when its
/// client has closed.
Future<void> closeDatabases(String directory) async {}

/// Deletes every database of the store from this browser's storage.
Future<void> deleteDatabases() async {
  final root = await window.navigator.storage.getDirectory().toDart;
  try {
    // deletion-ok: the store's own directory in the origin's private files
    await root
        .removeEntry('photolib', FileSystemRemoveOptions(recursive: true))
        .toDart;
    // The browser's errors are JavaScript's, no Exception.
    // ignore: avoid_catches_without_on_clauses
  } catch (_) {
    // No OPFS, or nothing in it.
  }
  for (final info in (await window.indexedDB.databases().toDart).toDart) {
    if (!info.name.startsWith('photolib/')) continue;
    final done = Completer<void>();
    window.indexedDB.deleteDatabase(info.name).onsuccess = (Event _) {
      done.complete();
    }.toJS;
    await done.future;
  }
}

/// No build before the encrypted store kept a replica in a browser.
Future<bool> rekeyPlaintext(
  String from,
  String location,
  String name,
  Uint8List key,
) async => false;

Future<QueryExecutor> _connect(
  Uri base,
  String file,
  bool indexedDb,
  _Client client,
) {
  const log = Logger('photolib.workers');
  final script = base.resolve('drift_worker.js').toString();
  final worker = client.worker = Worker(script.toJS);
  final connected = Completer<QueryExecutor>();
  final closed = Completer<void>();
  void failed(
    String cause, {
    Map<String, Object?> where = const {},
    String? stack,
  }) {
    final trace = stack == null ? null : StackTrace.fromString(stack);
    log.error(
      'database worker error',
      fields: {'database': file, ...where},
      error: cause,
      stackTrace: trace,
    );
    if (connected.isCompleted) return;
    // A worker that has not served yet never will: ending it frees the
    // database's lock it may hold.
    worker.terminate();
    connected.completeError(
      StateError('the database worker could not start: $cause'),
      trace,
    );
  }

  worker
    // The worker's own errors, with their stack (web/drift_worker.dart).
    ..onmessage = ((MessageEvent e) {
      switch (e.data.dartify()) {
        case {'error': final String error, 'stack': final String stack}:
          failed(error, stack: stack);
        case 'closed':
          closed.complete();
      }
    }).toJS
    ..onmessageerror = ((Event _) => failed('a message could not be read')).toJS
    // What escapes it, which Chrome names only by place, or a script that
    // could not load: logged here rather than as the page's own error.
    ..onerror = ((Event e) {
      e.preventDefault();
      if (!e.isA<ErrorEvent>()) {
        return failed('the worker could not be loaded', where: {'uri': script});
      }
      final error = e as ErrorEvent;
      failed(
        [
          error.message.trim(),
          if (error.error case final JSAny thrown)
            globalContext.callMethod<JSString>('String'.toJS, thrown).toDart,
        ].join(' '),
        where: {
          'uri': error.filename,
          'line': error.lineno,
          'column': error.colno,
        },
      );
    }).toJS;
  log.debug(
    'database worker started',
    fields: {'database': file, 'indexedDb': indexedDb},
  );
  final channel = MessageChannel();
  worker.postMessage(
    JSObject()
      ..['database'] = file.toJS
      ..['sqlite3'] = base.resolve('sqlite3mc.wasm').toString().toJS
      ..['port'] = channel.port2
      ..['indexedDb'] = indexedDb.toJS,
    [channel.port2].toJS,
  );
  // Not in drift's single-client mode, whose close shuts the worker's server
  // down at once: the worker ends once it has rolled back what was left open.
  unawaited(
    connectToRemoteAndInitialize(
      portChannel(channel.port1),
      serialize: false,
    ).then((connection) {
      if (connected.isCompleted) return;
      client.connection.complete(connection);
      connected.complete(
        connection.executor.interceptWith(_Closing(closed.future)),
      );
    }),
  );
  return connected.future;
}

/// Closes once its worker has closed the database and let go of its lock.
class _Closing extends QueryInterceptor {
  _Closing(this._closed);

  final Future<void> _closed;

  @override
  Future<void> close(QueryExecutor inner) async {
    await inner.close();
    await _closed;
  }
}

/// Runs [work] with [db]; browsers have no isolates, and drift's worker is the
/// writer.
Future<T> onDataConnection<T>(Replica db, Future<T> Function(Replica) work) =>
    work(db);

/// Syncs the replica of [db] with the server that [config] reaches as
/// [instance], in its data worker, which starts for it, one sync at a time;
/// completes once every stream has caught up, or with what stopped it. The
/// browser owns TLS and proxies, so only the endpoints, the session and the
/// headers go to it.
Future<void> syncReplica(Replica db, NetworkConfig config, {String? instance}) {
  if (db is! _Watched) throw StateError('not a replica of the vault');
  extractMetadata(db);
  final id = db._asked++;
  final done = db._syncs[id] = Completer<void>();
  final (worker, _) = db._data ?? (throw StateError('no data worker'));
  worker.postMessage(
    [
      'sync',
      id,
      [for (final e in config.endpoints) '$e'],
      config.session,
      config.headers,
      instance,
    ].jsify(),
  );
  return done.future;
}

/// Forgets what a server synced into [db] (forgetServer), once its account is
/// removed (ADR-0234); browsers' data worker does not sync yet.
Future<void> forgetReplica(Replica db) => forgetServer(db);

/// Browsers' data worker does not back up yet, as it does not sync.
Future<BackupRunData> backupReplica(
  Replica db,
  NetworkConfig config,
  BackupSelection selection,
  BackupConditions conditions, {
  String? instance,
}) => throw UnsupportedError('backup needs a data worker');

/// Starts reading the metadata of [db]'s folder files (metadata.dart) in its
/// data worker (web/data_worker.dart), a client of its drift worker, with the
/// kernel's module at [kernel], by default `kernel/photolib_kernel_wasm.js`
/// beside drift_worker.js (tools/kernel/wasm.sh); it runs until [db] closes.
/// Later calls change nothing.
void extractMetadata(Replica db, {String? kernel}) {
  if (db is! _Watched || db._data != null) return;
  const log = Logger('photolib.workers');
  final base = Uri.parse(db.location);
  final script = base.resolve('data_worker.js').toString();
  final stopped = Completer<void>();
  final channel = MessageChannel();
  db._client.worker.postMessage(
    JSObject()..['client'] = channel.port1,
    [channel.port1].toJS,
  );
  final worker = Worker(script.toJS)
    ..onmessage = ((MessageEvent e) {
      switch (e.data.dartify()) {
        case {'log': final String line}:
          Log.emit(LogRecord.fromJson(line));
        case {'error': final String error, 'stack': final String stack}:
          log.error(
            'data worker error',
            error: error,
            stackTrace: StackTrace.fromString(stack),
          );
        case {'synced': final num id} && final Map<Object?, Object?> reply:
          final done = db._syncs.remove(id.toInt());
          switch (reply) {
            case {'error': final String error, 'logsOut': final bool logsOut}:
              done?.completeError(
                logsOut
                    ? ServerError('unauthenticated', ErrorDetail())
                    : StateError(error),
              );
            default:
              done?.complete();
          }
        case 'stopped':
          stopped.complete();
      }
    }).toJS
    ..onerror = ((Event e) {
      e.preventDefault();
      log.error(
        'data worker error',
        fields: {'uri': script},
        error: e.isA<ErrorEvent>() ? (e as ErrorEvent).message : 'not loaded',
      );
      if (!stopped.isCompleted) stopped.complete();
    }).toJS
    ..postMessage(
      JSObject()
        ..['drift'] = channel.port2
        ..['pool'] = base.resolve('metadata_worker.js').toString().toJS
        ..['kernel'] =
            (kernel ??
                    base.resolve('kernel/photolib_kernel_wasm.js').toString())
                .toJS
        ..['release'] = Log.redact.toJS,
      [channel.port2].toJS,
    );
  db._data = (worker, stopped.future);
}

/// Has [db]'s data worker read the items of [ids], those on screen, before any
/// other.
void extractFirst(Replica db, List<Uint8List> ids) {
  if (db is _Watched) db._data?.$1.postMessage(['first', ids].jsify());
}

/// Tells [db]'s data worker whether the device allows background work
/// (docs/09-ml-and-search.md §3.4).
void reportDeviceHealth(Replica db, {required bool healthy}) {
  if (db is _Watched) db._data?.$1.postMessage(['healthy', healthy].jsify());
}

/// Browsers keep tiles as the vault's objects (`VaultCache`) instead.
Future<(TileCipher, void Function())> spawnTileCipher(
  Uint8List lockbox,
  Uint8List secret,
  String? kernel,
) => throw UnsupportedError('no tile cipher in browsers');
