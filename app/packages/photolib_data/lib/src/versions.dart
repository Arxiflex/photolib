import 'dart:typed_data';

import 'package:drift/drift.dart' show Variable;
import 'package:photolib_data/src/replica.dart';

/// A version of an asset as the replica holds it (ADR-0391).
typedef VersionRow = ({
  Uint8List id,
  String kind,
  String label,
  Uint8List? recipe,
  DateTime createdAt,
  bool current,
});

/// The versions of the server asset that [id] is, or that the device item [id]
/// is linked to, oldest first; they change with the replica.
Stream<List<VersionRow>> watchVersions(Replica db, Uint8List id) => db
    .customSelect(
      'SELECT v.id, v.kind, v.label, v.recipe, v.created_at, '
      'v.id = a.current_version_id AS current FROM asset_version v '
      'JOIN asset a ON a.id = v.asset_id WHERE v.asset_id = '
      'coalesce((SELECT asset_id FROM local_asset WHERE id = ?1), ?1) '
      'ORDER BY v.created_at, v.id',
      variables: [Variable(id)],
      readsFrom: {db.assetVersion, db.asset, db.localAsset},
    )
    .watch()
    .map(
      (rows) => [
        for (final v in rows)
          (
            id: v.read<Uint8List>('id'),
            kind: v.read<String>('kind'),
            label: v.readNullable<String>('label') ?? '',
            recipe: v.readNullable<Uint8List>('recipe'),
            createdAt: DateTime.fromMillisecondsSinceEpoch(
              v.read<int>('created_at'),
            ),
            current: v.read<bool>('current'),
          ),
      ],
    );

/// The server asset that the item [id] is: its own id for a server asset, the
/// asset a device item is linked to otherwise, [id] again if it has none.
Future<Uint8List> serverAssetIdOf(Replica db, Uint8List id) async {
  final row = await db
      .customSelect(
        'SELECT coalesce((SELECT asset_id FROM local_asset WHERE id = ?1), '
        '?1) AS id',
        variables: [Variable(id)],
      )
      .getSingle();
  return row.read<Uint8List>('id');
}
