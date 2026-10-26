import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:photolib/core/device_library.dart';
import 'package:photolib/core/logging.dart';

const _log = Logger('photolib.inbox');

/// A shared file, a `photo` or a `video`.
typedef SharedItem = ({String path, String kind});

/// Saves what other apps shared into Photolib (docs/10 §6.4, ADR-0143): the
/// share extension (ShareViewController.swift), and the Runner for a file
/// opened in Photolib (ShareInbox.swift), copy each photo and video into an
/// entry of [inbox] and write the entry's `manifest.json` last. Each
/// complete entry's items go to [save] in one batch and the entry goes once
/// saved; an entry without a manifest (still being copied) or whose save
/// failed stays for the next try, until it is older than [expiry]. Returns
/// how many items wait because Photos refused access (`denied`).
Future<int> drainInbox(
  Directory inbox,
  Future<void> Function(List<SharedItem> items) save, {
  Duration expiry = const Duration(days: 7),
  DateTime? now,
}) async {
  final List<FileSystemEntity> entries;
  try {
    entries = await inbox.list().toList();
  } on PathNotFoundException {
    return 0;
  }
  var waiting = 0;
  for (final entry in entries.whereType<Directory>()) {
    final age = (now ?? DateTime.now()).difference(
      (await FileStat.stat(entry.path)).modified,
    );
    var items = const <SharedItem>[];
    try {
      final manifest = File('${entry.path}/manifest.json');
      final json = jsonDecode(await manifest.readAsString()) as Map;
      items = [
        for (final item in (json['items'] as List).cast<Map<String, Object?>>())
          (path: '${entry.path}/${item['file']}', kind: '${item['kind']}'),
      ];
      await save(items);
      _log.info('shared items saved', fields: {'items': items.length});
    } on PathNotFoundException {
      if (age <= expiry) continue;
    } on Object catch (error, stack) {
      _log.warning(
        'shared items not saved',
        fields: {'expired': age > expiry},
        error: error,
        stackTrace: stack,
      );
      if (age <= expiry) {
        if (error case PlatformException(code: 'denied')) {
          waiting += items.length;
        }
        continue;
      }
    }
    // deletion-ok: the inbox's copy, saved into Photos or expired
    await entry.delete(recursive: true);
  }
  return waiting;
}

/// The App Group's inbox, the Photos library its items are saved into, and
/// the widgets (ShareInbox.swift).
class ShareInboxChannel {
  /// The channel of ShareInbox.swift.
  const new();

  static const _channel = MethodChannel('org.photolib/inbox');

  /// The inbox's path; null without the App Group, or a Runner that has it.
  Future<String?> folder() async {
    try {
      return await _channel.invokeMethod('folder');
    } on MissingPluginException {
      return null;
    }
  }

  /// Saves [items] as new assets of the Photos library, all or none; fails
  /// with `denied` while Photolib may not add to it.
  Future<void> save(List<SharedItem> items) => _channel.invokeMethod('save', [
    for (final item in items) [item.path, item.kind],
  ]);

  /// Asks for access to add to the Photos library, or opens the app's
  /// settings once the system no longer asks.
  Future<void> allow() => _channel.invokeMethod('allow');

  /// Has WidgetKit reload the home screen widgets, which read the App Group's
  /// `Widgets/` (widget_snapshot.dart).
  Future<void> reloadWidgets() => _channel.invokeMethod('reloadWidgets');
}

/// Saves what was shared into Photolib at start, on every resume and when the
/// Runner opens a file in it (`changed`), on iOS; the library hears the new
/// items from PhotoKit. Its state is how many items wait for access to the
/// Photos library, which the library shows.
class ShareInbox extends Notifier<int> {
  static const _channel = ShareInboxChannel();
  late final _drain = Coalesced(() async {
    try {
      final folder = await _channel.folder();
      if (folder != null) {
        state = await drainInbox(Directory(folder), _channel.save);
      }
    } on Object catch (error, stack) {
      _log.error('inbox unreadable', error: error, stackTrace: stack);
    }
  });

  @override
  int build() {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) return 0;
    unawaited(_drain());
    final lifecycle = AppLifecycleListener(onResume: _drain.call);
    // Open in Photolib adds an entry while the app runs.
    ShareInboxChannel._channel.setMethodCallHandler((call) async {
      if (call.method == 'changed') await _drain();
    });
    ref.onDispose(() {
      lifecycle.dispose();
      ShareInboxChannel._channel.setMethodCallHandler(null);
    });
    return 0;
  }

  /// Asks for access, then tries again.
  Future<void> allow() async {
    await _channel.allow();
    await _drain();
  }
}

/// How many shared items wait for access to the Photos library.
final shareInboxProvider = NotifierProvider<ShareInbox, int>(ShareInbox.new);
