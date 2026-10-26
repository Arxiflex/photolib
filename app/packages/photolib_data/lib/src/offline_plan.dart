// tool/single_writer_lint.dart: the store's own files import each other
// by relative paths.
// ignore_for_file: always_use_package_imports

import 'package:drift/drift.dart';

import 'offline_media.dart' show OfflineMedia;
import 'offline_policy.dart';
import 'replica.dart';

/// A file of the server that the plan has the device keep.
class PlannedFile {
  /// A file of [asset] in [role] for [pin].
  const PlannedFile({
    required this.asset,
    required this.role,
    required this.size,
    required this.hash,
    required this.pin,
    required this.private,
  });

  /// The asset, as 16 bytes.
  final Uint8List asset;

  /// The file's role: `thumb_s`, `thumb_m`, `preview`, `r1` or `original`.
  final String role;

  /// Its size on the server, in bytes.
  final int size;

  /// The hash of its content in hex, as the replica has it.
  final String hash;

  /// The pin it is kept for, or [OfflinePin.libraryId].
  final String pin;

  /// Whether the server holds only ciphertext of it (a private library): the
  /// device keeps the same bytes, and opens them only to show them.
  final bool private;

  /// The asset in hex.
  String get assetHex => _hex(asset);

  /// Names the file's content in the offline store: an edit is a new key, and
  /// the old one is dropped with the next plan.
  String get key => OfflineMedia.keyOf(assetHex, role, hash);
}

/// What the device keeps for a policy and its pins, in the order it gets it.
class OfflinePlan {
  /// The plan of [files].
  const OfflinePlan(this.files);

  /// The files, the most wanted first: for each pin in turn the tiles of all
  /// its items, then their previews, then videos' proxies, then originals;
  /// last the library's.
  final List<PlannedFile> files;

  /// The files that fit [budget] bytes in the order of the plan, a file that
  /// does not fit skipped for smaller ones after it, where [sealed] says how
  /// many bytes a file of a size takes on disk.
  ({List<PlannedFile> chosen, List<PlannedFile> left, int bytes, int leftBytes})
  within(int budget, int Function(int size) sealed) {
    final chosen = <PlannedFile>[];
    final left = <PlannedFile>[];
    var bytes = 0;
    var leftBytes = 0;
    for (final file in files) {
      final take = sealed(file.size);
      if (bytes + take <= budget) {
        chosen.add(file);
        bytes += take;
      } else {
        left.add(file);
        leftBytes += take;
      }
    }
    return (chosen: chosen, left: left, bytes: bytes, leftBytes: leftBytes);
  }
}

const _tier = {
  'thumb_s': 0,
  'thumb_m': 1,
  'preview': 2,
  'r1': 3,
  'original': 4,
};

List<String> _roles(Keep keep, {required bool video}) => [
  if (keep != Keep.nothing) ...['thumb_s', 'thumb_m', 'preview'],
  if (keep != Keep.nothing && video) 'r1',
  if (keep == Keep.originals) 'original',
];

