import 'dart:io';

import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// The bundle [name] through the save dialog on desktops, or the share sheet
/// on phones from the cache directory (ViewerChannel.kt and AppDelegate.swift
/// share a file of the app's own); false when the user cancelled.
Future<bool> saveBundle(String name, Uint8List bytes) async {
  if (Platform.isAndroid || Platform.isIOS) {
    final file = File('${(await getTemporaryDirectory()).path}/$name');
    await file.writeAsBytes(bytes);
    await const MethodChannel('org.photolib/viewer')
        .invokeMethod('share', ['${file.uri}', 'application/zip']);
    return true;
  }
  final location = await FileSelectorPlatform.instance.getSaveLocation(
    options: SaveDialogOptions(suggestedName: name),
  );
  if (location == null) return false;
  await File(location.path).writeAsBytes(bytes);
  return true;
}
