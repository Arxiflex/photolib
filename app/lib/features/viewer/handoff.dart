import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'package:photolib/features/library/timeline/pipeline.dart';

const _viewer = MethodChannel('org.photolib/viewer');

/// The place at [lat], [lon] as the platform's maps app opens it: Apple
/// Maps', Windows Maps' or a `geo:` URI, which Android's and the Linux
/// desktops' maps apps handle.
Uri mapOf(double lat, double lon) => Uri.parse(switch (defaultTargetPlatform) {
  TargetPlatform.iOS ||
  TargetPlatform.macOS => 'maps://?ll=$lat,$lon&q=$lat,$lon',
  TargetPlatform.windows => 'bingmaps:?cp=$lat~$lon&lvl=16',
  _ => 'geo:$lat,$lon?q=$lat,$lon',
});

/// Opens [uri] in the app the platform has for it: through the viewer's
/// channel on phones (ViewerChannel.kt, ThumbnailChannel.swift), macOS's
/// workspace (FolderAccess.swift), Windows' shell or `xdg-open`.
Future<void> openElsewhere(
  Uri uri, {
  Future<ProcessResult> Function(String, List<String>) run = Process.run,
}) async {
  switch (defaultTargetPlatform) {
    case TargetPlatform.android || TargetPlatform.iOS:
      await _viewer.invokeMethod<void>('view', ['$uri']);
    case TargetPlatform.macOS:
      await const MethodChannel('org.photolib/folders')
          .invokeMethod<void>('view', '$uri');
    case TargetPlatform.windows:
      await run('explorer.exe', ['$uri']);
    case TargetPlatform.linux || TargetPlatform.fuchsia:
      await run('xdg-open', ['$uri']);
  }
}

/// Whether [item] can be set as a wallpaper or contact photo: a MediaStore
/// photo, which Android hands to the apps that set one.
bool canSetAs(ThumbnailItem item) =>
    !kIsWeb &&
    defaultTargetPlatform == TargetPlatform.android &&
    item.uri.isScheme('content') &&
    !item.video;

/// Offers [item], a photo of type [mime], to the apps that set an image as
/// something (Android's `ATTACH_DATA`).
Future<void> setAs(ThumbnailItem item, String? mime) =>
    _viewer.invokeMethod<void>('setAs', ['${item.uri}', mime]);
