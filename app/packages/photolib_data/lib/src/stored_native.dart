import 'dart:io';
import 'dart:typed_data';

/// Every file under the directory [location], by path: what a copy of the app's storage holds.
Future<Map<String, Uint8List>> storedBytes(String location) async => {
  await for (final entry in Directory(location).list(recursive: true))
    if (entry is File) entry.path: await entry.readAsBytes(),
};
