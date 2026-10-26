import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

// drift's isolates and web workers are built on its remote protocol too.
// ignore: experimental_member_use
import 'package:drift/remote.dart';
import 'package:photolib_api/photolib_api.dart'
    show CallError, NetworkConfig, Server;
import 'package:photolib_data/src/extract_web.dart';
import 'package:photolib_data/src/metadata.dart';
import 'package:photolib_data/src/port_channel.dart';
import 'package:photolib_data/src/replica.dart';
import 'package:photolib_data/src/sync.dart' show SyncEngine;
import 'package:photolib_log/photolib_log.dart';
import 'package:photolib_workers/photolib_workers.dart';
import 'package:web/web.dart';

/// A replica's data worker in a browser (docs/10-client-app.md §1.5, ADR-0232),
/// compiled by tools/data/web.sh: a client of the drift worker on the `drift`
/// port, it reads the folders' metadata as the data isolate does, with the
/// `kernel` module on the `pool` script's Web Workers. It takes `[first, ids]`
/// and `[healthy, bool]`; on `stop` it posts `stopped` once the chunk being
/// read is stored. It posts its log (`release` as the page's) and its errors.
void main() {
  final self = globalContext as DedicatedWorkerGlobalScope;
  void post(Object message) => self.postMessage(message.jsify());
  late final Future<(MetadataExtractor, WorkerPool, Replica)> started;
  var syncs = Future<void>.value();
  Future<void> sync(int id, List<Object?> message) async {
    final [
      endpoints as List<Object?>,
      session,
      headers as Map<Object?, Object?>,
      instance,
    ] = message;
    final api = Server(
      NetworkConfig(
        endpoints: [for (final e in endpoints) Uri.parse(e! as String)],
        headers: headers.cast(),
        session: session as String?,
      ),
      instance: instance as String?,
    );
    try {
      final (_, _, db) = await started;
      await SyncEngine(db, api).run();
      post({'synced': id});
    } on Object catch (error) {
      post({
        'synced': id,
        'error': '$error',
        'logsOut': error is CallError && error.logsOut,
      });
    } finally {
      api.close();
    }
  }

  self.onmessage = (MessageEvent event) {
    final message = event.data;
    runZonedGuarded(() async {
      if (message.isA<JSString>()) {
        final (extractor, pool, db) = await started;
        await extractor.stop();
        pool.close();
        await db.close();
        return post('stopped');
      }
      if (message.isA<JSArray>()) {
        final (extractor, _, _) = await started;
        return switch (message.dartify()) {
          ['first', final List<Object?> ids] => extractor.prioritise(
            ids.cast(),
          ),
          ['healthy', final bool healthy] => extractor.healthy = healthy,
          ['sync', final num id, ...final rest] => syncs = syncs.then(
            (_) => sync(id.toInt(), rest),
          ),
          _ => null,
        };
      }
      final init = message! as JSObject;
      Log.configure(release: (init['release']! as JSBoolean).toDart);
      Log.records.listen((r) => post({'log': r.toJson()}));
      started = () async {
        final connection = await connectToRemoteAndInitialize(
          portChannel(init['drift']! as MessagePort),
          serialize: false,
        );
        final db = Replica(connection);
        final pool = WorkerPool(
          const [readFolderFiles],
          script: Uri.parse((init['pool']! as JSString).toDart),
          size: 2,
        );
        final kernel = (init['kernel']! as JSString).toDart;
        return (
          MetadataExtractor(db, browserExtract(pool, kernel))..start(),
          pool,
          db,
        );
      }();
      await started;
    }, (error, stack) => post({'error': '$error', 'stack': '$stack'}));
  }.toJS;
}
