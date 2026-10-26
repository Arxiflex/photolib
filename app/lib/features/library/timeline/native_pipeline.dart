import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:photolib/core/replica.dart';
import 'package:photolib/features/library/timeline/mpv_posters.dart';
import 'package:photolib/features/library/timeline/thumb_hash.dart';
import 'package:photolib_kernel/photolib_kernel.dart';

import 'disk_cache.dart';
import 'embedded.dart';
import 'ffmpeg.dart';
import 'freedesktop.dart';
import 'pipeline.dart';
import 'platform_thumbnails.dart';
import 'vips.dart';

Future<ThumbnailPipeline> platformPipeline(Ref ref, MediaFetch media) async {
  final vault = await ref.watch(vaultProvider.future);
  final cache = await DiskCache.open(
    '${(await getApplicationCacheDirectory()).path}/thumbnails',
    await vault.tileCipher(),
  );
  ref.onDispose(cache.close);
  final platform = defaultTargetPlatform;
  if (platform == TargetPlatform.android || platform == TargetPlatform.iOS) {
    return ThumbnailPipeline(
      cache: cache,
      thumbnailers: [
        platformThumbnails(const {'content', 'ph'}),
      ],
      media: media,
    );
  }
  return desktopPipeline(cache, media: media);
}

/// The desktops' tiers over [cache], and the server's renditions from
/// [media].
Future<ThumbnailPipeline> desktopPipeline(
  DiskCache cache, {
  MediaFetch? media,
}) async {
  final env = Platform.environment;
  final linux = defaultTargetPlatform == TargetPlatform.linux;
  return ThumbnailPipeline(
    cache: cache,
    media: media,
    thumbnailers: [
      if (linux)
        freedesktopThumbnails(env['XDG_CACHE_HOME'] ?? '${env['HOME']}/.cache'),
    ],
    decoders: [
      if (!linux) platformThumbnails(const {'file'}),
      if (linux) ?await mpvPosters(),
      if (linux) ?await ffmpegPosters(),
      ?await vipsDecoder(),
    ],
    originals: true,
    embedded: embeddedPreview,
    thumbHash: tileThumbHash,
    workers: max(1, Platform.numberOfProcessors - 1),
  );
}

/// The ThumbHash of an encoded tile, by the kernel from a copy at most 32 px a
/// side, on an isolate.
Future<Uint8List> tileThumbHash(Uint8List tile) => Isolate.run(() {
  final image =
      img.decodeImage(tile) ?? (throw const FormatException('not an image'));
  final wide = image.width >= image.height;
  final small = img
      .copyResize(image, width: wide ? 32 : null, height: wide ? null : 32)
      .convert(numChannels: 4);
  return encodeThumbHash(
    Kernel().call,
    small.width,
    small.height,
    small.getBytes(order: img.ChannelOrder.rgba),
  );
});
