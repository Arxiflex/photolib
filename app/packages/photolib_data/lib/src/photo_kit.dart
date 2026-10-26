import 'dart:convert';
import 'dart:math';

import 'package:drift/drift.dart';
import 'package:photolib_data/src/media_store.dart' show MediaAccess;
import 'package:photolib_data/src/replica.dart';
import 'package:photolib_log/photolib_log.dart';

/// The user's photo library as the indexer reads it (docs/10-client-app.md §6.1): the images and videos it shows,
/// hidden and recently deleted ones left out, described without reading their resources, which iCloud may keep off the
/// device. The app reads it over a platform channel (app/lib/core/photo_kit.dart).
///
/// Assets come as a JSON array of rows, which SQLite writes without them ever being Dart objects: collecting garbage
/// in any isolate pauses the UI's. A row holds `localIdentifier`, the `PHCloudIdentifier` string, whether it is a
/// video, `modificationDate` and `creationDate` in milliseconds, `pixelWidth`, `pixelHeight`, the duration in
/// milliseconds, latitude, longitude, the `mediaSubtypes` bits with bit 32 set on the frame that represents its burst,
/// bit 33 on one the user picked and bit 34 on an animated image (`playbackStyle`), `burstIdentifier`, `isFavorite`
/// and `hasAdjustments`.
abstract interface class PhotoKit {
  Future<MediaAccess> access();

  /// A random id kept out of backups, so restored app data comes with another one.
  Future<String> installId();

  /// The library's current persistent change token, archived.
  Future<String> token();

  /// The ids of the assets inserted, updated or deleted since [token]; null when the history no longer reaches it.
  Future<List<String>?> changedSince(String token);

  /// At most [limit] assets from [offset], newest first. Offset 0 takes a snapshot of the library, which later pages
  /// read, so that changes during a scan move nothing between pages.
  Future<String> assets(int offset, int limit);

  /// The assets of [ids] that the library shows.
  Future<String> assetsOf(List<String> ids);
}

/// Keeps the `local_asset` rows of [library] what it shows (ADR-0095), a statement per page of [page] assets.
class PhotoKitIndexer {
  PhotoKitIndexer(this.db, this.library, {this.page = 2000});

  final Replica db;
  final PhotoKit library;
  final int page;

  /// Brings the index up to date: nothing without access, everything again after a change of install. Replays the
  /// persistent history since the stored token, and reads the whole library when there is none, when the history no
  /// longer reaches it or when access is limited, as a selection changes without a trace in the history.
  Future<void> sync() async {
    final access = await library.access();
    // PhotoKit shows nothing then, which must not read as everything deleted.
    if (access == MediaAccess.none) return;
    final install = await library.installId();
    var cursor = await (db.select(
      db.volumeCursor,
    )..where((c) => c.source.equals(_source))).getSingleOrNull();
    if (cursor != null && cursor.installId != install) {
      // App data restored from another install: its rows, hashes and links are of that phone's library (Immich #10546).
      await _drop('true', const []);
      cursor = null;
    }
    // Read first: what changes during the sync is in the history after it.
    final token = await library.token();
    final changed = cursor == null || access == MediaAccess.partial
        ? null
        : await library.changedSince(cursor.version);
    // Each row this sync writes carries its stamp: rows without it are those the library no longer shows.
    final stamp = '${DateTime.now().microsecondsSinceEpoch}';
    const Logger('photolib.index').info(
      'photokit sync',
      fields: {
        'access': access.name,
        'read': changed == null ? 'whole library' : '${changed.length} changed',
        'why': cursor == null
            ? 'first sync'
            : access == MediaAccess.partial
            ? 'limited access'
            : changed == null
            ? 'history no longer reaches the token'
            : 'history',
      },
    );
    if (changed == null) {
      for (var offset = 0; ; offset += page) {
        if (await _write(await library.assets(offset, page), stamp) < page) {
          break;
        }
      }
      await _drop('generation IS NOT ?', [stamp]);
    } else {
      for (var i = 0; i < changed.length; i += page) {
        final ids = changed.sublist(i, min(i + page, changed.length));
        await _write(await library.assetsOf(ids), stamp);
        // Deleted, or hidden.
        await _drop(
          'source_id IN (SELECT value FROM json_each(?)) AND generation IS NOT ?',
          [jsonEncode(ids), stamp],
        );
      }
    }
    await db
        .into(db.volumeCursor)
        .insertOnConflictUpdate(
          VolumeCursorCompanion.insert(
            source: _source,
            volume: '',
            installId: install,
            version: token,
            generation: 0,
          ),
        );
  }

  /// Deletes the rows of the library [where] holds, with their backup state.
  Future<void> _drop(String where, List<String> args) =>
      db.transaction(() async {
        final variables = [
          const Variable(_source),
          for (final a in args) Variable(a),
        ];
        final rows = 'SELECT id FROM local_asset WHERE source = ? AND $where';
        await db.customUpdate(
          'DELETE FROM backup_state WHERE local_asset_id IN ($rows)',
          variables: variables,
          updates: {db.backupState},
        );
        await db.customUpdate(
          'DELETE FROM local_asset WHERE id IN ($rows)',
          variables: variables,
          updates: {db.localAsset},
        );
      });

  /// Writes the assets of [json] over their rows, or as new ones; returns how many there were.
  Future<int> _write(String json, String stamp) => db.customUpdate(
    _upsert,
    variables: [
      Variable(json),
      Variable(DateTime.now().millisecondsSinceEpoch),
      Variable(stamp),
    ],
    updates: {db.localAsset},
  );
}

const _source = 'photokit';

/// A new row's id is a UUIDv7 of the time ?2, as media_store.dart makes them, and ?2 its date added. The size is that
/// of a resource, read only for work on the original, and the MIME type a media range: only resources name the type.
/// Facets name the bits of PHAssetMediaSubtype, the two of bursts and that of
/// animated images.
const _upsert = '''
INSERT INTO local_asset (id, source, source_id, generation, cloud_id, mime, size, mtime, taken, width, height,
  duration_ms, lat, lon, facets, burst_id, favorite, edited, added)
SELECT unhex(printf('%012X7%03X%04X%012X', ?2, random() & 4095, 32768 | random() & 16383, random() & 281474976710655)),
  'photokit', a ->> 0, ?3, a ->> 1, iif(a ->> 2, 'video/*', 'image/*'), 0, a ->> 3, a ->> 4, a ->> 5, a ->> 6, a ->> 7,
  a ->> 8, a ->> 9,
  (SELECT group_concat(value) FROM json_each('{"1": "panorama", "2": "hdr", "4": "screenshot", "8": "live",
    "16": "depth_effect", "1024": "spatial", "32768": "screen_recording", "65536": "streamed",
    "131072": "high_frame_rate", "262144": "time_lapse", "2097152": "cinematic", "4294967296": "burst_cover",
    "8589934592": "burst_pick", "17179869184": "animated"}') WHERE a ->> 10 & key),
  a ->> 11, a ->> 12, a ->> 13, ?2
FROM (SELECT value AS a FROM json_each(?1)) WHERE true
ON CONFLICT (source, volume, source_id) DO UPDATE SET generation = ?3, cloud_id = excluded.cloud_id,
  mime = excluded.mime, mtime = excluded.mtime, taken = excluded.taken, width = excluded.width,
  height = excluded.height, duration_ms = excluded.duration_ms, lat = excluded.lat, lon = excluded.lon,
  facets = excluded.facets, burst_id = excluded.burst_id, favorite = excluded.favorite, edited = excluded.edited''';