/// The plan of [policy] for [pins] over the assets of the replica [db]: each
/// pin's assets in their order (an album's own, a person's and the library's
/// newest first), with the files the server has for them, the library at
/// [StoragePolicy.library] after the pins. [search] says which assets a
/// search pin's results are; nothing is kept beyond [ceiling] (a browser keeps
/// no originals). A file two pins want is planned for the first.
Future<OfflinePlan> planOffline(
  Replica db,
  StoragePolicy policy,
  List<OfflinePin> pins, {
  Future<List<Uint8List>> Function(OfflinePin pin)? search,
  Keep ceiling = Keep.originals,
}) async {
  Keep capped(Keep keep) => keep.index <= ceiling.index ? keep : ceiling;
  final files = <PlannedFile>[];
  final seen = <String>{};
  Future<void> add(
    String pin,
    Keep keep,
    Future<List<_Row>> Function() rows,
  ) async {
    if (keep == Keep.nothing) return;
    final assets = <String, List<_Row>>{};
    for (final row in await rows()) {
      assets.putIfAbsent(row.assetHex, () => []).add(row);
    }
    for (final tier in [0, 1, 2, 3, 4]) {
      for (final rows in assets.values) {
        final video = rows.first.video;
        final wanted = _roles(keep, video: video);
        for (final row in rows) {
          if (_tier[row.role] != tier || !wanted.contains(row.role)) continue;
          final file = PlannedFile(
            asset: row.asset,
            role: row.role,
            size: row.size,
            hash: row.hash,
            pin: pin,
            private: row.private,
          );
          if (seen.add(file.key)) files.add(file);
        }
      }
    }
  }

  if (policy.pinsActive) {
    for (final pin in pins) {
      if (pin.kind == PinKind.library) continue;
      await add(
        pin.id,
        capped(policy.keepOf(pin)),
        () => _pinRows(db, pin, search),
      );
    }
  }
  // The whole library pinned counts as the baseline at its own depth.
  final library = pins.where((p) => p.kind == PinKind.library).firstOrNull;
  final keep = library != null && policy.pinsActive
      ? _more(policy.library, policy.keepOf(library))
      : policy.library;
  await add(OfflinePin.libraryId, capped(keep), () => _libraryRows(db));
  return OfflinePlan(files);
}

Keep _more(Keep a, Keep b) => a.index >= b.index ? a : b;

class _Row {
  _Row({
    required this.asset,
    required this.video,
    required this.private,
    required this.role,
    required this.size,
    required this.hash,
  });

  final Uint8List asset;
  final bool video;
  final bool private;
  final String role;
  final int size;
  final String hash;

  late final String assetHex = _hex(asset);
}

const _select =
    'SELECT a.id AS asset, a.media_kind AS kind, l.privacy AS privacy, '
    'f.role AS role, f.size AS size, f.content_hash AS hash '
    'FROM asset a JOIN library l ON l.id = a.library_id '
    'JOIN asset_file f ON f.asset_id = a.id '
    "AND f.state = 'present' AND f.content_hash IS NOT NULL ";
const _live = 'a.trashed_at IS NULL AND a.locked = 0 ';

List<_Row> _rows(List<QueryRow> rows) => [
  for (final r in rows)
    _Row(
      asset: r.read<Uint8List>('asset'),
      video: r.read<String>('kind') == 'video',
      private: r.read<String>('privacy') == 'private',
      role: r.read<String>('role'),
      size: r.read<int>('size'),
      hash: _hex(r.read<Uint8List>('hash')),
    ),
];

const _wantedRoles = "('thumb_s', 'thumb_m', 'preview', 'r1', 'original')";

Future<List<_Row>> _libraryRows(Replica db) => db
    .customSelect(
      '$_select AND f.role IN $_wantedRoles WHERE $_live'
      'ORDER BY COALESCE(a.taken_utc, a.created_at) DESC, a.id, f.role',
      readsFrom: {db.asset, db.assetFile, db.library},
    )
    .get()
    .then(_rows);

