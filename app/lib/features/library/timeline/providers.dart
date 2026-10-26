import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photolib/features/offline/offline.dart';
import 'package:photolib/features/servers/servers.dart';
import 'package:photolib_api/photolib_api.dart' show Unreachable;

import 'native_pipeline.dart' if (dart.library.js_interop) 'web_pipeline.dart';
import 'pipeline.dart';

/// This platform's thumbnail tiers below memory (docs/10-client-app.md §3.4,
/// ADR-0107): MediaStore on Android and PhotoKit on iOS; on desktops a 1 GiB
/// disk cache in the app's cache directory, then on Linux file managers'
/// thumbnails, FFmpeg's poster frames and libvips, on macOS and Windows the
/// platform's decoders and libvips where installed, then Flutter's codecs;
/// in browsers their own decoders, in a worker, and their players' posters,
/// which the store keeps sealed (ADR-0116). Server items show the signed-in
/// server's renditions (T5, ADR-0246), which phones keep in a 1 GiB disk
/// cache too.
final thumbnailPipelineProvider = FutureProvider<ThumbnailPipeline>(
  (ref) => platformPipeline(
    ref,
    (path, headers) =>
        (ref.read(mediaProvider) ?? (throw Unreachable('signed out')))(
          path,
          headers,
        ),
  ),
);

/// The signed-in server's media through the session's [Link] (design 10 §9),
/// once an address has answered as the server's instance, so that the
/// session never goes to another machine (MOB-16). What this device keeps
/// offline is answered from the offline store, with no request (MOB-15);
/// the rest from the network. Null while signed out.
final mediaProvider = Provider<MediaFetch?>((ref) {
  final session = ref.watch(sessionProvider);
  if (session == null) return null;
  return (path, headers) async {
    final offline = await ref.read(offlineMediaProvider.future);
    if (await offline.fetch(path, headers) case final held?) return held;
    final media = await session.media(path, headers: headers);
    final bytes = BytesBuilder(copy: false);
    try {
      await media.bytes.forEach(bytes.add);
    } on Exception catch (e) {
      // A body cut short.
      throw Unreachable(e);
    }
    return (status: media.status, etag: media.etag, bytes: bytes.takeBytes());
  };
});
