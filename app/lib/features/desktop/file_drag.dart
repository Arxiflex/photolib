import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:photolib/core/logging.dart';
import 'package:photolib/features/folders/folders.dart';
import 'package:photolib/features/library/timeline/pipeline.dart';
import 'package:photolib/features/servers/setup_link.dart';
import 'package:photolib/features/viewer/viewer_page.dart';
import 'package:photolib_data/photolib_data.dart'
    show mediaExtensions, videoExtensions;

const _log = Logger('photolib.drag');

/// Files dragged between the file manager and the window on desktops
/// (docs/10 §8.2, ADR-0144): the runners (file_drag.cc, FileDrag.swift,
/// file_drag.cpp) call `dropped` with the paths dropped on the window, and
/// `drag` starts dragging paths out of it. They also hand over the files
/// opened with the app while it runs, macOS's Finder's and on Linux and
/// Windows a later start's (ADR-0206): `opened` until Dart asks, then
/// `dropped`.
const fileDragChannel = MethodChannel('org.photolib/drag');

/// Starts dragging files out of the window as copies, while the mouse button
/// that moved them is down; null where windows take no files.
final fileDragProvider = Provider<Future<void> Function(List<String> paths)?>(
  (ref) =>
      !kIsWeb &&
          const {
            TargetPlatform.linux,
            TargetPlatform.macOS,
            TargetPlatform.windows,
          }.contains(defaultTargetPlatform)
      ? (paths) => fileDragChannel.invokeMethod('drag', paths)
      : null,
);

/// What a desktop starts the app with, as [openedFilesProvider] keeps it: a
/// `photolib:` link as it is, a file as its absolute path, from the `file:`
/// URL that Linux's `%U` may pass too.
String openedArg(String arg) => switch (Uri.tryParse(arg)) {
  Uri(scheme: 'photolib') => arg,
  final Uri uri when uri.isScheme('file') => uri.toFilePath(),
  _ => File(arg).absolute.path,
};

/// The files the app was started with, absolute, and its `photolib:` links:
/// what the desktop opens with Photolib (docs/10 §8.2, ADR-0243).
final openedFilesProvider = Provider<List<String>>((ref) => const []);

/// Takes what the file manager drops on the window into [child], and the
/// files the app was opened with: each folder joins the library as if picked,
/// and the photos and videos open in the viewer, in the order given.
class FileDrops extends ConsumerStatefulWidget {
  /// Drops into [child].
  const new({required this.child, super.key});

  /// The page under the drops.
  final Widget child;

  @override
  ConsumerState<FileDrops> createState() => _FileDropsState();
}

class _FileDropsState extends ConsumerState<FileDrops> {
  @override
  void initState() {
    super.initState();
    if (ref.read(fileDragProvider) == null) return;
    fileDragChannel.setMethodCallHandler(_call);
    unawaited(_opened());
  }

  /// The command line's files (Linux, Windows), and those opened with the
  /// app before it could take them (`opened`).
  Future<void> _opened() async {
    final paths = [...ref.read(openedFilesProvider)];
    try {
      paths.addAll(
        await fileDragChannel.invokeListMethod<String>('opened') ?? const [],
      );
    } on MissingPluginException {
      // A runner without the channel.
    }
    if (paths.isNotEmpty && mounted) await _take(paths);
  }

  @override
  void dispose() {
    fileDragChannel.setMethodCallHandler(null);
    super.dispose();
  }

  Future<void> _call(MethodCall call) async {
    if (call.method == 'dropped') {
      await _take((call.arguments as List).cast<String>());
    }
  }

  /// Dropped on the window or opened with the app, a password setup link
  /// too.
  Future<void> _take(List<String> paths) async {
    bool link(String path) => path.startsWith('photolib:');
    final links = paths.where(link);
    final others = [
      for (final path in paths)
        if (!link(path)) path,
    ];
    // A link holds its setup token, which no log may (T79): only counted.
    _log.info('dropped', fields: {'files': others, 'links': links.length});
    for (final uri in links) {
      ref
          .read(openedSetupLinkProvider.notifier)
          .open(setupLink(Uri.parse(uri)));
    }
    final files = <ThumbnailItem>[];
    for (final path in others) {
      final stat = await FileStat.stat(path);
      if (stat.type == FileSystemEntityType.directory) {
        if (mounted) await addPickedFolder(context, ref, path);
      } else if (mediaExtensions.contains(_extension(path))) {
        files.add(_item(path, stat));
      }
    }
    if (files.isNotEmpty && mounted) {
      unawaited(openInViewer(context, ref, files));
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

String _extension(String path) => path.split('.').last.toLowerCase();

/// A file outside the library, its key from its path, size and time.
ThumbnailItem _item(String path, FileStat stat) {
  final hash = sha1.convert(utf8.encode(path));
  return ThumbnailItem(
    '$hash-${stat.size.toRadixString(36)}-'
    '${stat.modified.millisecondsSinceEpoch.toRadixString(36)}',
    Uri.file(path),
    video: videoExtensions.contains(_extension(path)),
  );
}
