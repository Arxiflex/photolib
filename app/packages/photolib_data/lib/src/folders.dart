import 'package:drift/drift.dart';

import 'package:photolib_data/src/replica.dart';

/// The folders a browser keeps with File System Access (docs/10-client-app.md §7.1, ADR-0082).
abstract interface class BrowserFolders {
  /// Asks the user for a folder and adds it under its name: null when the user cancelled, false when it is in the
  /// library, or inside or around a folder that is.
  Future<bool?> pick(Replica db);

  /// Asks the user again for access to the folder [root], which the browser may then grant on every visit, and scans
  /// it once granted.
  Future<void> allow(Replica db, String root);
}

/// Adds the folder [root], an absolute path, to the library; the folder indexer scans and watches it from then on.
/// Returns false, adding nothing, when it is already there, or inside or around a folder that is.
Future<bool> addFolder(Replica db, String root) => db.transaction(() async {
  final trimmed = root.replaceFirst(RegExp(r'(?<=.)[/\\]+$'), '');
  root = trimmed.endsWith(':') ? '$trimmed\\' : trimmed;
  bool within(String a, String b) =>
      a == b ||
      ['/', r'\'].any((s) => a.startsWith(b.endsWith(s) ? b : '$b$s'));
  for (final other in await db.select(db.mediaSource).get()) {
    if (within(root, other.root) || within(other.root, root)) return false;
  }
  await db
      .into(db.mediaSource)
      .insert(
        MediaSourceCompanion.insert(root: root, state: const Value('scanning')),
      );
  return true;
});

/// Removes the folder [root], its items and its folders' settings from the
/// library, never a file.
Future<void> removeFolder(Replica db, String root) => db.transaction(() async {
  await (db.delete(db.mediaSource)..where((s) => s.root.equals(root))).go();
  await (db.delete(db.deviceFolder)..where((f) => f.volume.equals(root))).go();
  final items = db.selectOnly(db.localAsset)
    ..addColumns([db.localAsset.id])
    ..where(
      db.localAsset.source.equals('folder') & db.localAsset.volume.equals(root),
    );
  await (db.delete(
    db.backupState,
  )..where((b) => b.localAssetId.isInQuery(items))).go();
  await (db.delete(
    db.localAsset,
  )..where((a) => a.source.equals('folder') & a.volume.equals(root))).go();
});

/// The folders in the library, in order, as they change.
Stream<List<MediaSourceData>> watchFolders(Replica db) => (db.select(
  db.mediaSource,
)..orderBy([(s) => OrderingTerm(expression: s.root)])).watch();

/// The present items of the folder [root], newest first as the timeline orders them, [limit] after the item [after].
Future<List<TimelineItemData>> folderTimeline(
  Replica db,
  String root, {
  TimelineItemData? after,
  int limit = -1,
}) => _folderItems(db, root, false, after, limit);

/// The present folder items without a ThumbHash, newest first as the
/// timeline orders them, [limit] after the item [after]: pages stay whole
/// while the warm-up saves hashes between them.
Future<List<TimelineItemData>> withoutThumbHash(
  Replica db, {
  TimelineItemData? after,
  int limit = 500,
}) => _folderItems(db, null, true, after, limit);

Future<List<TimelineItemData>> _folderItems(
  Replica db,
  String? root,
  bool hashless,
  TimelineItemData? after,
  int limit,
) => db
    .folderItems(
      root,
      hashless,
      after?.day ?? 1 << 62,
      after?.sortKey ?? 0,
      after?.id ?? Uint8List(0),
      limit,
    )
    .get();

/// Keeps the ThumbHashes of device items by their ids, in one transaction.
Future<void> saveThumbHashes(Replica db, Map<Uint8List, Uint8List> hashes) =>
    db.batch((batch) {
      for (final MapEntry(key: id, value: hash) in hashes.entries) {
        batch.update(
          db.localAsset,
          LocalAssetCompanion(thumbhash: Value(hash)),
          where: (a) => a.id.equals(id),
        );
      }
    });
