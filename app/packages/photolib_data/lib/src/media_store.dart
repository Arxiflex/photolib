import 'dart:convert';
import 'dart:math';

import 'package:drift/drift.dart';
import 'package:photolib_data/photolib_data.dart' show isJunk;
import 'package:photolib_data/src/replica.dart';
import 'package:photolib_log/photolib_log.dart';

/// What the user lets the app read of the device's media.
enum MediaAccess { none, partial, full }

/// A finalised item of a MediaStore volume, trashed or not; MediaStore never reports `IS_PENDING` rows.
final class MediaStoreItem {
  const MediaStoreItem({
    required this.id,
    required this.generation,
    required this.size,
    required this.modified,
    required this.name,
    required this.mime,
    this.path = '',
    this.bucketId = '',
    this.bucketName = '',
    this.taken,
    this.width,
    this.height,
    this.orientation,
    this.durationMs,
    this.favorite = false,
    this.trashed = false,
    this.expires,
  });

  /// `_ID` and `GENERATION_ADDED`, which together name one item even when MediaStore reuses an id.
  final int id, generation;
  final int size;

  /// `DATE_MODIFIED`, `DATE_TAKEN` and, while [trashed], `DATE_EXPIRES`, in milliseconds.
  final int modified;
  final int? taken, expires;
  final String name, mime, path, bucketId, bucketName;
  final int? width, height, orientation, durationMs;
  final bool favorite, trashed;
}

/// Android's MediaStore as the indexer reads it (docs/10-client-app.md §5.2); the app reads it over a platform
/// channel (app/lib/core/media_store.dart).
abstract interface class MediaStore {
  Future<MediaAccess> access();

  /// A random id kept out of backups, so restored app data comes with another one.
  Future<String> installId();

  /// The mounted volumes, by MediaStore name.
  Future<List<String>> volumes();

  /// The directory [volume] is mounted at, from which its files can be read by path.
  Future<String?> root(String volume);
  Future<String> version(String volume);
  Future<int> generation(String volume);
  Future<int> count(String volume);
  Future<List<int>> ids(String volume);

  /// At most [limit] items of [volume] modified after generation [since], with an id above [after], by id.
  Future<List<MediaStoreItem>> items(
    String volume, {
    required int since,
    required int after,
    required int limit,
  });
}

const _source = 'mediastore';

/// Keeps the `local_asset` rows of [store] what it shows, writing a transaction per page of [page] items.
class MediaStoreIndexer {
  MediaStoreIndexer(this.db, this.store, {this.page = 2000});

  final Replica db;
  final MediaStore store;
  final int page;

  /// Whether the folders this sync finds are new to the user: not on the
  /// first index after the grant.
  var _fresh = false;

  /// Brings the index up to date with [store]: nothing without access, everything again after a change of install.
  /// Items of volumes that are not mounted turn offline. A volume is scanned in full when it is new or comes back,
  /// with partial access, or when its MediaStore version changed or its generation went back (its database was
  /// rebuilt); otherwise only what changed since the stored generation is read, and the ids only when the counts show
  /// deletions.
  Future<void> sync() async {
    final access = await store.access();
    // MediaStore shows nothing then, which must not read as everything deleted.
    if (access == MediaAccess.none) return;
    final install = await store.installId();
    final cursors = {
      for (final c in await (db.select(
        db.volumeCursor,
      )..where((c) => c.source.equals(_source))).get())
        c.volume: c,
    };
    if (cursors.values.any((c) => c.installId != install)) {
      // App data restored from another install: its ids, hashes and links name other files (Immich #10546).
      await db.transaction(() async {
        await db.customStatement(
          'DELETE FROM backup_state WHERE local_asset_id IN (SELECT id FROM local_asset WHERE source = ?)',
          [_source],
        );
        await (db.delete(
          db.localAsset,
        )..where((a) => a.source.equals(_source))).go();
        await (db.delete(
          db.volumeCursor,
        )..where((c) => c.source.equals(_source))).go();
      });
      cursors.clear();
    }
    _fresh = cursors.isNotEmpty;
    final mounted = await store.volumes();
    await (db.update(db.localAsset)..where(
          (a) =>
              a.source.equals(_source) &
              a.volume.isNotIn(mounted) &
              a.state.equals('present'),
        ))
        .write(const LocalAssetCompanion(state: Value('offline')));
    for (final volume in mounted) {
      // Read first: what changes during the scan has a later generation.
      final version = await store.version(volume);
      final generation = await store.generation(volume);
      final cursor = cursors[volume];
      final comparable =
          cursor != null &&
          cursor.version == version &&
          cursor.generation <= generation;
      // A selection can grow by items of any generation.
      final returning = comparable && await _returning(volume);
      const Logger('photolib.index').info(
        'mediastore sync',
        fields: {
          'volume': volume,
          'access': access.name,
          'generation': generation,
          'from': cursor?.generation,
          'read': !comparable || access == MediaAccess.partial || returning
              ? 'all items'
              : 'changes',
          'why': cursor == null
              ? 'first sync'
              : !comparable
              ? 'version changed or generation went back'
              : access == MediaAccess.partial
              ? 'partial access'
              : returning
              ? 'volume is back'
              : 'generation',
        },
      );
      if (!comparable || access == MediaAccess.partial || returning) {
        await _full(volume, trustIds: comparable);
      } else {
        if (generation > cursor.generation) {
          await _delta(volume, cursor.generation);
        }
        await _sweep(volume);
      }
      await db
          .into(db.volumeCursor)
          .insertOnConflictUpdate(
            VolumeCursorCompanion.insert(
              source: _source,
              volume: volume,
              installId: install,
              version: version,
              generation: generation,
              root: Value(await store.root(volume)),
            ),
          );
    }
  }