Future<List<_Row>> _pinRows(
  Replica db,
  OfflinePin pin,
  Future<List<Uint8List>> Function(OfflinePin pin)? search,
) async {
  final target = switch (pin.target) {
    final t? => Uint8List.fromList(t),
    null => null,
  };
  switch (pin.kind) {
    case PinKind.album:
      return _rows(
        await db
            .customSelect(
              '$_select AND f.role IN $_wantedRoles '
              'JOIN album_item i ON i.asset_id = a.id '
              "AND i.album_id = ?1 AND i.kind = 'asset' WHERE $_live"
              'ORDER BY i.sort_key, i.id, f.role',
              variables: [Variable(target)],
              readsFrom: {db.asset, db.assetFile, db.library, db.albumItem},
            )
            .get(),
      );
    case PinKind.person:
      return _rows(
        await db
            .customSelect(
              '$_select AND f.role IN $_wantedRoles '
              'JOIN (SELECT asset_id, MIN(rowid) AS first FROM face '
              'WHERE person_id = ?1 OR person_id IN '
              '(SELECT id FROM person WHERE merged_into = ?1) '
              'GROUP BY asset_id) m ON m.asset_id = a.id '
              'WHERE $_live'
              'ORDER BY COALESCE(a.taken_utc, a.created_at) DESC, a.id, f.role',
              variables: [Variable(target)],
              readsFrom: {db.asset, db.assetFile, db.library, db.face},
            )
            .get(),
      );
    case PinKind.search:
      final ids = await search?.call(pin) ?? const <Uint8List>[];
      final rows = <_Row>[];
      for (var i = 0; i < ids.length; i += 500) {
        final chunk = ids.sublist(
          i,
          i + 500 > ids.length ? ids.length : i + 500,
        );
        final found = _rows(
          await db
              .customSelect(
                '$_select AND f.role IN $_wantedRoles '
                'WHERE $_live AND a.id IN '
                '(${List.filled(chunk.length, '?').join(',')})',
                variables: [for (final id in chunk) Variable(id)],
                readsFrom: {db.asset, db.assetFile, db.library},
              )
              .get(),
        );
        rows.addAll(found);
      }
      // The results' own order.
      final rank = {for (final (i, id) in ids.indexed) _hex(id): i};
      return rows..sort((a, b) {
        final c = (rank[a.assetHex] ?? 0).compareTo(rank[b.assetHex] ?? 0);
        return c != 0 ? c : a.role.compareTo(b.role);
      });
    case PinKind.asset:
      return _rows(
        await db
            .customSelect(
              '$_select AND f.role IN $_wantedRoles '
              'WHERE $_live AND a.id = ?1 ORDER BY f.role',
              variables: [Variable(target)],
              readsFrom: {db.asset, db.assetFile, db.library},
            )
            .get(),
      );
    case PinKind.library:
      return await _libraryRows(db);
  }
}

String _hex(List<int> bytes) =>
    [for (final b in bytes) b.toRadixString(16).padLeft(2, '0')].join();

/// The server's assets, neither trashed nor locked, whose file names hold
/// [text] in any case: what a search pin finds that the device does not
/// index. `%` and `_` in [text] match themselves.
Future<List<Uint8List>> assetsNamed(Replica db, String text) async {
  final needle = text.trim();
  if (needle.isEmpty) return const [];
  final escaped = needle
      .replaceAll(r'\', r'\\')
      .replaceAll('%', r'\%')
      .replaceAll('_', r'\_');
  final rows = await db
      .customSelect(
        'SELECT id FROM asset a WHERE $_live '
        r"AND a.original_filename LIKE ?1 ESCAPE '\' "
        'ORDER BY COALESCE(a.taken_utc, a.created_at) DESC, a.id',
        variables: [Variable('%$escaped%')],
        readsFrom: {db.asset},
      )
      .get();
  return [for (final r in rows) r.read<Uint8List>('id')];
}

/// Fires when something a plan reads changes: assets, their files, albums'
/// items or faces.
Stream<void> planChanges(Replica db) => db.tableUpdates(
  TableUpdateQuery.onAllTables([db.asset, db.assetFile, db.albumItem, db.face]),
);

/// The people the user named and shows, not merged into another, by name,
/// with how many of the server's photos each is in: what a person pin picks
/// from.
Future<List<({Uint8List id, String name, int photos})>> namedPeople(
  Replica db,
) async {
  final rows = await db
      .customSelect(
        'SELECT p.id AS id, p.name AS name, '
        '(SELECT count(DISTINCT f.asset_id) FROM face f '
        'WHERE f.person_id = p.id OR f.person_id IN '
        '(SELECT m.id FROM person m WHERE m.merged_into = p.id)) AS photos '
        "FROM person p WHERE p.name IS NOT NULL AND p.name <> '' "
        'AND p.hidden = 0 AND p.merged_into IS NULL '
        'ORDER BY p.name COLLATE NOCASE, p.id',
        readsFrom: {db.person, db.face},
      )
      .get();
  return [
    for (final r in rows)
      (
        id: r.read<Uint8List>('id'),
        name: r.read<String>('name'),
        photos: r.read<int>('photos'),
      ),
  ];
}
