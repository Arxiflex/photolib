import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:photolib_log/photolib_log.dart';

import 'pool.dart';

int defaultSize() => poolSize(
  Platform.numberOfProcessors,
  phone: Platform.isAndroid || Platform.isIOS,
);

/// Starts a worker isolate that knows [tasks]; [receive] gets its replies.
Future<Channel> spawn(
  List<Task> tasks,
  Uri? script,
  void Function(Object? message) receive,
) async {
  final port = ReceivePort();
  final errors = RawReceivePort(
    (List<Object?> e) => const Logger('photolib.workers').error(
      'worker error',
      error: e[0],
      stackTrace: StackTrace.fromString('${e[1]}'),
    ),
  );
  final inbox = Completer<SendPort>();
  port.listen((m) => m is SendPort ? inbox.complete(m) : receive(m));
  final isolate = await Isolate.spawn(
    _main,
    (port.sendPort, tasks),
    onExit: port.sendPort,
    onError: errors.sendPort,
    debugName: 'photolib worker',
  );
  final send = (await inbox.future).send;
  return (
    send: send,
    close: () {
      port.close();
      errors.close();
      isolate.kill();
    },
  );
}

void _main((SendPort, List<Task>) start) {
  final (out, tasks) = start;
  final inbox = ReceivePort();
  out.send(inbox.sendPort);
  inbox.listen(Server(tasks, out.send).receive);
}
