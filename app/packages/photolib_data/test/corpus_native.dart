// The VM side of web_test.dart's corpus folder: copies the corpus where the
// test server serves this package from, and sends what the native kernel, as
// the desktop apps run it, reads in each of its media files: their row's
// columns by path, without those it leaves as they are.
// spawnHybridUri loads it by name, which check-unused-code cannot see.
// ignore_for_file: unused-code, unused-files
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:photolib_data/src/extract_native.dart';
import 'package:photolib_data/src/folder_indexer.dart' show mediaExtensions;
import 'package:photolib_kernel/testing.dart';
import 'package:photolib_workers/photolib_workers.dart';
import 'package:stream_channel/stream_channel.dart';

Future<void> hybridMain(StreamChannel<Object?> channel) async {
  const corpus = '../../../testdata/corpus/files';
  const out = '.dart_tool/web_test/corpus';
  final paths = <String>[];
  for (final f in Directory(
    corpus,
  ).listSync(recursive: true).whereType<File>()) {
    final path = f.path.substring(corpus.length + 1);
    File('$out/$path').parent.createSync(recursive: true);
    f.copySync('$out/$path');
    if (mediaExtensions.contains(path.split('.').last.toLowerCase())) {
      paths.add(path);
    }
  }
  final pool = WorkerPool([readMetadata], size: 2);
  try {
    final found = await kernelExtract(pool, kernel: buildKernel())([
      for (final p in paths) (root: Directory(corpus).absolute.path, path: p),
    ], visible: false);
    channel.sink.add({
      'files': out,
      'native': {
        for (final (i, p) in paths.indexed)
          p: {
            for (final MapEntry(:key, :value)
                in found[i]!.toColumns(false).entries)
              key: (value as Variable).value,
          },
      },
    });
  } finally {
    pool.close();
  }
}
