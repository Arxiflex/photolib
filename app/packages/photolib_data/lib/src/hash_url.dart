// web/hash_worker.dart, a worker's entry point, uses it: no library may.
// ignore_for_file: unused-code, unused-files
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:photolib_workers/blake3.dart';
import 'package:photolib_workers/photolib_workers.dart';
import 'package:web/web.dart' as web;

/// The BLAKE3 of the bytes at [url] (a `blob:` URL of a picked or dropped
/// file), as lowercase hex, read in pieces as the browser gives them and
/// never whole; [progress] gets the share read, from 0 to 1, as it grows.
Future<String> hashUrl(
  String url, {
  void Function(double done)? progress,
}) async {
  // A worker has no `window`; both it and a page have `fetch`.
  final response = await globalContext
      .callMethod<JSPromise<web.Response>>('fetch'.toJS, url.toJS)
      .toDart;
  final total = int.tryParse(response.headers.get('content-length') ?? '') ?? 0;
  final body = response.body;
  if (body == null) throw StateError('no body at $url');
  final reader = body.getReader() as web.ReadableStreamDefaultReader;
  final hash = Blake3();
  var read = 0;
  for (;;) {
    final chunk = await reader.read().toDart;
    if (chunk.done) break;
    final bytes = (chunk.value as JSUint8Array?)?.toDart;
    if (bytes == null) break;
    hash.add(bytes);
    read += bytes.length;
    if (total > 0) progress?.call(read / total);
  }
  progress?.call(1);
  return hash.hex;
}

/// [hashUrl] in a Web Worker (web/hash_worker.dart), sent the URL.
const hashInWorker = Task<String, String>('hashUrl', _hashInWorker);

Future<String> _hashInWorker(String url, TaskContext context) =>
    hashUrl(url, progress: context.progress);

WorkerPool? _pool;

/// The BLAKE3 of the file at [url], hashed on a Web Worker of the page's pool
/// (`hash_worker.js` beside the app) so that the page keeps drawing, with
/// [progress] as [hashUrl].
Future<String> hashOnWorker(
  String url, {
  void Function(double done)? progress,
}) {
  final pool = _pool ??= WorkerPool(
    const [hashInWorker],
    script: Uri.base.resolve('hash_worker.js'),
    size: 2,
  );
  final job = pool.run(hashInWorker, url, priority: Priority.interactive);
  if (progress != null) job.progress.listen(progress);
  return job.result;
}
