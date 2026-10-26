import 'package:drift/drift.dart';
import 'package:photolib_data/photolib_data.dart';

/// What the library keeps out of new device folders until the user shows
/// them (ADR-0210): app-private and game data, caches, hidden folders, and
/// the album art of audio folders. Android's shared storage ignores case.
final IgnoreRules _junk = IgnoreRules.defaults(caseSensitive: false).add(
  '',
  '/Android/data/ /Android/obb/ .*/ cache/ caches/ /Music/ /Podcasts/ '
          '/Audiobooks/ /Ringtones/ /Alarms/ /Notifications/ /Recordings/'
      .replaceAll(' ', '\n'),
);

/// Whether the device folder [path], a relative path ending in `/`, or a
/// folder it is in is junk.
bool isJunk(String path) {
  final dirs = path.split('/')..removeLast();
  for (var i = 1; i <= dirs.length; i++) {
    if (_junk.ignores(dirs.take(i).join('/'), dir: true)) return true;
  }
  return false;
}

/// Shows the device folder [id] in the library or keeps it out (see [show]);
/// the app has said it is new.
Future<void> showFolder(Replica db, int id, {required bool shown}) async {
  final f = await (db.select(
    db.deviceFolder,
  )..where((f) => f.id.equals(id))).getSingle();
  await show(db, f.volume, f.path, shown: shown);
}

/// Shows the folder [path] of [volume], or the device when [volume] is '',
/// in the library or keeps it out, and with it what below has no visibility
/// of its own: its own visibility only where the folders above it would not.
Future<void> show(
  Replica db,
  String volume,
  String path, {
  required bool shown,
}) async {
  final above = volume.isEmpty ? null : await _shownAbove(db, volume, path);
  await setVisibility(
    db,
    volume,
    path,
    shown == above
        ? SourceVisibility.inherit
        : shown
        ? SourceVisibility.shown
        : SourceVisibility.hidden,
  );
}

/// Whether the folders above [path] show what inherits from them.
Future<bool> _shownAbove(Replica db, String volume, String path) async {
  final above = await db
      .customSelect(
        'SELECT visibility FROM device_folder WHERE volume = ?1 '
        "AND visibility <> 'inherit' AND path < ?2 "
        'AND substr(?2, 1, length(path)) = path ORDER BY path DESC LIMIT 1',
        variables: [Variable(volume), Variable(path)],
      )
      .getSingleOrNull();
  return above == null
      ? !await onlyChosen(db)
      : above.read<String>('visibility') == 'shown';
}

/// Shows [node] and everything below it: nothing there keeps a visibility of
/// its own.
Future<void> showEverything(Replica db, SourceNode node) =>
    db.transaction(() async {
      await _inheritBelow(db, node.volume, node.key);
      await show(db, node.volume, node.key, shown: true);
    });

/// Shows [node] and hides everything else in the node above it, which then
/// shows partly; or, [everywhere], everything else of the device.
Future<void> hideOthers(
  Replica db,
  SourceNode node, {
  bool everywhere = false,
}) => db.transaction(() async {
  final (volume, key) = switch (node.parent) {
    final parent? when !everywhere => (node.volume, parent),
    _ => ('', ''),
  };
  await _inheritBelow(db, volume, key);
  await show(db, volume, key, shown: false);
  await setVisibility(db, node.volume, node.key, SourceVisibility.shown);
});

/// Takes the own visibility of every folder below [path] of [volume], or of
/// every folder when [volume] is ''.
Future<void> _inheritBelow(Replica db, String volume, String path) =>
    db.customUpdate(
      "UPDATE device_folder SET visibility = 'inherit' WHERE ?1 = '' OR "
      '(volume = ?1 AND path > ?2 AND substr(path, 1, length(?2)) = ?2)',
      variables: [Variable(volume), Variable(path)],
      updates: {db.deviceFolder},
    );

/// Whether the library shows only the chosen device folders, rather than
/// every folder but the excluded.
Future<bool> onlyChosen(Replica db) async =>
    (await db.select(db.deviceFolderMode).getSingleOrNull())?.onlyChosen == 1;

/// The device folders the library keeps out, revealed or not.
Future<Set<int>> excludedFolders(Replica db) async => {
  for (final f in await db.excludedFolders().get()) f.id,
};

/// Shows only the chosen device folders [on], else every one but the
/// excluded.
Future<void> setOnlyChosen(Replica db, {required bool on}) =>
    _mode(db, DeviceFolderModeCompanion(onlyChosen: Value(on ? 1 : 0)));

/// Shows the device folders the library keeps out until [until], or no
/// more; the timeline marks their items.
Future<void> revealExcluded(Replica db, DateTime? until) => _mode(
  db,
  DeviceFolderModeCompanion(revealUntil: Value(until?.millisecondsSinceEpoch)),
);

Future<void> _mode(Replica db, DeviceFolderModeCompanion values) => db
    .into(db.deviceFolderMode)
    .insert(
      values.copyWith(id: const Value(0)),
      onConflict: DoUpdate((_) => values),
    );

/// The device folder of item [id]; 0 for none.
Future<int> _folderOf(Replica db, Uint8List id) async =>
    (await (db.select(
      db.localAsset,
    )..where((a) => a.id.equals(id))).getSingleOrNull())?.folder ??
    0;

/// Keeps the folder of the device item [item] out of the library.
Future<void> excludeFolderOf(Replica db, Uint8List item) async {
  final folder = await _folderOf(db, item);
  if (folder != 0) await showFolder(db, folder, shown: false);
}

/// The timeline items of the device folder of item [id], shown or not, as
/// the timeline orders them: what it swipes through when another app opens
/// it. None for an item of no device folder.
Future<List<TimelineItemData>> folderContextOf(
  Replica db,
  Uint8List id,
) async => switch (await _folderOf(db, id)) {
  0 => const [],
  final folder => await db.folderContext(folder).get(),
};

/// Forgets the device folder [id] and its settings; its items, while away,
/// belong to no folder until they come back.
Future<void> forgetFolder(Replica db, int id) => db.transaction(() async {
  await (db.update(db.localAsset)..where((a) => a.folder.equals(id))).write(
    const LocalAssetCompanion(folder: Value(0)),
  );
  await (db.delete(db.deviceFolder)..where((f) => f.id.equals(id))).go();
});

/// The device folders' settings by volume and path, the tree's own
/// visibilities and the mode, which a reinstall imports again (M1-33).
Future<Map<String, Object?>> exportDeviceFolders(Replica db) async => {
  'onlyChosen': await onlyChosen(db),
  'folders': [
    for (final f in await db.select(db.deviceFolder).get())
      {
        'volume': f.volume,
        'path': f.path,
        'name': f.name,
        'visibility': f.visibility,
      },
  ],
};

/// Restores what [exportDeviceFolders] gave, over the folders' settings.
Future<void> importDeviceFolders(Replica db, Map<String, Object?> json) =>
    db.transaction(() async {
      await setOnlyChosen(db, on: json['onlyChosen'] == true);
      for (final f in (json['folders']! as List).cast<Map<String, Object?>>()) {
        final values = DeviceFolderCompanion(
          visibility: Value(f['visibility']! as String),
          fresh: const Value(0),
        );
        await db
            .into(db.deviceFolder)
            .insert(
              values.copyWith(
                volume: Value(f['volume']! as String),
                path: Value(f['path']! as String),
                name: Value(f['name']! as String),
              ),
              onConflict: DoUpdate(
                (_) => values,
                target: [db.deviceFolder.volume, db.deviceFolder.path],
              ),
            );
      }
    });
