// What the benchmarks of tools/perf/budgets.json share: the synthlib
// fixtures loaded into a replica, their originals, and when a timeline shows.
import 'dart:convert';
import 'dart:io';

import 'package:image/image.dart' as img;
import 'package:material_ui/material_ui.dart';
import 'package:photolib/features/library/timeline/pages.dart';
import 'package:photolib/features/library/timeline/thumbnails.dart';
import 'package:photolib/features/library/timeline/timeline_view.dart';
import 'package:photolib_data/photolib_data.dart';

/// 64 small JPEGs of distinct colours in [path], the originals of every
/// timeline fixture's assets.
Directory writeOriginals(String path) {
  final originals = Directory(path)..createSync();
  for (var k = 0; k < 64; k++) {
    final image = img.Image(width: 256, height: 256);
    for (final p in image) {
      p
        ..r = (p.x + k * 37) % 256
        ..g = (p.y + k * 91) % 256
        ..b = (p.x + p.y + k * 13) % 256;
    }
    File('${originals.path}/$k.jpg').writeAsBytesSync(img.encodeJpg(image));
  }
  return originals;
}

/// Copies the fixture's tables into the replica. A timeline's assets become
/// the device index, files of [originals], and the result is null; else
/// `temp.view` gets the cells of the view the fixture stresses, and the
/// result is their number.
Future<int?> loadFixture(Replica db, Directory dir, String originals) async {
  final manifest = File('${dir.path}/manifest.json').readAsStringSync();
  final shape = (jsonDecode(manifest) as Map)['shape'];
  final timeline = shape != 'folders' && shape != 'albums';
  Future<void> run(String sql) => db.customStatement(sql);
  const blob = "unhex(replace(id, '-', ''))";
  await db.transaction(() async {
    for (final table in [
      'assets',
      if (shape == 'albums') ...['albums', 'album_items'],
    ]) {
      await _stage(db, File('${dir.path}/$table.csv'), 'csv_$table');
    }
    await run(
      'INSERT INTO asset (id, library_id, owner_id, original_filename, '
      'source, media_kind, width, height, taken_local, tz_offset_min, '
      "taken_utc, created_at, lat, lon) SELECT $blob, x'00', "
      "unhex(replace(owner_id, '-', '')), original_filename, 'scan', "
      "media_kind, width, height, nullif(taken_local, ''), "
      "nullif(tz_offset_min, ''), CAST(unixepoch(nullif(taken_local, ''), "
      "'subsec') * 1000 - ifnull(nullif(tz_offset_min, ''), 0) * 60000 "
      "AS INTEGER), 0, CAST(nullif(lat, '') AS REAL), "
      "CAST(nullif(lon, '') AS REAL) FROM temp.csv_assets",
    );
    if (timeline) {
      await db.customStatement(
        'INSERT INTO local_asset (id, source, volume, source_id, path, size, '
        'mtime, taken_local, tz_offset_min, taken_utc, extracted, added, '
        'lat, lon) '
        "SELECT id, 'folder', ?, hex(id), (rowid % 64) || '.jpg', 1, 0, "
        'taken_local, tz_offset_min, taken_utc, 1, 0, lat, lon FROM asset',
        [originals],
      );
      return;
    }
    await run(
      'CREATE TEMP TABLE view (pos INTEGER PRIMARY KEY, label TEXT, '
      'colour INTEGER)',
    );
    if (shape == 'folders') {
      await run(
        "INSERT INTO temp.view (label, colour) SELECT folder || ' · ' || "
        'count(*), 1 FROM temp.csv_assets GROUP BY folder ORDER BY folder',
      );
    } else {
      await run(
        'INSERT INTO album (id, owner_id, title, created_at) SELECT $blob, '
        "unhex(replace(owner_id, '-', '')), title, 0 FROM temp.csv_albums",
      );
      await run(
        'INSERT INTO album_item (id, album_id, kind, asset_id, sort_key) '
        "SELECT randomblob(16), unhex(replace(album_id, '-', '')), 'asset', "
        "unhex(replace(asset_id, '-', '')), printf('%08d', rowid) "
        'FROM temp.csv_album_items',
      );
      await run(
        "INSERT INTO temp.view (label, colour) SELECT title || ' · ' || "
        '(SELECT count(*) FROM album_item i WHERE i.album_id = a.id), 2 '
        'FROM album a ORDER BY title',
      );
    }
  });
  if (timeline) return null;
  final count = await db
      .customSelect('SELECT count(*) AS n FROM temp.view')
      .getSingle();
  return count.read<int>('n');
}

/// Copies a synthlib CSV table, whose fields hold no commas, into [table].
Future<void> _stage(Replica db, File csv, String table) async {
  final lines = csv
      .openRead()
      .transform(utf8.decoder)
      .transform(const LineSplitter());
  String? row;
  var chunk = <String>[];
  Future<void> flush() async {
    if (chunk.isEmpty) return;
    await db.customStatement(
      'INSERT INTO temp.$table VALUES '
      '${List.filled(chunk.length, row).join(',')}',
      [for (final line in chunk) ...line.split(',')],
    );
    chunk = [];
  }

  await for (final line in lines) {
    if (row == null) {
      await db.customStatement('CREATE TEMP TABLE $table ($line)');
      row = '(${List.filled(line.split(',').length, '?').join(',')})';
    } else if ((chunk..add(line)).length == 1000) {
      await flush();
    }
  }
  await flush();
}

/// Whether every visible cell of [view] shows its thumbnail.
bool allShown(
  TimelineViewState view,
  TimelinePages pages,
  Thumbnails thumbnails,
) {
  final (first, last) = view.visible;
  final dpr = MediaQuery.devicePixelRatioOf(view.context);
  final tier = tierFor(view.layout.cellExtent * dpr);
  for (var a = first; a <= last; a++) {
    final item = pages[a];
    if (item == null || thumbnails.get(item, tier) == null) return false;
  }
  return true;
}
