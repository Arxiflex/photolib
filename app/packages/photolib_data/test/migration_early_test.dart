@TestOn('vm')
library;

import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:photolib_data/photolib_data.dart';
import 'package:test/test.dart';

import 'drift/replica/generated/schema.dart';

Uint8List _id(int n) => Uint8List(16)..[15] = n;

/// The steps of schemas 2 to 13 (migration_test.dart holds the later ones and
/// what a failed migration keeps).
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late Directory dir;
  setUp(
    () async => dir = await Directory.systemTemp.createTemp('photolib-data-'),
  );
  tearDown(() => dir.delete(recursive: true));

  final verifier = SchemaVerifier(GeneratedHelper());
  // The columns of the one device item, read raw: an older schema lacks
  // columns the current row class requires.
  Future<List<Object?>> row(Replica db, String columns) async =>
      (await db.customSelect('SELECT $columns FROM local_asset').getSingle())
          .data
          .values
          .toList();
  // Rows of [sql], read raw for the same reason.
  Future<List<List<Object?>>> select(Replica db, String sql) async => [
    for (final r in await db.customSelect(sql).get()) r.data.values.toList(),
  ];
  // The first column of [sql]'s rows.
  Future<List<Object?>> column(Replica db, String sql) async => [
    for (final r in await select(db, sql)) r.first,
  ];

  // [schema]'s replica, migrated to schema [to] and validated.
  Future<Replica> migrate(InitializedSchema schema, int to) async {
    final db = Replica(
      schema.newConnection(),
      openBackup: (suffix) =>
          NativeDatabase(File('${dir.path}/replica$suffix')),
    );
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, to);
    return db;
  }

  test(
    'schema v2 keeps its device index, which gains the MediaStore columns',
    () async {
      final schema = await verifier.schemaAt(2);
      schema.rawDatabase.execute(
        'INSERT INTO local_asset '
        '(id, source, source_id, size, mtime, content_hash) '
        "VALUES (?, 'mediastore', '42', 7, 8, ?)",
        [_id(1), _id(2)],
      );
      final db = await migrate(schema, 3);
      expect(await row(db, 'source_id, content_hash, name, favorite, state'), [
        '42',
        _id(2),
        null,
        0,
        'present',
      ]);
      expect(await db.select(db.volumeCursor).get(), isEmpty);
    },
  );

  test(
    'schema v3 keeps its device index, every item pending extraction',
    () async {
      final schema = await verifier.schemaAt(3);
      schema.rawDatabase.execute(
        'INSERT INTO local_asset (id, source, source_id, size, mtime, width) '
        "VALUES (?, 'mediastore', '42', 7, 8, 640)",
        [_id(1)],
      );
      // A synced row, which only a migration in place keeps: a failed one
      // rebuilds the replica.
      schema.rawDatabase.execute(
        'INSERT INTO album (id, owner_id, title, created_at, txid) '
        "VALUES (?, ?, 'synced', 1, 5)",
        [_id(2), _id(0)],
      );
      final db = await migrate(schema, 4);
      expect(await row(db, 'source_id, width, extracted, taken_utc, facets'), [
        '42',
        640,
        null,
        null,
        null,
      ]);
      expect(await db.select(db.album).get(), hasLength(1));
      expect(
        (await db.select(db.volumeCursor).get()).map((c) => c.root),
        isEmpty,
      );
    },
  );

  test(
    'schema v4 keeps its device index, which gains the PhotoKit columns',
    () async {
      final schema = await verifier.schemaAt(4);
      schema.rawDatabase.execute(
        'INSERT INTO local_asset '
        '(id, source, source_id, size, mtime, content_hash) '
        "VALUES (?, 'photokit', 'A/L0/001', 0, 8, ?)",
        [_id(1), _id(2)],
      );
      final db = await migrate(schema, 5);
      expect(
        await row(db, 'source_id, content_hash, cloud_id, burst_id, edited'),
        ['A/L0/001', _id(2), null, null, 0],
      );
    },
  );

  test('schema v5 dates its device items added when their ids were made, '
      'and lists them in the timeline', () async {
    final schema = await verifier.schemaAt(5);
    // A UUIDv7 of 2 May 2024 22:00:00.123 UTC.
    final id = Uint8List.fromList([
      0x01,
      0x8F,
      0x3B,
      0x52,
      0x4B,
      0x7B,
      0x70,
      0,
      0x80,
      0,
      0,
      0,
      0,
      0,
      0,
      1,
    ]);
    schema.rawDatabase.execute(
      'INSERT INTO local_asset '
      '(id, source, source_id, size, mtime, taken_local) '
      "VALUES (?, 'folder', 'a', 7, 8, '2024-05-03T00:30:00')",
      [id],
    );
    final db = await migrate(schema, 6);
    expect(await row(db, 'added'), [1714687200123]);
    expect(uuidTime(id), 1714687200123);
    expect(
      await select(db, 'SELECT day, COUNT(*) FROM timeline_item GROUP BY 1'),
      [
        [20240503, 1],
      ],
    );
  });

  test('schema v6 keeps its sync cursors, of no known epoch; an asset deleted '
      'then takes its files along', () async {
    final schema = await verifier.schemaAt(6);
    schema.rawDatabase
      ..execute("INSERT INTO sync_cursor VALUES ('tags', x'01', 1)")
      ..execute(
        'INSERT INTO asset (id, library_id, owner_id, original_filename, '
        'source, media_kind, created_at, txid) '
        "VALUES (?, ?, ?, 'a.jpg', 'upload', 'image', 1, 5)",
        [_id(1), _id(2), _id(3)],
      )
      ..execute(
        'INSERT INTO asset_file '
        '(id, asset_id, role, mime, size, state, txid) '
        "VALUES (?, ?, 'original', 'image/jpeg', 1, 'present', 5)",
        [_id(4), _id(1)],
      );
    final db = await migrate(schema, 7);
    expect((await db.select(db.syncCursor).getSingle()).epoch, null);
    expect(await db.select(db.assetFile).get(), hasLength(1));
    await db.delete(db.asset).go();
    expect(await db.select(db.assetFile).get(), isEmpty);
  });

  test('schema v7 keeps its device items, with no ThumbHash until one is '
      'kept, which the timeline lists', () async {
    final schema = await verifier.schemaAt(7);
    schema.rawDatabase.execute(
      'INSERT INTO local_asset (id, source, source_id, size, mtime, added) '
      "VALUES (?, 'folder', 'a', 7, 8, 9)",
      [_id(1)],
    );
    final db = await migrate(schema, 8);
    const timeline = 'SELECT added, thumbhash FROM timeline_item';
    expect(await select(db, timeline), [
      [9, null],
    ]);
    await saveThumbHashes(db, {
      _id(1): Uint8List.fromList([1, 2, 3]),
      _id(2): Uint8List.fromList([4]),
    });
    expect(await select(db, timeline), [
      [
        9,
        [1, 2, 3],
      ],
    ]);
  });

  test('schema v8 sends its motion photos back to extraction, to find their '
      'videos', () async {
    final schema = await verifier.schemaAt(8);
    for (final (n, facets) in ['panorama,motion_photo', ''].indexed) {
      schema.rawDatabase.execute(
        'INSERT INTO local_asset '
        '(id, source, source_id, size, mtime, extracted, facets) '
        "VALUES (?, 'folder', '$n', 7, 8, 9, ?)",
        [_id(n), facets],
      );
    }
    final db = await migrate(schema, 9);
    expect(await column(db, 'SELECT extracted FROM local_asset'), [null, 9]);
  });

  test("schema v10 keeps the libraries a partner's share shows whole, and "
      "syncs partners' streams again for their others", () async {
    final schema = await verifier.schemaAt(10);
    schema.rawDatabase
      ..execute('INSERT INTO partner_library VALUES (?, ?)', [_id(1), _id(2)])
      ..execute(
        "INSERT INTO sync_cursor VALUES ('partner/1', x'01', 1, 'e'), "
        "('libraries', x'01', 1, 'e')",
      );
    final db = await migrate(schema, 11);
    expect(
      [for (final l in await db.select(db.partnerLibrary).get()) l.whole],
      [1],
    );
    expect(
      [for (final c in await db.select(db.syncCursor).get()) c.stream],
      ['libraries'],
    );
  });

  test('schema v11 sends its videos back to extraction, to read their frame '
      'rates', () async {
    final schema = await verifier.schemaAt(11);
    for (final (n, mime) in ['video/mp4', 'image/jpeg', null].indexed) {
      schema.rawDatabase.execute(
        'INSERT INTO local_asset '
        '(id, source, source_id, size, mtime, extracted, mime) '
        "VALUES (?, 'folder', '$n', 7, 8, 9, ?)",
        [_id(n), mime],
      );
    }
    final db = await migrate(schema, 12);
    expect(await select(db, 'SELECT extracted, frame_rate FROM local_asset'), [
      [null, null],
      [9, null],
      [9, null],
    ]);
  });

  test('schema v12 sends its panoramas and videos back to extraction, to '
      'read their projections and stereo modes', () async {
    final schema = await verifier.schemaAt(12);
    for (final (n, (facets, mime)) in [
      ('panorama', 'image/jpeg'),
      ('', 'video/mp4'),
      ('motion_photo', 'image/jpeg'),
    ].indexed) {
      schema.rawDatabase.execute(
        'INSERT INTO local_asset '
        '(id, source, source_id, size, mtime, extracted, facets, mime) '
        "VALUES (?, 'folder', '$n', 7, 8, 9, ?, ?)",
        [_id(n), facets, mime],
      );
    }
    final db = await migrate(schema, 13);
    final extracted = await column(db, 'SELECT extracted FROM local_asset');
    expect(extracted, [null, null, 9]);
  });

  test('schema v13 files its MediaStore items under their device folders, '
      'junk out of the library, and counts their days', () async {
    final schema = await verifier.schemaAt(13);
    for (final (n, (source, path)) in [
      ('mediastore', 'DCIM/Camera/'),
      ('mediastore', 'DCIM/Camera/'),
      ('mediastore', 'Android/data/com.app/cache/'),
      ('folder', 'a.jpg'),
    ].indexed) {
      schema.rawDatabase.execute(
        'INSERT INTO local_asset '
        '(id, source, volume, source_id, size, mtime, path, bucket_name) '
        "VALUES (?, ?, 'v', '$n', 7, 86400000, ?, 'b$n')",
        [_id(n), source, path],
      );
    }
    final db = await migrate(schema, 14);
    const folders =
        'SELECT path, (SELECT SUM(count) FROM timeline_day '
        'WHERE folder = f.id), id IN (SELECT id FROM excluded_folder) '
        'FROM device_folder f ORDER BY path';
    expect(await select(db, folders), [
      ['Android/data/com.app/cache/', 1, 1],
      ['DCIM/Camera/', 2, 0],
    ]);
    expect(await column(db, 'SELECT folder FROM local_asset'), [2, 2, 1, 0]);
    const days =
        'SELECT day, SUM(count) FROM timeline_day '
        'WHERE folder NOT IN (SELECT id FROM hidden_folder) GROUP BY day';
    expect(await select(db, days), [
      [19700102, 3],
    ]);
  });
}
