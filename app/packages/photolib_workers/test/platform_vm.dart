import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';

Future<int> length(Object path) => File(path as String).length();

Stream<Uint8List> chunks(Object path, int size) async* {
  final file = await File(path as String).open();
  try {
    for (
      var chunk = await file.read(size);
      chunk.isNotEmpty;
      chunk = await file.read(size)
    ) {
      yield chunk;
    }
  } finally {
    await file.close();
  }
}

/// A sparse file of [size] zero bytes.
Future<Object> zeroFile(int size) async {
  final dir = await Directory.systemTemp.createTemp('photolib_workers');
  addTearDown(() => dir.delete(recursive: true));
  final file = await File('${dir.path}/zeros').open(mode: FileMode.write);
  await file.truncate(size);
  await file.close();
  return '${dir.path}/zeros';
}
