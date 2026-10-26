import 'dart:io';
import 'dart:typed_data';

import 'package:photolib_data/src/vault.dart';

/// The files of the store in the directory [location].
StoreFiles storeFiles(String location) => _DirectoryFiles(location);

/// The browser's keystore; natively the app brings the platform's.
DeviceKeystore webKeystore() => throw UnsupportedError('a browser keystore');

class _DirectoryFiles implements StoreFiles {
  _DirectoryFiles(this._root);

  final String _root;

  File _file(String name) => File('$_root/$name');

  @override
  Future<Uint8List?> read(String name) async {
    final file = _file(name);
    return await file.exists() ? file.readAsBytes() : null;
  }

  /// Writes a temporary file and renames it, so a crash leaves the old file or the new one.
  @override
  Future<void> write(String name, Uint8List bytes) async {
    final file = _file(name);
    await file.parent.create(recursive: true);
    final part = File('${file.path}.part');
    await part.writeAsBytes(bytes, flush: true);
    await part.rename(file.path);
  }

  @override
  Future<void> delete(String name) async {
    final file = _file(name);
    // deletion-ok: a file of the store's own
    if (await file.exists()) await file.delete();
  }

  @override
  Future<void> deleteAll(String prefix) async {
    final dir = Directory('$_root/$prefix');
    // deletion-ok: a directory of the store's own
    if (await dir.exists()) await dir.delete(recursive: true);
  }

  @override
  Future<List<String>> list(String prefix) async {
    final names = <String>[];
    try {
      await for (final entry in Directory(
        '$_root/$prefix',
      ).list(recursive: true)) {
        if (entry is File) {
          names.add(
            entry.path.substring(_root.length + 1).replaceAll(r'\', '/'),
          );
        }
      }
    } on PathNotFoundException {
      // Nothing there yet.
    }
    return names;
  }
}
