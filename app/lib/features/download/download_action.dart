import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import 'package:photolib/core/providers.dart';
import 'package:photolib/core/replica.dart';
import 'package:photolib/features/download/download.dart';
import 'package:photolib/features/download/download_io.dart'
    if (dart.library.js_interop) 'package:photolib/features/download/download_web.dart';
import 'package:photolib/features/editor/versions.dart';
import 'package:photolib/features/library/timeline/pipeline.dart';
import 'package:photolib/features/servers/link.dart' show Link;
import 'package:photolib/features/servers/servers.dart' show sessionProvider;
import 'package:photolib/features/settings/settings.dart';
import 'package:photolib/l10n/app_localizations.dart';
import 'package:photolib/ui/adaptive.dart';
import 'package:photolib_data/photolib_data.dart' show Replica, uuidOf;

export 'download_io.dart'
    if (dart.library.js_interop) 'download_web.dart'
    show canReveal, reveal;

/// Where this platform saves downloads, a desktop's dialog opening in the
/// folder the settings keep; null on phones.
final destinationProvider = Provider<Destination?>((ref) {
  final settings = ref.read(settingsProvider.notifier);
  return platformDestination(
    folder: settings.downloadFolder,
    chosen: settings.setDownloadFolder,
  );
});

/// The most items a phone shares at once: an intent past a few hundred URIs
/// can exceed Android's 1 MB binder limit, and iOS copies each to share it.
const shareLimit = 500;

/// How an item downloads, if it can.
final downloadOfProvider = Provider<Download? Function(ThumbnailItem)>(
  (ref) => downloadOf,
);

/// Downloads the [count] items [items] gives (MIG-15, ADR-0128): one under
/// its own name, several as a zip, the current version or, when one of them
/// has an edit, the original if the user picks it; with progress and a
/// cancel. Phones share them instead, up to [shareLimit].
Future<void> download(
  BuildContext context,
  WidgetRef ref, {
  required int count,
  required Stream<ThumbnailItem> Function() items,
}) => _download(
  context,
  ref,
  count: count,
  items: () => items().map((item) => (item, null)),
);

/// Downloads [albums] (MIG-15): one as a zip named after it, several as one
/// zip with a folder for each; phones share their items.
Future<void> downloadAlbums(
  BuildContext context,
  WidgetRef ref,
  List<({String name, int count, Stream<ThumbnailItem> Function() items})>
  albums,
) {
  final used = <String>{};
  final folders = [
    for (final album in albums) uniqueName(album.name, used, file: false),
  ];
  return _download(
    context,
    ref,
    count: albums.fold(0, (sum, album) => sum + album.count),
    items: () async* {
      for (final (i, album) in albums.indexed) {
        await for (final item in album.items()) {
          yield (item, albums.length > 1 ? folders[i] : null);
        }
      }
    },
    archive: albums.length == 1 ? '${folders.single}.zip' : null,
  );
}

/// A photo only the server has as it downloads (ADR-0128, ADR-0391): its
/// original, and once edited its current version, the server's `edit_export`;
/// null for any other item, or one the replica does not know.
Future<Download?> serverDownloadOf(
  Link link,
  Replica db,
  ThumbnailItem item,
) async {
  final asset = isServerOnly(item) ? serverAssetOf(item) : null;
  if (asset == null) return null;
  final row = await (db.select(
    db.asset,
  )..where((a) => a.id.equals(asset))).getSingleOrNull();
  if (row == null) return null;
  final current = row.currentVersionId;
  final edit = current == null
      ? null
      : await (db.select(db.assetVersion)
              ..where((v) => v.id.equals(current))
              ..where((v) => v.kind.equals('edit')))
            .getSingleOrNull();
  final taken = DateTime.fromMillisecondsSinceEpoch(
    row.takenUtc ?? row.createdAt,
  );
  Future<DownloadFile> file(String role) async {
    final media = await link.media('media/${uuidOf(asset)}/$role');
    return DownloadFile(media.bytes, modified: taken, size: media.length);
  }

  final name = row.originalFilename;
  final dot = name.lastIndexOf('.');
  return Download(
    name,
    () => file('original'),
    edited: edit == null ? null : () => file('edit_export'),
    editedName: edit == null
        ? null
        : '${dot > 0 ? name.substring(0, dot) : name}_edit.jpg',
  );
}

