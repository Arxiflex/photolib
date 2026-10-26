import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:photolib_api/photolib_api.dart' show Server;

/// A file's bytes from an offset on, and where they start: at the offset, or
/// at 0 from a source that sends the whole file; null from a source without
/// the file.
typedef ModelSource = Future<(int, Stream<List<int>>)?> Function(int offset);

/// Installs the model file of [size] bytes and [sha256] (lowercase hex) at
/// [path] from the first of [sources] that has it (design 09 §12.2): a
/// download resumes what an earlier one left in `<path>.part`, and the file is
/// kept only once its size and SHA-256 match; one that does not is deleted. A
/// source that fails passes to the next; with none left, the last failure is
/// thrown, or [ModelMissing] when no source has the file. [progress] hears
/// how many bytes are there.
Future<void> installModel(
  String path, {
  required int size,
  required String sha256,
  required List<ModelSource> sources,
  void Function(int bytes)? progress,
}) async {
  if (File(path).existsSync() && File(path).lengthSync() == size) return;
  final part = File('$path.part');
  await part.parent.create(recursive: true);
  Exception? failure;
  for (final source in sources) {
    var have = part.existsSync() ? part.lengthSync() : 0;
    try {
      final found = await source(have > size ? 0 : have);
      if (found == null) continue;
      final (start, bytes) = found;
      final out = await part.open(mode: FileMode.append);
      try {
        await out.truncate(have = start < have ? start : have);
        await out.setPosition(have);
        await for (final chunk in bytes) {
          await out.writeFrom(chunk);
          progress?.call(have += chunk.length);
        }
      } finally {
        await out.close();
      }
    } on Exception catch (error) {
      failure = error;
      continue;
    }
    final digest = await crypto.sha256.bind(part.openRead()).first;
    if (part.lengthSync() == size && '$digest' == sha256) {
      await part.rename(path);
      return;
    }
    // deletion-ok: the app's own download of a model, which failed its check
    await part.delete();
    failure = FormatException('$path: SHA-256 $digest, expected $sha256');
  }
  if (failure != null) throw failure;
  throw ModelMissing(path);
}

/// No source has a model file: the user's server has not installed it.
class ModelMissing implements Exception {
  /// What [path] would hold.
  const ModelMissing(this.path);

  /// Where the file would go.
  final String path;

  @override
  String toString() => 'no source has $path';
}

/// The file [file] of [model] (`id@revision`) from the user's server.
ModelSource serverModel(Server server, String model, String file) =>
    (offset) async {
      final response = await server.modelFile(model, file, offset);
      if (response == null) return null;
      return (response.statusCode == 206 ? offset : 0, response.stream);
    };

/// The file at [url], a mirror the registry pins, which must send more
/// within [timeout].
ModelSource mirrorModel(
  Uri url, {
  Duration timeout = const Duration(seconds: 30),
}) => (offset) async {
  final client = HttpClient()..connectionTimeout = timeout;
  final request = await client.getUrl(url);
  request.headers.set(HttpHeaders.rangeHeader, 'bytes=$offset-');
  final response = await request.close().timeout(timeout);
  if (response.statusCode == HttpStatus.notFound) {
    client.close(force: true);
    return null;
  }
  if (response.statusCode ~/ 100 != 2) {
    client.close(force: true);
    throw HttpException('HTTP ${response.statusCode}', uri: url);
  }
  Stream<List<int>> body() async* {
    try {
      yield* response.timeout(timeout);
    } finally {
      client.close(force: true);
    }
  }

  return (
    response.statusCode == HttpStatus.partialContent ? offset : 0,
    body(),
  );
};
