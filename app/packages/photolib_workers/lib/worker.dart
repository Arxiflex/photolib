/// The body of a pool's Web Worker: a script whose `main` calls [serveWorker] with the pool's tasks, compiled with
/// `dart compile js`.
library;

import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'src/pool.dart';

void serveWorker(List<Task> tasks) {
  final scope = globalContext as web.DedicatedWorkerGlobalScope;
  final server = Server(tasks, (message) => scope.postMessage(message.jsify()));
  scope.onmessage = (web.MessageEvent event) {
    server.receive(event.data.dartify());
  }.toJS;
}
