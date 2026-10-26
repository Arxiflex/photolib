import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'pipeline.dart';
import 'thumbnails.dart';

const _channel = MethodChannel('org.photolib/thumbnails');
var _requests = 0;

/// The platform's thumbnails of the items whose URIs have [schemes], handed
/// over as pixels at the tier (docs/10-client-app.md §3.4). On phones, T3,
/// upright in sRGB (ADR-0040): MediaStore's of a content URI in RGBA, which
/// ThumbnailChannel.kt decodes on cores − 1 threads, or PhotoKit's of a `ph:`
/// local identifier in BGRA, which ThumbnailChannel.swift requests from
/// PHCachingImageManager, never from the network. On macOS and Windows, T4 of
/// a file in RGBA: ImageIO, QuickLook and AVFoundation's poster frames
/// (ThumbnailChannel.swift), or WIC and the shell's thumbnail handlers
/// (thumbnail_channel.cpp), off the UI and raster threads; a format they
/// refuse is [NoThumbnail]. A cancelled request leaves its queue, or stops,
/// and is declined as such, as is a URL that names no file.
Thumbnailer platformThumbnails(Set<String> schemes) => Thumbnailer(
  defaultTargetPlatform.name.toLowerCase(),
  (item, tier, cancelled) async {
    if (!schemes.contains(item.uri.scheme)) throw const Declined('no scheme');
    final id = _requests++;
    unawaited(cancelled.then((_) => _channel.invokeMethod<void>('cancel', id)));
    final List<Object?>? v;
    try {
      v = await _channel.invokeListMethod<Object?>('load', [
        item.uri.toString(),
        tier,
        id,
      ]);
    } on PlatformException catch (e) {
      throw switch (e.code) {
        'refused' => NoThumbnail(video: item.video, cause: e.message ?? ''),
        'cancelled' ||
        'unreadable-url' => Declined([e.code, ?e.message].join(' ')),
        _ => e,
      };
    }
    if (v == null) throw const Declined('nil reply');
    final [width as int, height as int, bytes as Uint8List] = v;
    return item.uri.isScheme('ph')
        ? Pixels.bgra(bytes, width, height)
        : Pixels.rgba(bytes, width, height);
  },
);
