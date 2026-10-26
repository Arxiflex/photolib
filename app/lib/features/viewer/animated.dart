import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:photolib/features/library/timeline/pipeline.dart';
import 'package:photolib/features/viewer/mpv.dart'
    if (dart.library.js_interop) 'package:photolib/features/viewer/mpv_web.dart';
import 'package:photolib_data/photolib_data.dart' show isAnimated;

/// The frames of [item] when it is an animated GIF, WebP, PNG or AVIF
/// (FMT-13): a file's, one in a browser folder, or a MediaStore or PhotoKit
/// item's when its facets say it is animated; null for a still and anything
/// else. Only the first bytes are read to tell.
Future<ui.Codec?> animationOf(ThumbnailItem item) async {
  final uri = item.uri;
  if (item.video ||
      !item.animated && (uri.isScheme('content') || uri.isScheme('ph'))) {
    return null;
  }
  const first = 64 << 10;
  final head = await bytesOf(item, limit: first);
  if (head == null || !isAnimated(head)) return null;
  final all = head.length < first ? head : await bytesOf(item);
  if (all == null) return null;
  final codec = await ui.instantiateImageCodec(all);
  if (codec.frameCount > 1) return codec;
  codec.dispose();
  return null;
}

/// How the viewer opens an item's animation.
final Provider<Future<ui.Codec?> Function(ThumbnailItem)> animationProvider =
    Provider((ref) => animationOf);

/// Plays an animated image's codec (FMT-13, docs/10 §4.1), handing each frame
/// to a callback that then owns its image, and loops as the file says. Frame n
/// shows when the durations of those before it have passed, counted on a
/// ticker's clock from the first, and decodes while the one before shows:
/// neither a late vsync nor a decode delays the frames after it, as they did
/// when Flutter's image stream counted each frame's duration from when the
/// last one showed (Aves played GIFs ~20 % slow, deckerst/aves#513). A frame
/// that comes later than its own duration starts the count again, rather than
/// rushing the next ones after a stall. A frame of 10 ms or less shows for
/// 100 ms, as browsers show it.
class Frames {
  /// Plays [_codec] on a ticker of [vsync], handing its frames to [_show].
  new(this._codec, TickerProvider vsync, this._show) {
    _ticker = vsync.createTicker(_tick)..start();
    unawaited(_decode());
  }

  final ui.Codec _codec;
  final void Function(ui.Image image) _show;
  late final Ticker _ticker;
  ui.FrameInfo? _next;
  Duration? _due;
  late int _left = _codec.repetitionCount < 0
      ? -1
      : _codec.frameCount * (_codec.repetitionCount + 1);
  var _disposed = false;

  Future<void> _decode() async {
    if (_left == 0) return _ticker.stop();
    if (_left > 0) _left--;
    try {
      final next = await _codec.getNextFrame();
      if (_disposed) return next.image.dispose();
      _next = next;
    } on Object {
      // A damaged frame ends the animation on the one before.
      if (!_disposed) _ticker.stop();
    }
  }

  void _tick(Duration now) {
    final (next, due) = (_next, _due ?? now);
    if (next == null || now < due) return;
    final shows = next.duration > const Duration(milliseconds: 10)
        ? next.duration
        : const Duration(milliseconds: 100);
    _due = (now - due > shows ? now : due) + shows;
    _next = null;
    _show(next.image);
    unawaited(_decode());
  }

  /// Stops, and lets go of the codec.
  void dispose() {
    _disposed = true;
    _ticker.dispose();
    _next?.image.dispose();
    _codec.dispose();
  }
}
