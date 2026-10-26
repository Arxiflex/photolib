import 'dart:async';
import 'dart:js_interop';
import 'dart:math';

import 'package:web/web.dart' as web;

import '../../testing.dart';

/// Null outside Chrome, as Firefox animates a headless page at 1 Hz.
final Frames Function() Function()? countAnimationFrames =
    web.window.navigator.userAgent.contains('Chrome/') ? _count : null;

/// Starts counting the 60 Hz animation frames that the browser starts late, from the gaps between
/// `requestAnimationFrame` callbacks. The returned function stops and returns the count.
Frames Function() _count() {
  const frame = 1000 / 60;
  double? first, last;
  var missed = 0, longest = 0.0, done = false;
  void onFrame(double now) {
    if (last case final last?) {
      missed += max(0, ((now - last) / frame).round() - 1);
      longest = max(longest, now - last);
    }
    first ??= now;
    last = now;
    if (!done) web.window.requestAnimationFrame(onFrame.toJS);
  }

  web.window.requestAnimationFrame(onFrame.toJS);
  return () {
    done = true;
    return Frames(
      missed,
      first == null ? 0 : ((last! - first!) / frame).round(),
      Duration(microseconds: (longest * 1000).round()),
    );
  };
}

String describeMachine() => '${web.window.navigator.hardwareConcurrency} cores';

/// Starts counting, as [countTimerFrames] does, the frames that an idle Web Worker of this page misses. The returned
/// function stops it and returns the count.
Future<Future<Frames> Function()> countIdleFrames() async {
  final url = web.URL.createObjectURL(
    web.Blob([_idle.toJS].toJS, web.BlobPropertyBag(type: 'text/javascript')),
  );
  final worker = web.Worker(url.toJS);
  final messages = StreamIterator(
    web.EventStreamProviders.messageEvent.forTarget(worker),
  );
  await messages.moveNext();
  web.URL.revokeObjectURL(url);
  return () async {
    worker.postMessage(null);
    await messages.moveNext();
    worker.terminate();
    final [missed, total, longest] = [
      for (final n in (messages.current.data as JSArray<JSNumber>).toDart)
        n.toDartInt,
    ];
    await messages.cancel();
    return Frames(missed, total, Duration(microseconds: longest));
  };
}

const _idle = '''
const frame = 1000 / 60, start = performance.now();
let last = start, missed = 0, longest = 0;
const tick = () => {
  const now = performance.now();
  missed += Math.floor((now - last) / frame);
  longest = Math.max(longest, now - last);
  last = now;
};
const timer = setInterval(tick, 1);
onmessage = () => {
  clearInterval(timer);
  tick();
  postMessage([missed, Math.floor((last - start) / frame), Math.round(longest * 1000)]);
};
postMessage(null);
''';