  Expression<bool> _indexed(String volume) =>
      db.localAsset.source.equals(_source) &
      db.localAsset.volume.equals(volume);

  Future<bool> _returning(String volume) async =>
      await (db.select(db.localAsset)
            ..where((a) => _indexed(volume) & a.state.equals('offline'))
            ..limit(1))
          .getSingleOrNull() !=
      null;

  /// Reads every item of [volume] and matches each to its row by id and generation when [trustIds], else or failing
  /// that by its file, as a card MediaStore indexed again has new ids. Deletes the rows left unmatched.
  Future<void> _full(String volume, {required bool trustIds}) async {
    final rows = await (db.select(
      db.localAsset,
    )..where((_) => _indexed(volume))).get();
    final byId = {
      if (trustIds)
        for (final r in rows) r.sourceId: r,
    };
    final byFile = {
      for (final r in rows) _file(r.path, r.name, r.size, r.mtime): r,
    };
    final seen = Set<LocalAssetData>.identity();
    // The ids of another database may name other items: every row gets its id back from the item it matches.
    if (!trustIds) {
      await db.customUpdate(
        "UPDATE local_asset SET source_id = '~' || hex(id) WHERE source = ? AND volume = ?",
        variables: [Variable(_source), Variable(volume)],
        updates: {db.localAsset},
      );
    }
    await _pages(volume, 0, (items) async {
      final folders = await _folders(volume, items);
      await db.batch((b) {
        for (final item in items) {
          final holder = byId['${item.id}'];
          var row = holder?.generation == '${item.generation}'
              ? holder
              : byFile[_file(item.path, item.name, item.size, item.modified)];
          if (row != null && !seen.add(row)) row = null;
          if (holder != null && holder != row && !seen.contains(holder)) {
            _park(b, holder);
          }
          _write(b, volume, item, row, folders);
        }
      });
    });
    await _delete([
      for (final r in rows)
        if (!seen.contains(r)) r.id,
    ]);
  }

  /// Reads the items of [volume] changed after generation [since].
  Future<void> _delta(String volume, int since) =>
      _pages(volume, since, (items) async {
        final rows = {
          for (final r
              in await (db.select(db.localAsset)..where(
                    (a) =>
                        _indexed(volume) &
                        a.sourceId.isIn([for (final i in items) '${i.id}']),
                  ))
                  .get())
            r.sourceId: r,
        };
        final folders = await _folders(volume, items);
        await db.batch((b) {
          for (final item in items) {
            final holder = rows['${item.id}'];
            final same = holder?.generation == '${item.generation}';
            // Another item under the same id: the sweep deletes the parked one.
            if (holder != null && !same) _park(b, holder);
            _write(b, volume, item, same ? holder : null, folders);
          }
        });
      });

  Future<void> _pages(
    String volume,
    int since,
    Future<void> Function(List<MediaStoreItem>) apply,
  ) async {
    for (var after = 0; ;) {
      final items = await store.items(
        volume,
        since: since,
        after: after,
        limit: page,
      );
      await apply(items);
      if (items.length < page) return;
      after = items.last.id;
    }
  }

  /// The device folders of [items] by path, adding those new to [volume]:
  /// junk out of the library, others new to the user after the first index.
  Future<Map<String, int>> _folders(
    String volume,
    List<MediaStoreItem> items,
  ) async {
    final names = {for (final i in items) i.path: i.bucketName};
    await db.batch((b) {
      for (final MapEntry(key: path, value: name) in names.entries) {
        final junk = isJunk(path);
        b.insert(
          db.deviceFolder,
          DeviceFolderCompanion.insert(
            volume: volume,
            path: path,
            name: Value(name),
            visibility: Value(junk ? 'hidden' : 'inherit'),
            fresh: Value(_fresh && !junk ? 1 : 0),
          ),
          mode: InsertMode.insertOrIgnore,
        );
      }
    });
    final rows = db.select(db.deviceFolder)
      ..where((f) => f.volume.equals(volume) & f.path.isIn(names.keys));
    return {for (final f in await rows.get()) f.path: f.id};
  }

