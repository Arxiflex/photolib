import 'dart:io';

import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../library/timeline/pipeline.dart';
import 'download.dart';

/// A desktop's save dialog; the file is written where it says, and removed
/// again if the download does not finish.
class FileDestination implements Destination {
  FileDestination(this.pick, {required this.folder, required this.chosen});

  /// The dialog: where to save [name], starting in [folder].
  final Future<String?> Function(String name, String? folder) pick;

  /// The folder chosen last, where the dialog opens.
  final Future<String?> Function() folder;

  /// Keeps the folder chosen.
  final void Function(String folder) chosen;

  @override
  Future<bool> save(
    String name,
    Stream<List<int>> bytes, {
    DateTime? modified,
  }) async {
    final path = await pick(name, await folder());
    if (path == null) return false;
    final file = File(path);
    chosen(file.parent.path);
    final sink = file.openWrite();
    try {
      await sink.addStream(bytes);
      await sink.close();
      if (modified != null) await file.setLastModified(modified);
    } on Object {
      await sink.close().then((_) {}, onError: (Object _) {});
      // deletion-ok: the download that failed half-written
      await file.delete();
      rethrow;
    }
    return true;
  }
}

bool get _desktop => const {
  TargetPlatform.linux,
  TargetPlatform.macOS,
  TargetPlatform.windows,
}.contains(defaultTargetPlatform);

/// A desktop's save dialog, opening in [folder]; null on phones, which share
/// instead.
Destination? platformDestination({
  required Future<String?> Function() folder,
  required void Function(String folder) chosen,
}) => _desktop
    ? FileDestination(
        (name, folder) async =>
            (await FileSelectorPlatform.instance.getSaveLocation(
              options: SaveDialogOptions(
                suggestedName: name,
                initialDirectory: folder,
              ),
            ))?.path,
        folder: folder,
        chosen: chosen,
      )
    : null;

/// A file of a folder library as it downloads, as of when it was taken;
/// null for other items.
Download? downloadOf(ThumbnailItem item) {
  if (!item.uri.isScheme('file')) return null;
  final file = File(item.uri.toFilePath());
  return Download(item.uri.pathSegments.last, () async {
    final stat = await file.stat();
    return DownloadFile(
      file.openRead(),
      modified: item.taken ?? stat.modified,
      size: stat.size,
    );
  });
}

/// Whether [item] is a file of a folder library on a desktop, which [reveal]
/// shows in the file manager.
bool canReveal(ThumbnailItem item) => _desktop && item.uri.isScheme('file');

/// Shows the file at [path] selected in Finder (FolderAccess.swift, as the
/// sandbox allows), in Explorer, or in the freedesktop file manager, else
/// opens its folder.
Future<void> reveal(
  String path, {
  Future<ProcessResult> Function(String, List<String>) run = Process.run,
}) async {
  Future<bool> ok(String command, List<String> arguments) => run(
    command,
    arguments,
  ).then((r) => r.exitCode == 0, onError: (Object _) => false);
  switch (defaultTargetPlatform) {
    case TargetPlatform.macOS:
      await const MethodChannel('org.photolib/folders')
          .invokeMethod('reveal', path);
    case TargetPlatform.windows:
      await ok('explorer.exe', ['/select,', path]);
    default:
      if (!await ok('dbus-send', [
        '--session',
        '--print-reply',
        '--dest=org.freedesktop.FileManager1',
        '/org/freedesktop/FileManager1',
        'org.freedesktop.FileManager1.ShowItems',
        // dbus-send splits arrays at commas.
        'array:string:${'${Uri.file(path)}'.replaceAll(',', '%2C')}',
        'string:',
      ])) {
        await ok('xdg-open', [File(path).parent.path]);
      }
  }
}
