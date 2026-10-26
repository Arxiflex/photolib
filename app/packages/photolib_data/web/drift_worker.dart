import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

// drift's isolates and web workers are built on its remote protocol too.
// ignore: experimental_member_use
import 'package:drift/remote.dart';
import 'package:drift/wasm.dart';
import 'package:photolib_data/src/port_channel.dart';
import 'package:sqlite3/wasm.dart';
import 'package:web/web.dart';

/// The worker that hosts one database of the local store in a browser, its one writer for the origin
/// (docs/10-client-app.md §7.5); tools/data/web.sh compiles it to drift_worker.js. It opens the database in OPFS, else
/// IndexedDB, else memory, through SQLite3MultipleCiphers' VFS, so that its client's first statements can key it, and
/// serves drift on the port it is sent until that client closes, and on each `client` port it is sent later (the data
/// worker's) meanwhile; then it rolls back what the client left open, closes the database and posts `closed`. It posts
/// its client's page each of its errors with their stack, which the browser's error event leaves out
/// (photolib-design#491).
void main() {
  final self = globalContext as DedicatedWorkerGlobalScope;
  final clients = StreamController<MessagePort>();
  void report(Object error, StackTrace stack) =>
      self.postMessage({'error': '$error', 'stack': '$stack'}.jsify());
  self.onmessage = (MessageEvent event) {
    final message = event.data as JSObject;
    if (message['client'] case final JSObject port) {
      return clients.add(port as MessagePort);
    }
    runZonedGuarded(
      () =>
          _serve(
            self,
            (message['database'] as JSString).toDart,
            Uri.parse((message['sqlite3'] as JSString).toDart),
            message['port'] as MessagePort,
            clients.stream,
            indexedDb: (message['indexedDb'] as JSBoolean?)?.toDart ?? false,
          ).catchError(report).whenComplete(() {
            self
              ..postMessage('closed'.toJS)
              ..close();
          }),
      report,
    );
  }.toJS;
}

Future<void> _serve(
  DedicatedWorkerGlobalScope self,
  String name,
  Uri sqlite3Uri,
  MessagePort port,
  Stream<MessagePort> clients, {
  required bool indexedDb,
}) async {
  // One writer per database and origin: another tab's worker waits for this one.
  final held = Completer<void>();
  final release = Completer<void>();
  self.navigator.locks.request(
    'photolib/$name',
    (JSAny? _) {
      held.complete();
      return release.future.toJS;
    }.toJS,
  );
  await held.future;
  try {
    final WasmSqlite3 sqlite3;
    try {
      sqlite3 = await WasmSqlite3.loadFromUrl(sqlite3Uri);
    } catch (e) {
      // The browser's error names neither the file nor a place in this worker.
      throw StateError('cannot load $sqlite3Uri: $e');
    }
    final vfs = await _storage('photolib/$name', indexedDb: indexedDb);
    sqlite3.registerVirtualFileSystem(vfs);
    final server = DriftServer(
      WasmDatabase.opened(
        sqlite3.open('/database', vfs: 'multipleciphers-${vfs.name}'),
        enableMigrations: false,
      ),
    );
    final others = clients.listen(
      (port) => server.serve(portChannel(port), serialize: false),
    );
    try {
      // Until the client closes and the transactions it left open are rolled
      // back; a remote shutdown would close the database first
      // (photolib-design#511).
      await server.serve(portChannel(port), serialize: false);
    } finally {
      await others.cancel();
      await server.shutdown();
      switch (vfs) {
        case SimpleOpfsFileSystem():
          vfs.close();
        case IndexedDbFileSystem():
          await vfs.close();
      }
    }
  } finally {
    release.complete();
  }
}

Future<VirtualFileSystem> _storage(
  String path, {
  required bool indexedDb,
}) async {
  if (!indexedDb) {
    try {
      return await SimpleOpfsFileSystem.loadFromStorage(path);
    } catch (_) {}
  }
  try {
    return await IndexedDbFileSystem.open(dbName: path);
  } catch (_) {
    return InMemoryFileSystem();
  }
}
