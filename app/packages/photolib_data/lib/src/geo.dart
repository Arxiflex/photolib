import 'dart:typed_data';

import 'package:drift/drift.dart' show Variable;
import 'package:photolib_data/src/replica.dart';

/// The located items of the library, one per photo as the timeline shows
/// them: a device item's position or else its asset's (ADR-0267), by position
/// in these lists, which a `MapIndex` names its assets by.
class GeoPoints {
  /// Points with the columns [ids], [cloud], [latitudes], [longitudes] and
  /// [times] (seconds), all as long.
  GeoPoints({
    required this.ids,
    required this.cloud,
    required this.latitudes,
    required this.longitudes,
    required this.times,
  });

  /// The id of each item: a device item's, or an asset's where [cloud].
  final List<Uint8List> ids;

  /// 1 where the item is an asset no device item shows, else 0.
  final Uint8List cloud;

  /// Degrees.
  final Float64List latitudes;

  /// Degrees.
  final Float64List longitudes;

  /// Capture times in seconds since the epoch.
  final List<int> times;

  /// How many items.
  int get length => ids.length;
}

/// The items of [db] that have a position and that the library shows: the
/// device's present, untrashed ones outside hidden folders, hidden and
/// archived only when [veiled], and the account's assets that no device item
/// shows (as `cloud_item` does).
Future<GeoPoints> geoPoints(Replica db, {bool veiled = false}) async {
  final rows = await db
      .customSelect(
        'SELECT id, lat, lon, COALESCE(taken_utc, taken, mtime) / 1000 AS t, '
        "0 AS cloud FROM local_asset WHERE state = 'present' AND "
        'trashed = 0 AND tile < 2 AND lat IS NOT NULL AND lon IS NOT NULL '
        'AND (?1 OR hidden + archived = 0) '
        'AND folder NOT IN (SELECT id FROM hidden_folder) '
        'UNION ALL SELECT id, lat, lon, COALESCE(taken_utc, created_at) / 1000, '
        '1 FROM asset WHERE lat IS NOT NULL AND lon IS NOT NULL AND '
        'trashed_at IS NULL AND archived = 0 AND locked = 0 AND on_device = 0 '
        "AND media_kind IN ('image', 'video') "
        'AND +library_id IN (SELECT id FROM library)',
        variables: [Variable.withBool(veiled)],
        readsFrom: {db.localAsset, db.asset},
      )
      .get();
  final ids = <Uint8List>[];
  final cloud = Uint8List(rows.length);
  final lat = Float64List(rows.length);
  final lon = Float64List(rows.length);
  final time = List<int>.filled(rows.length, 0);
  for (var i = 0; i < rows.length; i++) {
    final row = rows[i].data;
    ids.add(row['id']! as Uint8List);
    lat[i] = (row['lat']! as num).toDouble();
    lon[i] = (row['lon']! as num).toDouble();
    time[i] = (row['t'] as num?)?.toInt() ?? 0;
    cloud[i] = (row['cloud']! as num).toInt();
  }
  return GeoPoints(
    ids: ids,
    cloud: cloud,
    latitudes: lat,
    longitudes: lon,
    times: time,
  );
}
