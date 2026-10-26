import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:photolib_log/photolib_log.dart';
import 'package:web/web.dart' as web;

import 'pool.dart';

int defaultSize() => poolSize(web.window.navigator.hardwareConcurrency);

/// Starts a Web Worker from [script]; [receive] gets its replies, and null when it fails.
Future<Channel> spawn(
  List<Task> tasks,
  Uri? script,
  void Function(Object? message) receive,
) async {
  if (script == null) throw ArgumentError.notNull('script');
  final worker = web.Worker(script.toString().toJS)
    ..onmessage = (web.MessageEvent event) {
      receive(event.data.dartify());
    }.toJS
    ..onerror = (web.Event event) {
      event.preventDefault();
      // An ErrorEvent when the script throws, a plain Event when it does not load.
      const Logger('photolib.workers').error(
        'worker error',
        fields: {'script': '$script'},
        error: (event as JSObject)['message'].dartify() ?? event.type,
      );
      receive(null);
    }.toJS;
  return (
    send: (Object? message) => worker.postMessage(message.jsify()),
    close: () => worker.terminate(),
  );
}
