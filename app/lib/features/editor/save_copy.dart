import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photolib/core/kernel.dart'
    if (dart.library.js_interop) 'package:photolib/core/kernel_web.dart';
import 'package:photolib/core/on_device_faces.dart' show faceNotice;
import 'package:photolib/core/replica.dart';
import 'package:photolib/features/editor/face_carry.dart';
import 'package:photolib/features/library/timeline/pipeline.dart';
import 'package:photolib/features/settings/settings.dart';
import 'package:photolib_api/kernel.dart' show CaptureTime;
import 'package:photolib_editor/edit.dart';
import 'package:photolib_log/photolib_log.dart';

/// Saves an edit of an item as a copy beside it and returns the copy; null
/// when the user cancelled.
typedef SaveCopy = Future<ThumbnailItem?> Function(
  ThumbnailItem item,
  Edit edit,
  CaptureTime? time,
);

/// How the editor saves; tests fake it.
final saveCopyProvider = Provider<SaveCopy>(
  (ref) =>
      (item, edit, time) => saveCopy(
        item,
        edit,
        time,
        written: (copy, crop) => _carry(ref, item, edit, copy, crop),
      ),
);

const _log = Logger('photolib.faces');

/// Carries the faces found in [item] to its [copy] (ADR-0389), when the user
/// agreed to find faces: [crop] is the part of the edited photo, in pixels,
/// that the copy shows.
Future<void> _carry(
  Ref ref,
  ThumbnailItem item,
  Edit edit,
  ThumbnailItem copy,
  Rect? crop,
) async {
  final id = item.id;
  final db = ref.read(replicaProvider).value;
  if (id == null || db == null) return;
  if (ref.read(settingsProvider).faceNotice != faceNotice) return;
  try {
    await carryFaces(
      db,
      original: id,
      copy: copy.uri,
      turns: edit.quarterTurns,
      flip: edit.flip,
      crop: crop,
    );
  } on Object catch (error) {
    // The copy found its own faces anyway, once indexed.
    _log.warning('faces were not carried to the copy', error: error);
  }
}

/// Whether the editor edits [item]: a JPEG photo in a folder or MediaStore
/// (ADR-0331; PhotoKit and browser folders wait for M2-21 and M8).
bool canEdit(ThumbnailItem item, String? mime) =>
    !item.video &&
    (item.uri.isScheme('file') || item.uri.isScheme('content')) &&
    (mime == 'image/jpeg' ||
        RegExp(r'\.jpe?g$', caseSensitive: false).hasMatch(item.uri.path));

const _viewer = MethodChannel('org.photolib/viewer');

/// Where a copy goes, of the [name] it would take, when its [folder] cannot
/// be written; null when the user cancels.
typedef AskWhere = Future<String?> Function(String name, String folder);

/// The copy of [item] that [edit] makes, written beside it: a file
/// `<name>_edit.jpg` in its folder, or a MediaStore item in its folder.
Future<ThumbnailItem?> saveCopy(
  ThumbnailItem item,
  Edit edit,
  CaptureTime? time, {
  AskWhere ask = _saveDialog,
  Future<void> Function(ThumbnailItem copy, Rect? crop)? written,
}) async {
  final file = item.uri.isScheme('file') ? File(item.uri.toFilePath()) : null;
  final original =
      await file?.readAsBytes() ??
      await _viewer.invokeMethod<Uint8List>('read', ['${item.uri}']) ??
      (throw StateError('no original'));
  final edited = await editedCopyOf(original, edit, time);
  final copy = await writeCopy(item, edited.jpeg, ask: ask);
  if (copy != null) await written?.call(copy, edited.crop);
  return copy;
}

/// Writes [copy] beside [item], once the platform's decoder reads it at a
/// small size, as every write is verified before it counts (design 11 §5.1):
/// as a MediaStore item, or a file `<name>_edit.jpg`, or `_edit-2` and on when
/// taken, through a hidden temporary file, so that no watcher indexes half a
/// file and nothing is ever overwritten. Where the folder cannot be written
/// (macOS keeps picked folders read-only, ADR-0071), it goes where [ask]
/// says, never over the original.
Future<ThumbnailItem?> writeCopy(
  ThumbnailItem item,
  Uint8List copy, {
  AskWhere ask = _saveDialog,
}) async {
  final codec = await ui.instantiateImageCodec(copy, targetWidth: 64);
  try {
    (await codec.getNextFrame()).image.dispose();
  } finally {
    codec.dispose();
  }
  if (!item.uri.isScheme('file')) {
    final uri =
        await _viewer.invokeMethod<String>('saveCopy', ['${item.uri}', copy]) ??
        (throw StateError('no copy'));
    return ThumbnailItem('${sha1.convert(utf8.encode(uri))}', Uri.parse(uri));
  }
  final original = File(item.uri.toFilePath());
  final name = original.uri.pathSegments.last;
  final dot = name.lastIndexOf('.');
  final stem = dot > 0 ? name.substring(0, dot) : name;
  final folder = original.parent.path;
  for (var n = 1; ; n++) {
    final taken = '${stem}_edit${n > 1 ? '-$n' : ''}.jpg';
    final target = File('$folder${Platform.pathSeparator}$taken');
    try {
      // Taken here, so that no other writer gets the same name.
      await target.create(exclusive: true);
    } on FileSystemException {
      if (await _exists(target)) continue;
      final path = await ask('${stem}_edit.jpg', folder);
      if (path == null) return null;
      if (await _exists(File(path)) &&
          await FileSystemEntity.identical(path, original.path)) {
        throw FileSystemException('the original', path);
      }
      return _written(await File(path).writeAsBytes(copy, flush: true), copy);
    }
    final part = File('$folder${Platform.pathSeparator}.$taken.part');
    try {
      await part.writeAsBytes(copy, flush: true);
      return _written(await part.rename(target.path), copy);
    } on Object {
      for (final file in [target, part]) {
        // deletion-ok: the copy this edit took the name of or half wrote
        if (await _exists(file)) await file.delete();
      }
      rethrow;
    }
  }
}

// The root isolate does no synchronous I/O (tool/root_isolate_lint.dart).
// ignore: avoid_slow_async_io
Future<bool> _exists(File file) => file.exists();

ThumbnailItem _written(File file, Uint8List copy) => ThumbnailItem(
  '${sha1.convert(utf8.encode(file.path))}-${copy.length.toRadixString(36)}',
  file.uri,
);

Future<String?> _saveDialog(String name, String folder) async =>
    (await FileSelectorPlatform.instance.getSaveLocation(
      options: SaveDialogOptions(suggestedName: name, initialDirectory: folder),
    ))?.path;
