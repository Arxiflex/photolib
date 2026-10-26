// web/data_worker.dart, a worker's entry point, uses it: no library may.
// ignore_for_file: unused-code, unused-files
import 'dart:js_interop';
import 'dart:math';
import 'dart:typed_data';

import 'package:photolib_api/kernel.dart';
import 'package:photolib_data/src/browser_folders.dart';
import 'package:photolib_data/src/metadata.dart';
import 'package:photolib_data/src/read_metadata.dart';
import 'package:photolib_data/src/replica.dart';
import 'package:photolib_kernel/photolib_kernel_web.dart';
import 'package:photolib_workers/photolib_workers.dart';
import 'package:protobuf/well_known_types/google/protobuf/timestamp.pb.dart';
import 'package:web/web.dart' as web;

/// Reads the files of the browser's folders on [pool]'s Web Workers, which
/// run [readFolderFiles] with the kernel's module at [kernel], 16 files per
/// job.
Extract browserExtract(WorkerPool pool, String kernel) =>
    (files, {required visible}) async {
      final found = await Future.wait([
        for (final f in files) browserFile(f.root, f.path),
      ]);
      final answers = await Future.wait([
        for (var i = 0; i < files.length; i += 16)
          pool.run(
            readFolderFiles,
            [
              kernel,
              [
                for (var j = i; j < min(i + 16, files.length); j++)
                  [found[j], files[j].path],
              ],
            ],
            priority: visible ? Priority.interactive : Priority.background,
          ).result,
      ]);
      return [
        for (final (i, answer) in answers.expand((a) => a).indexed)
          switch (answer) {
            [
              final List<int> meta,
              final List<int> time,
              final bool animated,
              final List<int> fingerprint,
            ] =>
              companionOf(
                ReadMetadataResponse.fromBuffer(meta),
                ResolveCaptureTimeResponse.fromBuffer(time),
                files[i].path,
                animated: animated,
                fingerprint: Uint8List.fromList(fingerprint),
              ),
            [] => const LocalAssetCompanion(),
            _ => null,
          },
      ];
    };

/// Reads files in a Web Worker (web/metadata_worker.dart), sent as
/// `[kernel module URL, [[file or null, path], …]]`: for each, the kernel's
/// ReadMetadata and ResolveCaptureTime responses, whether it is an animated
/// image and its fingerprint; none when the kernel panicked on it; null when
/// it cannot be read.
const readFolderFiles = Task<List<Object?>, List<Object?>>(
  'readFolderFiles',
  _readAll,
);

final _kernels = <String, Future<Kernel>>{};

Future<List<Object?>> _readAll(List<Object?> input, TaskContext _) async {
  final [url as String, files as List<Object?>] = input;
  final now = Timestamp.fromDateTime(DateTime.now());
  return [
    for (final [file, path as String] in files.cast<List<Object?>>())
      await _read(url, file as web.File?, path, now),
  ];
}

Future<List<Object>?> _read(
  String url,
  web.File? file,
  String path,
  Timestamp now,
) async {
  if (file == null) return null;
  final Kernel kernel;
  try {
    kernel = await (_kernels[url] ??= Kernel.load(Uri.parse(url)));
  } catch (_) {
    _kernels.remove(url)?.ignore();
    rethrow;
  }
  try {
    final read = MetadataRead(kernel.call, file.size, path);
    for (var spans = read.next(); spans.isNotEmpty; spans = read.next()) {
      for (final (at, length) in spans) {
        final data = await file.slice(at, at + length).arrayBuffer().toDart;
        read.add(at, data.toDart.asUint8List());
      }
    }
    final (at, length) = read.tail;
    final tail = await file.slice(at, at + length).arrayBuffer().toDart;
    return [
      read.meta.writeToBuffer(),
      read.resolve(now).writeToBuffer(),
      read.animated,
      read.fingerprint(tail.toDart.asUint8List()),
    ];
  } on KernelPanicked {
    // The module trapped and refuses every later call: load it again.
    _kernels.remove(url)?.ignore();
    return const [];
    // Not only exceptions: the browser's errors are JavaScript's.
    // ignore: avoid_catches_without_on_clauses
  } catch (_) {
    return null; // Gone or changed since it was found: the next pass reads it.
  }
}