  /// Frees the id of [row], which another item took.
  void _park(Batch b, LocalAssetData row) => b.customStatement(
    "UPDATE local_asset SET source_id = '~' || hex(id) WHERE id = ?",
    [row.id],
  );

  /// Removes the items deleted since the last sweep, which MediaStore reports without a generation.
  Future<void> _sweep(String volume) async {
    final count = countAll();
    final indexed =
        await (db.selectOnly(db.localAsset)
              ..addColumns([count])
              ..where(_indexed(volume)))
            .getSingle();
    if (indexed.read(count) == await store.count(volume)) return;
    // Diffed in SQLite: reading 100,000 rows back costs more than the whole delta may.
    final live = jsonEncode([for (final id in await store.ids(volume)) '$id']);
    await _delete(
      await db
          .customSelect(
            'SELECT id FROM local_asset WHERE source = ? AND volume = ? '
            'AND source_id NOT IN (SELECT value FROM json_each(?))',
            variables: [Variable(_source), Variable(volume), Variable(live)],
          )
          .map((r) => r.read<Uint8List>('id'))
          .get(),
    );
  }

  /// Deletes local assets and their backup state.
  Future<void> _delete(List<Uint8List> ids) => db.transaction(() async {
    for (var i = 0; i < ids.length; i += 500) {
      final chunk = ids.sublist(i, min(i + 500, ids.length));
      await (db.delete(
        db.backupState,
      )..where((s) => s.localAssetId.isIn(chunk))).go();
      await (db.delete(db.localAsset)..where((a) => a.id.isIn(chunk))).go();
    }
  });

  /// Writes [item] over [row], or as a new row. A changed file loses its hashes and the asset matched by them, and is
  /// extracted again.
  void _write(
    Batch b,
    String volume,
    MediaStoreItem item,
    LocalAssetData? row,
    Map<String, int> folders,
  ) {
    final changed =
        row != null && (row.size != item.size || row.mtime != item.modified);
    // MediaStore's NULLs never erase what extraction read in the same file.
    Value<int?> known(int? v) =>
        row != null && !changed ? Value.absentIfNull(v) : Value(v);
    final values = LocalAssetCompanion(
      source: const Value(_source),
      volume: Value(volume),
      sourceId: Value('${item.id}'),
      generation: Value('${item.generation}'),
      size: Value(item.size),
      mtime: Value(item.modified),
      name: Value(item.name),
      path: Value(item.path),
      bucketId: Value(item.bucketId),
      bucketName: Value(item.bucketName),
      mime: Value(item.mime),
      taken: Value(item.taken),
      width: known(item.width),
      height: known(item.height),
      orientation: known(item.orientation),
      durationMs: known(item.durationMs),
      // The index's favourites stay: one found again by its content has none
      // in MediaStore (ADR-0245).
      favorite: Value(item.favorite || row?.favorite == 1 ? 1 : 0),
      trashed: Value(item.trashed ? 1 : 0),
      expires: Value(item.expires),
      state: const Value('present'),
      folder: Value(folders[item.path] ?? 0),
    );
    if (row == null) {
      final id = uuidv7();
      return b.insert(
        db.localAsset,
        values.copyWith(id: Value(id), added: Value(uuidTime(id))),
      );
    }
    b.update(
      db.localAsset,
      changed
          ? values.copyWith(
              contentHash: const Value(null),
              fingerprint: const Value(null),
              assetId: const Value(null),
              extracted: const Value(null),
            )
          : values,
      where: (a) => a.id.equals(row.id),
    );
  }
}

String _file(String? path, String? name, int size, int mtime) =>
    '$path\u0000$name\u0000$size\u0000$mtime';

final _random = Random.secure();

/// The time in a UUIDv7, in ms since the epoch: when the device index first saw the item it names.
int uuidTime(Uint8List id) => id.take(6).fold(0, (t, b) => t * 256 + b);

/// A UUIDv7, without shifts wider than 32 bits so that it also runs in browsers.
Uint8List uuidv7() {
  final id = Uint8List(16);
  var ms = DateTime.now().millisecondsSinceEpoch;
  for (var i = 5; i >= 0; i--, ms ~/= 256) {
    id[i] = ms % 256;
  }
  for (var i = 6; i < 16; i++) {
    id[i] = _random.nextInt(256);
  }
  id[6] = 0x70 | id[6] & 0x0f;
  id[8] = 0x80 | id[8] & 0x3f;
  return id;
}
