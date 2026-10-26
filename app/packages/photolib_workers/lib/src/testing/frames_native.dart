import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import '../../testing.dart';

/// The VM draws no frames.
const Frames Function() Function()? countAnimationFrames = null;

/// The cores, and the load average where the system tells it.
String describeMachine() {
  final cores = '${Platform.numberOfProcessors} cores';
  try {
    final load = File('/proc/loadavg').readAsStringSync().split(' ').first;
    return 'load average $load on $cores';
  } on FileSystemException {
    return cores;
  }
}

/// Starts counting, as [countTimerFrames] does, the frames that an idle isolate of this process misses. The returned
/// function stops it and returns the count.
Future<Future<Frames> Function()> countIdleFrames() async {
  final replies = ReceivePort();
  final messages = StreamIterator(replies);
  await Isolate.spawn(_idle, replies.sendPort, debugName: 'idle frame meter');
  await messages.moveNext();
  final stop = messages.current as SendPort;
  return () async {
    stop.send(null);
    await messages.moveNext();
    replies.close();
    return messages.current as Frames;
  };
}

void _idle(SendPort replies) {
  final count = countTimerFrames();
  final stop = RawReceivePort();
  stop.handler = (_) {
    stop.close();
    Isolate.exit(replies, count());
  };
  replies.send(stop.sendPort);
}