/// Downloads [count] items, each into the archive's folder it names, as
/// [archive] or, unless there is one, one under its own name.
Future<void> _download(
  BuildContext context,
  WidgetRef ref, {
  required int count,
  required Stream<(ThumbnailItem, String?)> Function() items,
  String? archive,
}) async {
  final strings = AppLocalizations.of(context);
  if (sharesDownloads && count > shareLimit) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(strings.shareTooMany(shareLimit))));
    return;
  }
  if (sharesDownloads) {
    final all = await items().map((item) => item.$1).toList();
    if (context.mounted) await share(context, all);
    return;
  }
  final to = ref.read(destinationProvider);
  if (to == null || count == 0) return;
  final of = ref.read(downloadOfProvider);
  // The photos only the server has are read from the replica first.
  final server = <String, Download>{};
  if (ref.read(sessionProvider) case final link?) {
    final db = await ref.read(replicaProvider.future);
    await for (final (item, _) in items()) {
      if (isServerOnly(item) && of(item) == null) {
        if (await serverDownloadOf(link, db, item) case final d?) {
          server[item.key] = d;
        }
      }
    }
  }
  Stream<Download> downloads() => items().expand(
    (item) => [
      if (of(item.$1) ?? server[item.$1.key] case final d?)
        Download(
          d.name,
          d.original,
          edited: d.edited,
          editedName: d.editedName,
          folder: item.$2,
        ),
    ],
  );
  var original = false;
  if (await _anyEdit(ref) &&
      await downloads().any((download) => download.edited != null)) {
    if (!context.mounted) return;
    final choice = await showDialog<bool>(
      context: context,
      builder: (context) => _Version(strings),
    );
    if (choice == null) return;
    original = choice;
  }
  if (!context.mounted) return;
  await _save(
    context,
    ref,
    to,
    count,
    downloads,
    archive: archive,
    original: original,
  );
}

/// Downloads [file], a file of the server's that is no photo or video, to
/// where this platform saves downloads (ADR-0066).
Future<void> downloadFile(
  BuildContext context,
  WidgetRef ref,
  Download file,
) async {
  final to = ref.read(destinationProvider);
  if (to != null) await _save(context, ref, to, 1, () => Stream.value(file));
}

/// Saves the [count] [downloads] to [to], with their progress, a cancel and
/// what came of it.
Future<void> _save(
  BuildContext context,
  WidgetRef ref,
  Destination to,
  int count,
  Stream<Download> Function() downloads, {
  String? archive,
  bool original = false,
}) async {
  final strings = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final job = DownloadJob(count);
  final close = _showProgress(context, count, job, job.cancel);
  String? message;
  try {
    final saved = await job.save(
      to,
      downloads(),
      archive:
          archive ??
          (count == 1
              ? null
              : 'Photolib ${DateFormat('yyyy-MM-dd HH.mm.ss').format(DateTime.now())}.zip'),
      original: original,
    );
    if (saved != null) message = strings.downloadSaved(saved);
  } on DownloadCancelled {
    // The user knows.
  } on Object catch (error) {
    ref.read(loggerProvider).warning('download failed', error: error);
    message = strings.downloadFailed;
  } finally {
    close();
    job.dispose();
  }
  if (message != null) messenger.showSnackBar(SnackBar(content: Text(message)));
}

/// Shows how far [count] items are, [progress] from 0 to 1 when known, with
/// a cancel, which closes it too; anything shown meanwhile waits behind it.
/// What it returns closes it.
VoidCallback _showProgress(
  BuildContext context,
  int count,
  ValueListenable<double?> progress,
  VoidCallback cancel,
) {
  final messenger = ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..removeCurrentSnackBar();
  final bar = messenger.showSnackBar(
    SnackBar(
      duration: const Duration(days: 1),
      content: ValueListenableBuilder(
        valueListenable: progress,
        builder: (context, value, _) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(AppLocalizations.of(context).downloading(count)),
            const SizedBox(height: 8),
            LinearProgressIndicator(value: value),
          ],
        ),
      ),
      action: SnackBarAction(
        label: MaterialLocalizations.of(context).cancelButtonLabel,
        onPressed: cancel,
      ),
    ),
  );
  var open = true;
  unawaited(bar.closed.whenComplete(() => open = false));
  return () {
    if (open) bar.close();
  };
}

