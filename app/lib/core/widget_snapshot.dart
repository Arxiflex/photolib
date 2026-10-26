import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photolib/core/device_library.dart';
import 'package:photolib/core/logging.dart';
import 'package:photolib/core/replica.dart';
import 'package:photolib/core/share_inbox.dart';
import 'package:photolib/features/library/timeline/pipeline.dart';
import 'package:photolib/features/library/timeline/providers.dart';
import 'package:photolib/features/library/timeline/thumbnails.dart';
import 'package:photolib_data/photolib_data.dart';

const _log = Logger('photolib.widgets');

/// Writes what the home screen's widgets show into [dir] (docs/10 §6.4,
/// ADR-0153), where WidgetKit reads it, never the replica: the images, each
/// pre-rendered once by [render] and left out if it fails, then
/// `snapshot.json`, which names them; images it no longer names go. True when
/// the widgets have something new to show.
Future<bool> writeWidgetSnapshot(
  Directory dir,
  DateTime today,
  List<TimelineItemData> onThisDay,
  Future<Uint8List> Function(ThumbnailItem item) render,
) async {
  await dir.create(recursive: true);
  // A file is complete under its name, or not there.
  Future<void> write(String name, List<int> bytes) async {
    final temp = await File('${dir.path}/$name.tmp').writeAsBytes(bytes);
    await temp.rename('${dir.path}/$name');
  }

  final shown = <Map<String, Object>>[];
  for (final asset in onThisDay) {
    final item = ThumbnailItem.local(asset);
    final image = '${item.key}.png';
    try {
      final path = '${dir.path}/$image';
      if ((await FileStat.stat(path)).type == FileSystemEntityType.notFound) {
        await write(image, await render(item));
      }
      shown.add({'year': asset.day ~/ 10000, 'image': image});
    } on Object catch (error) {
      _log.info(
        'no widget image',
        fields: {'file': '$item', 'cause': '$error'},
      );
    }
  }
  final snapshot = jsonEncode({
    'version': 1,
    'date': today.toIso8601String().substring(0, 10),
    'onThisDay': shown,
  });
  final changed = await File('${dir.path}/snapshot.json')
      .readAsString()
      .then((old) => old != snapshot, onError: (Object _) => true);
  await write('snapshot.json', utf8.encode(snapshot));
  final kept = {'snapshot.json', for (final entry in shown) entry['image']};
  await for (final file in dir.list()) {
    // deletion-ok: a picture of the widget snapshot, which the app wrote
    if (!kept.contains(file.uri.pathSegments.last)) await file.delete();
  }
  return changed;
}

/// Keeps the widgets' snapshot in the App Group's `Widgets/` current on iOS:
/// at start and whenever the app leaves the screen; WidgetKit reloads the
/// widgets (app/ios/WidgetExtension) when it changed.
final widgetSnapshotProvider = Provider<void>((ref) {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) return;
  Future<Uint8List> render(ThumbnailItem item) async {
    final pipeline = await ref.read(thumbnailPipelineProvider.future);
    final image = await pipeline.load(item, 512, Tile());
    try {
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      return png?.buffer.asUint8List() ?? (throw StateError('not encoded'));
    } finally {
      image.dispose();
    }
  }

  final write = Coalesced(() async {
    try {
      const group = ShareInboxChannel();
      final inbox = await group.folder();
      if (inbox == null) return;
      final db = await ref.read(replicaProvider.future);
      final today = DateTime.now();
      final changed = await writeWidgetSnapshot(
        Directory('${Directory(inbox).parent.path}/Widgets'),
        today,
        await onThisDay(db, today),
        render,
      );
      if (changed) await group.reloadWidgets();
    } on Object catch (error, stack) {
      _log.warning(
        'widget snapshot not written',
        error: error,
        stackTrace: stack,
      );
    }
  });
  unawaited(write());
  final lifecycle = AppLifecycleListener(onHide: write.call);
  ref.onDispose(lifecycle.dispose);
});
