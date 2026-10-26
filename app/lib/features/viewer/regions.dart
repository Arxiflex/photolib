import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/logging.dart';
import '../library/timeline/pipeline.dart';
import 'deep_zoom.dart';

const _log = Logger('photolib.viewer');

/// The regions of [item] (docs/10 §4.1): MediaStore's through Android's
/// region decoder, a file's through Flutter's codecs; null for anything
/// else, such as a video, and for what they cannot decode.
Future<Regions?> openRegions(ThumbnailItem item) async {
  final took = Stopwatch()..start();
  final (decoder, regions) = item.uri.isScheme('content')
      ? ('region decoder', await ChannelRegions.open(item.uri))
      : !kIsWeb && item.uri.isScheme('file')
      ? ('codec', await CodecRegions.open(item.uri.toFilePath()))
      : ('none', null);
  _log.debug(
    'regions',
    fields: {
      'file': '$item',
      'decoder': decoder,
      'opened': regions != null,
      'size': ?regions?.size.toString(),
      'ms': took.elapsedMilliseconds,
    },
  );
  return regions;
}

final regionsProvider = Provider((ref) => openRegions);

const _channel = MethodChannel('org.photolib/viewer');

/// Puts [item], a MediaStore item, on the clipboard by its URI (MOB-14).
Future<void> copy(ThumbnailItem item) =>
    _channel.invokeMethod('copy', '${item.uri}');

/// A MediaStore item's regions, which ViewerChannel.kt decodes with a
/// `BitmapRegionDecoder`, orientation applied, as RGBA. ViewerChannel.kt also
/// shares and copies items (download_action.dart).
class ChannelRegions implements Regions {
  ChannelRegions._(this._id, this.size);

  static Future<ChannelRegions?> open(Uri uri) async {
    try {
      final v = await _channel.invokeListMethod<int>('open', '$uri');
      return v == null
          ? null
          : ChannelRegions._(v[0], ui.Size(v[1].toDouble(), v[2].toDouble()));
    } on PlatformException catch (e) {
      _log.warning(
        'region decoder refused',
        fields: {'file': '$uri'},
        error: e,
      );
      return null;
    }
  }

  final int _id;
  @override
  final ui.Size size;

  @override
  Future<ui.Image> decode(ui.Rect region, int sample) async {
    final v = (await _channel.invokeListMethod<Object>('decode', [
      _id,
      region.left.round(),
      region.top.round(),
      region.right.round(),
      region.bottom.round(),
      sample,
    ]))!;
    final done = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      v[2] as Uint8List,
      v[0] as int,
      v[1] as int,
      ui.PixelFormat.rgba8888,
      done.complete,
    );
    return done.future;
  }

  @override
  void close() => _channel.invokeMethod<void>('close', _id);
}

/// A file's regions, where Flutter's codecs decode only whole images
/// (docs/10 §4.1): one sample size's image at a time, holding at most
/// [maxPixels] and a GPU texture's 16384 per side, which the tiles are cut
/// from; a finer sample size gets the finest within those.
class CodecRegions implements Regions {
  CodecRegions._(this._buffer, this._descriptor, this.maxPixels)
    : size = ui.Size(
        _descriptor.width.toDouble(),
        _descriptor.height.toDouble(),
      );

  static Future<CodecRegions?> open(
    String path, {
    int maxPixels = 64 << 20,
  }) async {
    final buffer = await ui.ImmutableBuffer.fromFilePath(path);
    try {
      return CodecRegions._(
        buffer,
        await ui.ImageDescriptor.encoded(buffer),
        maxPixels,
      );
    } on Exception catch (e) {
      _log.warning('codec refused', fields: {'file': path}, error: e);
      buffer.dispose();
      return null;
    }
  }

  final ui.ImmutableBuffer _buffer;
  final ui.ImageDescriptor _descriptor;
  final int maxPixels;
  @override
  final ui.Size size;
  (int, ui.Image)? _level;
  // One cut at a time, so that a level is never disposed while in use.
  Future<void> _queue = Future.value();

  @override
  Future<ui.Image> decode(ui.Rect region, int sample) {
    final tile = _queue.then((_) => _cut(region, sample));
    _queue = tile.then((_) {}, onError: (Object _) {});
    return tile;
  }

  Future<ui.Image> _cut(ui.Rect region, int sample) async {
    var s = sample;
    while (size.width * size.height / (s * s) > maxPixels ||
        max(size.width, size.height) / s > 16384) {
      s *= 2;
    }
    if (_level?.$1 != s) {
      _level?.$2.dispose();
      _level = null;
      final codec = await _descriptor.instantiateCodec(
        targetWidth: (size.width / s).ceil(),
        targetHeight: (size.height / s).ceil(),
      );
      _level = (s, (await codec.getNextFrame()).image);
      codec.dispose();
    }
    final level = _level!.$2;
    final scale = level.width / size.width;
    final from = ui.Rect.fromLTRB(
      region.left * scale,
      region.top * scale,
      region.right * scale,
      region.bottom * scale,
    );
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder)
        .drawImageRect(level, from, ui.Offset.zero & from.size, ui.Paint());
    final picture = recorder.endRecording();
    try {
      return await picture.toImage(from.width.ceil(), from.height.ceil());
    } finally {
      picture.dispose();
    }
  }

  @override
  void close() => _queue = _queue.then((_) {
    _level?.$2.dispose();
    _descriptor.dispose();
    _buffer.dispose();
  });
}
