// tool/single_writer_lint.dart: the store's own files import each other
// by relative paths.
// ignore_for_file: always_use_package_imports

import 'package:drift/drift.dart';

import 'media_store.dart' show uuidv7;
import 'replica.dart';

/// The owner of the albums this device makes until an account adopts them
/// through the outbox with their ids (M2, ADR-0217): the nil UUID.
final Uint8List localOwner = Uint8List(16);

const _digits =
    '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz';

/// A fractional index (docs/04-domain-model.md §5) that sorts as text after
/// [before] and before [after], either absent at its end: base-62 digits that
/// never end in the lowest, so there is always room between two keys.
String keyBetween(String? before, String? after) {
  final a = before ?? '';
  if (after != null && a.compareTo(after) >= 0) {
    throw ArgumentError('$before is not before $after');
  }
  final key = StringBuffer();
  for (var i = 0; ; i++) {
    final lo = i < a.length ? _digits.indexOf(a[i]) : 0;
    final hi = after != null && i < after.length
        ? _digits.indexOf(after[i])
        : _digits.length;
    if (hi - lo > 1) return '$key${_digits[(lo + hi) ~/ 2]}';
    key.write(_digits[lo]);
    // Past the first digit that differs, anything after a's rest will do.
    if (hi > lo) {
      final rest = a.length > i + 1 ? a.substring(i + 1) : null;
      return '$key${keyBetween(rest, null)}';
    }
  }
}

/// An album folder or an album among its siblings, with how many entries or
/// items it holds and, for an album, the item its tile shows.
typedef AlbumEntry = ({
  Uint8List id,
  bool folder,
  String name,
  int items,
  TimelineItemData? cover,
});

/// Adds a folder named [name] to the album folder [parent], or to the top,
/// and returns its id.
Future<Uint8List> createAlbumFolder(
  Replica db,
  String name, {
  Uint8List? parent,
}) async {
  final id = uuidv7();
  final last = await db
      .customSelect(
        'SELECT max(sort_key) AS k FROM album_folder WHERE parent_id IS ?1',
        variables: [Variable(parent)],
      )
      .getSingle();
  await db
      .into(db.albumFolder)
      .insert(
        AlbumFolderCompanion.insert(
          id: id,
          ownerId: localOwner,
          parentId: Value(parent),
          name: name,
          sortKey: keyBetween(last.read<String?>('k'), null),
        ),
      );
  return id;
}

/// Adds an album titled [title] to the album folder [folder], or to the top,
/// and returns its id.
Future<Uint8List> createAlbum(
  Replica db,
  String title, {
  Uint8List? folder,
}) async {
  final id = uuidv7();
  await db
      .into(db.album)
      .insert(
        AlbumCompanion.insert(
          id: id,
          ownerId: localOwner,
          folderId: Value(folder),
          title: title,
          createdAt: DateTime.now().millisecondsSinceEpoch,
        ),
      );
  return id;
}

/// The folders, then the albums, in the album folder [parent] or at the top,
/// as they change: folders in their order, albums by when they were made.
Stream<List<AlbumEntry>> albumChildren(
  Replica db,
  Uint8List? parent, {
  bool veiled = false,
}) {
  const shown = '(?2 OR t.hidden = 0)';
  const present =
      'album_item i JOIN timeline_item t ON t.id = i.asset_id '
      'WHERE i.album_id = a.id AND $shown '
      'AND t.folder NOT IN (SELECT id FROM hidden_folder)';
  return db
      .customSelect(
        'SELECT id, 1 AS folder, name, sort_key AS k, '
        '(SELECT count(*) FROM album_folder c WHERE c.parent_id = f.id) + '
        '(SELECT count(*) FROM album a WHERE a.folder_id = f.id) AS items, '
        'NULL AS cover FROM album_folder f WHERE parent_id IS ?1 '
        "UNION ALL SELECT id, 0, title, printf('%020d', created_at), "
        '(SELECT count(*) FROM $present) + '
        '(SELECT count(*) FROM ${_serverInAlbum.replaceAll('?1', 'a.id')}), '
        'coalesce((SELECT id FROM '
        'timeline_item t WHERE t.id = cover_asset_id AND $shown), '
        '(SELECT i.asset_id FROM $present ORDER BY i.sort_key LIMIT 1)) '
        'FROM album a WHERE folder_id IS ?1 ORDER BY folder DESC, k',
        variables: [Variable(parent), Variable(veiled)],
        readsFrom: {
          db.albumFolder,
          db.album,
          db.albumItem,
          db.localAsset,
          db.asset,
          db.deviceFolder,
          db.deviceFolderMode,
        },
      )
      .watch()
      .asyncMap((rows) async {
        final ids = [for (final r in rows) ?r.read<Uint8List?>('cover')];
        final covers = {
          for (final c in await (db.select(
            db.timelineItem,
          )..where((t) => t.id.isIn(ids))).get())
            _hex(c.id): c,
        };
        return [
          for (final r in rows)
            (
              id: r.read<Uint8List>('id'),
              folder: r.read<int>('folder') == 1,
              name: r.read<String>('name'),
              items: r.read<int>('items'),
              cover: covers[_hex(r.read<Uint8List?>('cover'))],
            ),
        ];
      });
}

