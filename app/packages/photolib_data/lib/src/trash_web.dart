import 'dart:js_interop';

import 'package:photolib_data/src/browser_folders.dart' show writableDirectory;
import 'package:photolib_data/src/deletion.dart';
import 'package:photolib_data/src/replica.dart';

/// The trash of desktopTrash: a browser's folders have none, so Photolib's
/// own bin, whose purge asks the browser for write access to a folder.
MediaPlatform folderTrash() => const AppBin(_removeEntry);

Future<void> _removeEntry(LocalAssetData item) async {
  final path = item.path ?? '';
  final slash = path.lastIndexOf('/');
  final dir = await writableDirectory(
    item.volume,
    slash < 0 ? '' : path.substring(0, slash),
  );
  if (dir == null) throw StateError('no write access to its folder');
  try {
    await dir.removeEntry(path.substring(slash + 1)).toDart;
  } on Object {
    // Gone already.
  }
}
