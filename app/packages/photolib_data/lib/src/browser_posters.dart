import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:math';
import 'dart:typed_data';

import 'package:photolib_workers/photolib_workers.dart' show JobCancelled;
import 'package:web/web.dart' as web;

/// A video's poster frame as JPEG, and the video's duration when its container says.
typedef Poster = ({Uint8List bytes, Duration? duration});

/// A video whose picture the browser cannot play, and its duration when its container says.
class Unplayable implements Exception {
  const Unplayable(this.cause, [this.duration]);

  final String cause;
  final Duration? duration;

  @override
  String toString() => 'Unplayable($cause)';
}

/// The poster frame of [file] from the browser's own player (docs/10-client-app.md §4.2, ADR-0116), which decodes off
/// the page's thread: an off-DOM `<video>` seeked to a tenth of the video, at most 10 s in, as the server's poster
/// (docs/08 §4.1), then by half seconds for up to 3 s while the frame is near black, so that a fade from black is
/// skipped; drawn with its short side at [tier], never larger. It stops, freeing the player, when [cancelled] completes
/// ([JobCancelled]) or after [timeout] ([TimeoutException]).
Future<Poster> browserPoster(
  web.Blob file,
  int tier, {
  Future<void>? cancelled,
  Duration timeout = const Duration(seconds: 10),
}) async {
  final abort = Completer<Never>()..future.ignore();
  void stop(Object error) {
    if (!abort.isCompleted) abort.completeError(error);
  }

  final timer = Timer(
    timeout,
    () => stop(TimeoutException('no poster', timeout)),
  );
  cancelled?.then((_) => stop(const JobCancelled()));
  final video = web.HTMLVideoElement()
    ..muted = true
    ..preload = 'auto';
  final url = web.URL.createObjectURL(file);
  Future<T> until<T>(Future<T> work) => Future.any([work, abort.future]);
  Duration? duration() => video.duration.isFinite
      ? Duration(milliseconds: (video.duration * 1000).round())
      : null;
  Future<void> next(web.EventStreamProvider<web.Event> event) async {
    final happened = await until(
      Future.any([
        event.forTarget(video).first,
        web.EventStreamProviders.errorEvent.forTarget(video).first,
      ]),
    );
    if (happened.type == 'error') {
      throw Unplayable(video.error?.message ?? 'error', duration());
    }
  }

  // The media time of the frame the player shows.
  var shown = double.nan;
  var presented = Completer<void>();
  void watch() => video.requestVideoFrameCallback(
    (JSNumber _, JSObject frame) {
      shown = (frame['mediaTime']! as JSNumber).toDartDouble;
      presented.complete();
      presented = Completer();
      watch();
    }.toJS,
  );
  try {
    watch();
    video.src = url;
    await next(web.EventStreamProviders.loadedMetadataEvent);
    final (width, height) = (video.videoWidth, video.videoHeight);
    if (width == 0) throw Unplayable('no picture', duration());
    final scale = min(1.0, tier / min(width, height));
    final (w, h) = (
      max(1, (width * scale).round()),
      max(1, (height * scale).round()),
    );
    final canvas = web.OffscreenCanvas(w, h);
    final context =
        canvas.getContext('2d', {'willReadFrequently': true}.jsify())!
            as web.OffscreenCanvasRenderingContext2D;
    final seconds = duration() == null ? 0.0 : video.duration;
    final start = min(seconds / 10, 10.0);
    web.ImageData? brightest;
    var best = -1.0;
    for (
      var t = start;
      best < _dark && t <= start + 3 && (t == start || t < seconds);
      t += 0.5
    ) {
      video.currentTime = t;
      await next(web.EventStreamProviders.seekedEvent);
      // Chrome presents the frame sought after `seeked`, Firefox before; a sparse video may show an earlier one.
      final waiting = Stopwatch()..start();
      while (!((shown - t).abs() <= 0.25) &&
          waiting.elapsedMilliseconds < 200) {
        await until(presented.future).timeout(
          const Duration(milliseconds: 200) - waiting.elapsed,
          onTimeout: () {},
        );
      }
      final frame = await until(
        web.window
            .createImageBitmap(
              video,
              web.ImageBitmapOptions(
                resizeWidth: w,
                resizeHeight: h,
                resizeQuality: 'medium',
              ),
            )
            .toDart,
      );
      context.drawImage(frame, 0, 0);
      frame.close();
      final pixels = context.getImageData(0, 0, w, h);
      final luma = _luma(pixels.data.toDart);
      if (luma > best) (best, brightest) = (luma, pixels);
    }
    context.putImageData(brightest!, 0, 0);
    final jpeg = await until(
      canvas
          .convertToBlob(
            web.ImageEncodeOptions(type: 'image/jpeg', quality: 0.85),
          )
          .toDart,
    );
    return (
      bytes: (await until(jpeg.arrayBuffer().toDart)).toDart.asUint8List(),
      duration: duration(),
    );
  } finally {
    timer.cancel();
    video
      ..removeAttribute('src')
      ..load();
    web.URL.revokeObjectURL(url);
  }
}

/// The mean luma, 0 to 255, below which a frame counts as black.
const _dark = 32;

double _luma(Uint8ClampedList rgba) {
  var sum = 0.0;
  for (var i = 0; i < rgba.length; i += 16) {
    sum += 0.2126 * rgba[i] + 0.7152 * rgba[i + 1] + 0.0722 * rgba[i + 2];
  }
  return sum / (rgba.length / 16).ceil();
}
