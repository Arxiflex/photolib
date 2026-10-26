import 'dart:js_interop';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:web/web.dart' as web;

Future<int> length(Object blob) async => (blob as web.Blob).size;

Stream<Uint8List> chunks(Object blob, int size) async* {
  blob as web.Blob;
  for (var at = 0; at < blob.size; at += size) {
    yield (await blob.slice(at, at + size).arrayBuffer().toDart).toDart
        .asUint8List();
  }
}

/// A file of [size] zero bytes in the origin private file system.
Future<Object> zeroFile(int size) async {
  final root = await web.window.navigator.storage.getDirectory().toDart;
  final handle = await root
      .getFileHandle('zeros', web.FileSystemGetFileOptions(create: true))
      .toDart;
  addTearDown(() => root.removeEntry('zeros').toDart);
  final writable = await handle.createWritable().toDart;
  await writable.truncate(size).toDart;
  await writable.close().toDart;
  return await handle.getFile().toDart;
}