/// Every album, by title, with the names of the album folders it is in.
Future<List<({Uint8List id, String title, List<String> path})>> allAlbums(
  Replica db,
) async => [
  for (final a in await (db.select(
    db.album,
  )..orderBy([(a) => OrderingTerm(expression: a.title)])).get())
    (id: a.id, title: a.title, path: await albumPath(db, a.id)),
];

String _hex(Uint8List? id) => [
  for (final b in id ?? Uint8List(0)) b.toRadixString(16).padLeft(2, '0'),
].join();

/// The names of the album folders the album or folder [id] is in, from the
/// top.
Future<List<String>> albumPath(Replica db, Uint8List id) async {
  final rows = await db
      .customSelect(
        'WITH RECURSIVE up(id, name, depth) AS ( '
        'SELECT parent_id, NULL, 0 FROM album_folder WHERE id = ?1 '
        'UNION ALL SELECT folder_id, NULL, 0 FROM album WHERE id = ?1 '
        'UNION ALL SELECT f.parent_id, f.name, up.depth + 1 '
        'FROM album_folder f JOIN up ON f.id = up.id) '
        'SELECT name FROM up WHERE name IS NOT NULL ORDER BY depth DESC',
        variables: [Variable(id)],
      )
      .get();
  return [for (final r in rows) r.read<String>('name')];
}

/// Moves the album or album folder [id] into the folder [to], or to the top;
/// false, moving nothing, when [to] is the folder itself or inside it.
Future<bool> moveAlbumEntry(Replica db, Uint8List id, Uint8List? to) =>
    db.transaction(() async {
      if (to != null) {
        final inside = await db
            .customSelect(
              'WITH RECURSIVE up(id) AS (SELECT ?2 UNION ALL '
              'SELECT f.parent_id FROM album_folder f JOIN up ON f.id = up.id) '
              'SELECT count(*) AS n FROM up WHERE id = ?1',
              variables: [Variable(id), Variable(to)],
            )
            .getSingle();
        if (inside.read<int>('n') > 0) return false;
      }
      await (db.update(db.albumFolder)..where((f) => f.id.equals(id))).write(
        AlbumFolderCompanion(parentId: Value(to)),
      );
      await (db.update(db.album)..where((a) => a.id.equals(id))).write(
        AlbumCompanion(folderId: Value(to)),
      );
      return true;
    });

/// Appends the device items [ids] that the album [album] does not hold yet,
/// in that order. Until an account adopts the album its items name
/// `local_asset` rows (ADR-0217).
Future<void> addToAlbum(Replica db, Uint8List album, List<Uint8List> ids) =>
    db.transaction(() async {
      final items = await (db.select(
        db.albumItem,
      )..where((i) => i.albumId.equals(album))).get();
      final held = {for (final i in items) _hex(i.assetId)};
      var last = [
        for (final i in items) i.sortKey,
      ].fold<String?>(null, (a, b) => a == null || b.compareTo(a) > 0 ? b : a);
      for (final id in ids) {
        if (!held.add(_hex(id))) continue;
        last = keyBetween(last, null);
        await db
            .into(db.albumItem)
            .insert(
              AlbumItemCompanion.insert(
                id: uuidv7(),
                albumId: album,
                kind: 'asset',
                assetId: Value(id),
                sortKey: last,
              ),
            );
      }
    });

/// The albums the item [id] is in, by title, as they change: each with the
/// album folders above it, how many items it holds and whether others share
/// it.
Stream<
  List<
    ({Uint8List id, String title, List<String> path, int items, bool shared})
  >
>
itemAlbums(Replica db, Uint8List id) => db
    .customSelect(
      'SELECT a.id, a.title, (SELECT count(*) FROM album_item c '
      "WHERE c.album_id = a.id AND c.kind = 'asset') AS n, "
      'EXISTS (SELECT 1 FROM album_member m WHERE m.album_id = a.id) AS shared '
      'FROM album a WHERE a.id IN (SELECT album_id FROM album_item '
      "WHERE kind = 'asset' AND asset_id = ?1) ORDER BY a.title",
      variables: [Variable(id)],
      readsFrom: {db.album, db.albumItem, db.albumMember, db.albumFolder},
    )
    .watch()
    .asyncMap(
      (rows) => Future.wait([
        for (final r in rows)
          albumPath(db, r.read<Uint8List>('id')).then(
            (path) => (
              id: r.read<Uint8List>('id'),
              title: r.read<String>('title'),
              path: path,
              items: r.read<int>('n'),
              shared: r.read<bool>('shared'),
            ),
          ),
      ]),
    );

/// Takes the item [id] out of the album [album], and only that one.
Future<void> removeFromAlbum(Replica db, Uint8List album, Uint8List id) =>
    (db.delete(
      db.albumItem,
    )..where((i) => i.albumId.equals(album) & i.assetId.equals(id))).go();