/// Whether the replica holds an edit, which it says without the selection
/// being read: until it does, no item has another version than its original.
Future<bool> _anyEdit(WidgetRef ref) async {
  final db = await ref.read(replicaProvider.future);
  final edit = db.select(db.assetVersion)
    ..where((v) => v.kind.equals('edit'))
    ..limit(1);
  return await edit.getSingleOrNull() != null;
}

/// The current version, by default, or the original.
class _Version extends StatefulWidget {
  const _Version(this.strings);

  final AppLocalizations strings;

  @override
  State<_Version> createState() => _VersionState();
}

class _VersionState extends State<_Version> {
  var _original = false;

  @override
  Widget build(BuildContext context) {
    final strings = widget.strings;
    final material = MaterialLocalizations.of(context);
    return AlertDialog(
      title: Text(strings.downloadVersion),
      content: RadioGroup<bool>(
        groupValue: _original,
        onChanged: (v) => setState(() => _original = v!),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RadioListTile(value: false, title: Text(strings.downloadCurrent)),
            RadioListTile(value: true, title: Text(strings.downloadOriginal)),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(material.cancelButtonLabel),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, _original),
          child: Text(strings.download),
        ),
      ],
    );
  }
}

/// Whether [item] can be shared: a MediaStore item or a PhotoKit asset.
bool canShare(ThumbnailItem item) =>
    item.uri.isScheme('content') || item.uri.isScheme('ph');

/// Offers [items] to other apps through the system's share sheet, as [mime]
/// or what their kinds say: MediaStore items on Android (ViewerChannel.kt),
/// PhotoKit assets on iOS (ShareSheet.swift).
Future<void> share(
  BuildContext context,
  List<ThumbnailItem> items, {
  String? mime,
}) async {
  final shared = items.where(canShare).toList();
  if (shared.isEmpty) return;
  if (shared.first.uri.isScheme('ph')) return _sharePhotos(context, shared);
  final kinds = {for (final i in shared) i.video};
  await const MethodChannel('org.photolib/viewer').invokeMethod('share', [
    [for (final i in shared) '${i.uri}'],
    mime ?? (kinds.length > 1 ? '*/*' : (kinds.single ? 'video/*' : 'image/*')),
  ]);
}

/// Whether PhotoKit assets are being shared: their channel has one progress
/// handler, and its cancel stops every request.
var _sharingPhotos = false;

/// Shares PhotoKit assets, which iOS copies first, from iCloud if need be: an
/// explicit export, which shows its progress while it downloads, with a
/// cancel, into a bounded temporary space (docs/10 §6.2). Nothing starts
/// while another share runs.
Future<void> _sharePhotos(
  BuildContext context,
  List<ThumbnailItem> items,
) async {
  if (_sharingPhotos) return;
  _sharingPhotos = true;
  const channel = MethodChannel('org.photolib/share');
  final messenger = ScaffoldMessenger.of(context);
  final strings = AppLocalizations.of(context);
  final progress = ValueNotifier<double?>(null);
  VoidCallback? close;
  channel.setMethodCallHandler((call) async {
    if (call.method != 'progress') return;
    progress.value = call.arguments as double;
    if (close == null && context.mounted) {
      close = _showProgress(
        context,
        items.length,
        progress,
        () => unawaited(channel.invokeMethod<void>('cancel')),
      );
    }
  });
  var tooLarge = false;
  try {
    await channel.invokeMethod<void>('share', [
      for (final i in items) i.uri.path,
    ]);
  } on PlatformException catch (e) {
    tooLarge = e.code == 'tooLarge';
    if (!tooLarge && e.code != 'cancelled') rethrow;
  } finally {
    _sharingPhotos = false;
    channel.setMethodCallHandler(null);
    close?.call();
    progress.dispose();
  }
  if (tooLarge) {
    messenger.showSnackBar(SnackBar(content: Text(strings.shareTooLarge)));
  }
}
