import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photolib_data/browser.dart';
import 'package:photolib_data/photolib_data.dart' show VaultCache;
import 'package:web/web.dart' as web;

import '../../../core/replica.dart';
import 'browser_thumbnails.dart';
import 'pipeline.dart';

Future<ThumbnailPipeline> platformPipeline(Ref ref, MediaFetch media) async {
  Future<web.File?> open(ThumbnailItem item) async {
    if (!item.uri.isScheme('folder')) return null;
    final [root, ...path] = item.uri.pathSegments;
    return browserFile(root, path.join('/'));
  }

  return ThumbnailPipeline(
    cache: await VaultCache.open(await ref.watch(vaultProvider.future)),
    decoders: [browserPosters(open), browserThumbnails(open)],
    media: media,
  );
}
