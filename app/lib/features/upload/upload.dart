import 'dart:async';

import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photolib/features/servers/servers.dart';
import 'package:photolib/features/upload/hasher.dart';
import 'package:photolib_log/photolib_log.dart';

const _log = Logger('photolib.upload');

/// Where an upload is.
enum UploadState {
  /// Hashing the file, which the server wants before it takes a byte.
  hashing,

  /// Sending what the server lacks of it.
  sending,

  /// Stored and verified by the server.
  done,

  /// Stopped: [UploadItem.error] says why.
  failed,
}

/// One file the person gave to upload, and how far it got.
@immutable
class UploadItem {
  /// A file of [size] bytes, in [state].
  const new(
    this.name,
    this.size, {
    this.state = UploadState.hashing,
    this.hashed = 0,
    this.sent = 0,
    this.error,
  });

  /// The file's name, which ingest keeps as the asset's.
  final String name;

  /// Its length in bytes, once known.
  final int size;

  /// Where it is.
  final UploadState state;

  /// The share of the file hashed, from 0 to 1.
  final double hashed;

  /// Bytes the server has, as far as this device knows.
  final int sent;

  /// Why it failed.
  final Object? error;

  UploadItem _with({
    UploadState? state,
    double? hashed,
    int? sent,
    Object? error,
  }) => UploadItem(
    name,
    size,
    state: state ?? this.state,
    hashed: hashed ?? this.hashed,
    sent: sent ?? this.sent,
    error: error ?? this.error,
  );
}

/// The browser's file picker, null where the app has no use for it.
typedef Pick = Future<List<XFile>> Function();

/// Opens the system's file dialog for photos and videos.
final uploadPickerProvider = Provider<Pick>(
  (ref) =>
      () => FileSelectorPlatform.instance.openFiles(
        acceptedTypeGroups: const [
          XTypeGroup(mimeTypes: ['image/*', 'video/*']),
        ],
      ),
);

/// How a file is hashed for its upload: on a Web Worker in a browser.
typedef Hasher = Future<String> Function(
  XFile file,
  void Function(double done) progress,
);

/// Hashes the files to upload; tests fake it.
final uploadHasherProvider = Provider<Hasher>((ref) => hashFile);

/// The files being uploaded to the signed-in server, from the picker or a
/// drop on the window (WEB-01): hashed, created as resumable uploads
/// (ADR-0061) and sent one after another; a file the server refuses fails
/// alone.
final uploadsProvider = NotifierProvider<Uploads, List<UploadItem>>(
  Uploads.new,
);

/// See [uploadsProvider].
class Uploads extends Notifier<List<UploadItem>> {
  var _queue = Future<void>.value();

  @override
  List<UploadItem> build() => const [];

  /// Uploads [files] after those given before; completes once they ended.
  Future<void> add(Iterable<XFile> files) {
    final first = state.length;
    final given = files.toList();
    state = [...state, for (final file in given) UploadItem(file.name, 0)];
    final run = _queue.then((_) async {
      for (final (i, file) in given.indexed) {
        await _upload(first + i, file);
      }
    });
    _queue = run.catchError((Object _) {});
    return run;
  }

  /// Forgets the uploads that ended.
  void clearFinished() => state = [
    for (final item in state)
      if (item.state == UploadState.hashing ||
          item.state == UploadState.sending)
        item,
  ];

  void _set(int index, UploadItem Function(UploadItem item) change) {
    if (!ref.mounted || index >= state.length) return;
    state = [
      for (final (i, item) in state.indexed)
        if (i == index) change(item) else item,
    ];
  }

  Future<void> _upload(int index, XFile file) async {
    final link = ref.read(sessionProvider);
    try {
      if (link == null) throw StateError('not signed in');
      final size = await file.length();
      _set(index, (item) => UploadItem(item.name, size));
      final hash = await ref.read(uploadHasherProvider)(
        file,
        (done) => _set(index, (item) => item._with(hashed: done)),
      );
      _set(index, (item) => item._with(state: UploadState.sending, hashed: 1));
      final path = await link.createUpload(size, hash, path: file.name);
      await link.sendUpload(path, size, (offset) {
        var at = offset;
        return file.openRead(offset).map((chunk) {
          at += chunk.length;
          _set(index, (item) => item._with(sent: at));
          return chunk;
        });
      });
      _set(index, (item) => item._with(state: UploadState.done, sent: size));
    } on Object catch (error) {
      _log.warning('upload failed', fields: {'file': file.name}, error: error);
      _set(
        index,
        (item) => item._with(state: UploadState.failed, error: error),
      );
    }
  }
}
