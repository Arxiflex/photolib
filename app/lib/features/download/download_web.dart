import 'dart:js_interop';
import 'dart:typed_data';

import 'package:photolib_data/browser.dart';
import 'package:web/web.dart' as web;

import '../library/timeline/pipeline.dart';
import 'download.dart';

extension type _Download._(JSObject _) implements JSObject {
  external JSPromise<_Writer> save(String name);
}

extension type _Writer._(JSObject _) implements JSObject {
  external JSPromise<JSAny?> write(JSUint8Array chunk);
  external JSPromise<JSAny?>? close();
  external JSPromise<JSAny?>? abort();
}

/// The browser's own downloads, which web/download.js writes a chunk at a
/// time as they ask for it, so that a large zip never sits in memory. The
/// browser dates a file when it saves it: only a zip's entries keep their
/// time.
class BrowserDestination implements Destination {
  JSPromise<JSAny>? _module;

  @override
  Future<bool> save(
    String name,
    Stream<List<int>> bytes, {
    DateTime? modified,
  }) async {
    _module ??= importModule(
      web.URL('download.js', web.document.baseURI).href.toJS,
    );
    final writer = await ((await _module!.toDart) as _Download)
        .save(name)
        .toDart;
    try {
      await for (final chunk in bytes) {
        final data = chunk is Uint8List ? chunk : Uint8List.fromList(chunk);
        await writer.write(data.toJS).toDart;
      }
      await writer.close()?.toDart;
    } on Object {
      await writer.abort()?.toDart;
      rethrow;
    }
    return true;
  }
}

/// The browser's downloads, which choose their own folder.
Destination? platformDestination({
  required Future<String?> Function() folder,
  required void Function(String folder) chosen,
}) => BrowserDestination();

/// A file of a browser's folder library as it downloads, as of when it was
/// taken; null for others.
Download? downloadOf(ThumbnailItem item) {
  if (!item.uri.isScheme('folder')) return null;
  final [root, ...path] = item.uri.pathSegments;
  return Download(path.last, () async {
    final file = await browserFile(root, path.join('/'));
    if (file == null) throw StateError('$root/${path.join('/')} is gone');
    return DownloadFile(
      _read(file),
      modified:
          item.taken ?? DateTime.fromMillisecondsSinceEpoch(file.lastModified),
      size: file.size,
    );
  });
}

Stream<List<int>> _read(web.Blob blob) async* {
  final reader = blob.stream().getReader() as web.ReadableStreamDefaultReader;
  try {
    for (;;) {
      final read = await reader.read().toDart;
      if (read.done) return;
      yield (read.value! as JSUint8Array).toDart;
    }
  } finally {
    reader.releaseLock();
  }
}

bool canReveal(ThumbnailItem item) => false;

Future<void> reveal(String path) => throw UnsupportedError('no file manager');