// The server's assets in an album that no present device item shows (the
// timeline's cloud_item rule): the same album_item rows as device items.
const _serverInAlbum =
    'album_item i JOIN asset s ON s.id = i.asset_id '
    'WHERE i.album_id = ?1 AND s.trashed_at IS NULL AND s.locked = 0 '
    "AND s.on_device = 0 AND s.media_kind IN ('image', 'video')";

// An asset of the server as the columns of local_asset, in their order, so that
// an album lists it with the device items: source `server`, the asset's own id.
const _serverAsLocal =
    "SELECT s.id AS id, 'server' AS source, '' AS volume, '' AS source_id, "
    'NULL AS generation, COALESCE(s.file_size_total, 0) AS size, '
    's.created_at AS mtime, NULL AS content_hash, s.id AS asset_id, '
    's.original_filename AS path, NULL AS file_id, '
    "'present' AS state, NULL AS name, NULL AS bucket_id, "
    'NULL AS bucket_name, '
    "CASE s.media_kind WHEN 'video' THEN 'video/*' ELSE 'image/*' END AS mime, "
    's.taken_utc AS taken, s.width AS width, s.height AS height, '
    's.orientation AS orientation, s.duration_ms AS duration_ms, '
    '0 AS favorite, 0 AS trashed, NULL AS expires, NULL AS extracted, '
    's.taken_local AS taken_local, s.tz_offset_min AS tz_offset_min, '
    's.taken_utc AS taken_utc, s.time_source AS time_source, '
    's.time_confidence AS time_confidence, s.time_precision AS time_precision, '
    's.lat AS lat, s.lon AS lon, s.make AS make, s.model AS model, '
    's.facets AS facets, NULL AS cloud_id, NULL AS burst_id, 0 AS edited, '
    's.created_at AS added, s.thumbhash AS thumbhash, '
    'NULL AS motion_offset, NULL AS motion_length, s.fps AS frame_rate, '
    'NULL AS projection, NULL AS crop, NULL AS stereo, 0 AS folder, '
    'NULL AS heading, 0 AS hidden, s.archived AS archived, NULL AS bin, '
    'NULL AS fingerprint, 0 AS tile, i.sort_key AS album_key '
    'FROM $_serverInAlbum';

/// The present items of the album [album], but those of the folders the
/// library hides, in its own order, as they change: the device's, and the
/// server's assets that no device item shows, as rows of source `server`
/// (their tiles are the server's renditions, ADR-0267).
Stream<List<LocalAssetData>> albumItems(
  Replica db,
  Uint8List album, {
  bool veiled = false,
}) => db
    .customSelect(
      'SELECT * FROM (SELECT a.*, i.sort_key AS album_key '
      'FROM album_item i JOIN local_asset a ON a.id = i.asset_id '
      "WHERE i.album_id = ?1 AND a.state = 'present' AND a.trashed = 0 "
      'AND (?2 OR a.hidden = 0) '
      'AND a.folder NOT IN (SELECT id FROM hidden_folder) '
      'UNION ALL $_serverAsLocal) ORDER BY album_key',
      variables: [Variable(album), Variable(veiled)],
      readsFrom: {
        db.albumItem,
        db.localAsset,
        db.asset,
        db.deviceFolder,
        db.deviceFolderMode,
      },
    )
    .map((row) => db.localAsset.map(row.data))
    .watch();

/// Makes the device item [item] the cover of the album [album].
Future<void> setAlbumCover(Replica db, Uint8List album, Uint8List item) =>
    (db.update(db.album)..where((a) => a.id.equals(album))).write(
      AlbumCompanion(coverAssetId: Value(item)),
    );

/// What the account hides of the album [album] (ORG-17), as it changes:
/// `shared` is whether the account's library holds the album, which the server
/// can hide it for, not an album only this device made.
Stream<({bool timeline, bool memories, bool shared})> albumHiding(
  Replica db,
  Uint8List album,
) => db
    .customSelect(
      'SELECT coalesce((SELECT hide_from_timeline FROM album_user_state '
      'WHERE album_id = ?1), 0) AS t, coalesce((SELECT hide_from_memories '
      'FROM album_user_state WHERE album_id = ?1), 0) AS m, '
      'coalesce((SELECT owner_id <> ?2 FROM album WHERE id = ?1), 0) AS s',
      variables: [Variable(album), Variable(localOwner)],
      readsFrom: {db.albumUserState, db.album},
    )
    .watchSingle()
    .map(
      (r) => (
        timeline: r.read<int>('t') != 0,
        memories: r.read<int>('m') != 0,
        shared: r.read<int>('s') != 0,
      ),
    );

/// The sort mode and layout of the album [album].
Future<(String, String)> albumView(Replica db, Uint8List album) async {
  final a = await (db.select(
    db.album,
  )..where((a) => a.id.equals(album))).getSingle();
  return (a.sortMode, a.layout);
}

/// Keeps [sort] and [layout] as the album [album]'s.
Future<void> setAlbumView(
  Replica db,
  Uint8List album, {
  required String sort,
  required String layout,
}) => (db.update(db.album)..where((a) => a.id.equals(album))).write(
  AlbumCompanion(sortMode: Value(sort), layout: Value(layout)),
);
