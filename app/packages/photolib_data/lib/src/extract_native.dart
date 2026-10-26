import 'dart:io';
import 'dart:math';

import 'package:photolib_data/src/file_system.dart';
import 'package:photolib_data/src/metadata.dart';
import 'package:photolib_data/src/read_metadata.dart';
import 'package:photolib_data/src/replica.dart';
import 'package:photolib_kernel/photolib_kernel.dart';
import 'package:photolib_workers/photolib_workers.dart';
import 'package:protobuf/well_known_types/google/protobuf/timestamp.pb.dart';

/// Reads files with the kernel on [pool]'s workers, 16 files per job: the
/// kernel library at [kernel], or the bundled one.
Extract kernelExtract(WorkerPool pool, {String? kernel}) =>
    (files, {required visible}) async => [
      for (final found in await Future.wait([
        for (var i = 0; i < files.length; i += 16)
          pool.run(
            readMetadata,
            (kernel, files.sublist(i, min(i + 16, files.length))),
            priority: visible ? Priority.interactive : Priority.background,
          ).result,
      ]))
        ...found,
    ];

/// Reads what files say about themselves: the metadata the kernel reads in the
/// parts of each file it asks for, and the capture time it resolves from that
/// and the file's name and folders. Null for a file that cannot be read.
const readMetadata =
    Task<(String?, List<MediaFile>), List<LocalAssetCompanion?>>(
      'readMetadata',
      _readAll,
    );

final Map<String?, Kernel> _kernels = {};

List<LocalAssetCompanion?> _readAll(
  (String?, List<MediaFile>) input,
  TaskContext context,
) {
  final (library, files) = input;
  final kernel = _kernels[library] ??= library == null
      ? Kernel()
      : Kernel.open(library);
  final now = Timestamp.fromDateTime(DateTime.now());
  return [for (final f in files) readFile(kernel.call, f, now)];
}

/// What [f] says about itself, read through [call], a kernel's: the values of
/// its row; none when the kernel panicked on it (kernel.panic), so that it is
/// marked read, which only a change of the file undoes; or null when it cannot
/// be read.
LocalAssetCompanion? readFile(KernelCall call, MediaFile f, Timestamp now) {
  RandomAccessFile? file;
  try {
    final opened = file = File(nativePath(f.root, f.path)).openSync();
    final read = MetadataRead(call, opened.lengthSync(), f.path);
    for (var spans = read.next(); spans.isNotEmpty; spans = read.next()) {
      for (final (at, length) in spans) {
        read.add(at, (opened..setPositionSync(at)).readSync(length));
      }
    }
    final (at, length) = read.tail;
    return companionOf(
      read.meta,
      read.resolve(now),
      f.path,
      animated: read.animated,
      fingerprint: read.fingerprint(
        (opened..setPositionSync(at)).readSync(length),
      ),
    );
  } on KernelPanicked {
    return const LocalAssetCompanion();
  } on Exception {
    return null; // Unreadable or gone: it waits for the next pass.
  } finally {
    file?.closeSync();
  }
}
