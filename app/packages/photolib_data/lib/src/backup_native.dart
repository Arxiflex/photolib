// app/tool/single_writer_lint.dart reads a package import of this package's
// src/ as a way around the vault.
// ignore_for_file: always_use_package_imports
import 'dart:io';
import 'dart:typed_data';

import 'package:photolib_workers/photolib_workers.dart';

import 'blake3.dart';
import 'file_system.dart' show nativePath;
import 'metadata.dart';

/// The BLAKE3 of [file], or null when it cannot be read.
Future<Uint8List?> hashFile(MediaFile file) async {
  final hash = Blake3();
  try {
    await File(nativePath(file.root, file.path)).openRead().forEach(hash.add);
  } on FileSystemException {
    return null;
  }
  return hash.close();
}

/// The bytes of [file] from [offset] on.
Stream<List<int>> readMedia(MediaFile file, int offset) =>
    File(nativePath(file.root, file.path)).openRead(offset);

/// [hashFile] on a worker of a pool.
const hashMedia = Task<MediaFile, Uint8List?>('hashMedia', _hashMedia);

Future<Uint8List?> _hashMedia(MediaFile file, TaskContext context) =>
    hashFile(file);
