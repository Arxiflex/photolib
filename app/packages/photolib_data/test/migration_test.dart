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

final int _current = Replica(NativeDatabase.memory()).schemaVersion;

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late Directory dir;
  setUp(
    () async => dir = await Directory.systemTemp.createTemp('photolib-data-'),
  );
  tearDown(() => dir.delete(recursive: true));

  QueryExecutor file(String name) => NativeDatabase(File('${dir.path}/$name'));
  QueryExecutor openBackup(String suffix) => file('replica$suffix');

  group('released schemas', () {
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
      final db = Replica(schema.newConnection(), openBackup: openBackup);
      addTearDown(db.close);
      await verifier.migrateAndValidate(db, to);
      return db;
    }

    for (final from in GeneratedHelper.versions) {
      test('schema v$from migrates to the current schema', () async {
        await migrate(await verifier.schemaAt(from), _current);
      });
    }

    test("schema v17 counts its device items' days added by quarter hour, as "
        'the items, those it shows and hides alike', () async {
      final schema = await verifier.schemaAt(17);
      schema.rawDatabase.execute(
        "INSERT INTO device_folder (id, volume, path) VALUES (1, 'v', 'a/')",
      );
      // 2 May 2024 22:00 and 22:20 UTC, the second hidden; one missing, one
      // trashed, one never dated.
      for (final (n, (added, folder, state, trashed)) in [
        (1714687200000, 0, 'present', 0),
        (1714687200000, 0, 'present', 0),
        (1714688400000, 1, 'present', 0),
        (1714688400000, 0, 'missing', 0),
        (1714688400000, 0, 'present', 1),
        (null, 0, 'present', 0),
      ].indexed) {
        schema.rawDatabase.execute(
          'INSERT INTO local_asset (id, source, volume, source_id, size, '
          "mtime, added, folder, state, trashed) VALUES (?, 'folder', 'v', "
          "'$n', 7, 0, ?, ?, ?, ?)",
          [_id(n), added, folder, state, trashed],
        );
      }
      final db = await migrate(schema, 27);
      await showFolder(db, 1, shown: false);
      Future<List<(int, int)>> days(int offset) async => [
        for (final d in await db.timelineAddedDays(offset, false, null).get())
          (d.day, d.count),
      ];
      expect(await days(0), [(20240502, 2), (19700101, 1)]);
      await showFolder(db, 1, shown: true);
      expect(await days(2 * 3600000), [(20240503, 3), (19700101, 1)]);
    });

    test(
      'schema v15 sends its spheres back to extraction, for their '
      'headings and video crops, and its timeline says which they are',
      () async {
        final schema = await verifier.schemaAt(15);
        for (final (n, projection) in ['equirectangular', null].indexed) {
          schema.rawDatabase.execute(
            'INSERT INTO local_asset (id, source, source_id, size, mtime, '
            "extracted, projection) VALUES (?, 'folder', '$n', 7, 8, 9, ?)",
            [_id(n), projection],
          );
        }
        final db = await migrate(schema, 16);
        const timeline =
            'SELECT extracted, t.projection FROM local_asset '
            'JOIN timeline_item t USING (id)';
        expect(
          await select(db, timeline),
          unorderedEquals([
            [null, 'equirectangular'],
            [9, null],
          ]),
        );
      },
    );

    test('schema v18 sends its GIF, WebP, PNG and AVIF files back to '
        "extraction and PhotoKit's library to be read again, to find their "
        'animations, which the timeline shows', () async {
      final schema = await verifier.schemaAt(18);
      for (final (n, (source, mime, path, name)) in [
        ('mediastore', 'image/gif', 'DCIM/', 'a.gif'),
        ('mediastore', 'image/jpeg', 'DCIM/', 'b.jpg'),
        ('folder', null, 'c.WEBP', null),
        ('folder', null, 'd.png', null),
        ('folder', null, 'e.avif', null),
        ('folder', null, 'f.heic', null),
      ].indexed) {
        schema.rawDatabase.execute(
          'INSERT INTO local_asset (id, source, volume, source_id, size, '
          'mtime, extracted, facets, mime, path, name) '
          "VALUES (?, ?, 'v', '$n', 7, 8, 9, 'panorama', ?, ?, ?)",
          [_id(n), source, mime, path, name],
        );
      }
      schema.rawDatabase.execute(
        'INSERT INTO volume_cursor VALUES '
        "('photokit', '', 'i', '3', 0, NULL), "
        "('mediastore', 'v', 'i', '3', 0, NULL)",
      );
      final db = await migrate(schema, 19);
      expect(await select(db, 'SELECT extracted, facets FROM local_asset'), [
        [null, null],
        [9, 'panorama'],
        [null, null],
        [null, null],
        [null, null],
        [9, 'panorama'],
      ]);
      expect(await select(db, 'SELECT source FROM volume_cursor'), [
        ['mediastore'],
      ]);
      expect(
        await select(db, 'SELECT source_id, facets FROM timeline_item'),
        unorderedEquals(
          await select(db, 'SELECT source_id, facets FROM local_asset'),
        ),
      );
    });

    test('schema v19 sends every file it read back to extraction, to find '
        'its HDR items', () async {
      final schema = await verifier.schemaAt(19);
      for (final (n, (mime, extracted)) in [
        ('image/jpeg', 9),
        ('video/mp4', 9),
        (null, 9),
        ('image/heic', null),
      ].indexed) {
        schema.rawDatabase.execute(
          'INSERT INTO local_asset '
          '(id, source, source_id, size, mtime, extracted, mime) '
          "VALUES (?, 'folder', '$n', 7, 8, ?, ?)",
          [_id(n), extracted, mime],
        );
      }
      final db = await migrate(schema, 20);
      final extracted = await column(db, 'SELECT extracted FROM local_asset');
      expect(extracted, [null, null, null, null]);
    });

    test('schema v21 syncs the streams that bring assets again, for their '
        'ThumbHashes', () async {
      final schema = await verifier.schemaAt(21);
      schema.rawDatabase.execute(
        "INSERT INTO sync_cursor VALUES ('assets/1', x'01', 1, 'e'), "
        "('album_items/1', x'01', 1, 'e'), ('partner/1', x'01', 1, 'e'), "
        "('faces/1', x'01', 1, 'e'), ('libraries', x'01', 1, 'e')",
      );
      final db = await migrate(schema, 22);
      expect(
        [for (final c in await db.select(db.syncCursor).get()) c.stream],
        ['faces/1', 'libraries'],
      );
    });

    test('schema v23 keeps its device items shown, favourites too, with '
        'nothing kept by content until it is read', () async {
      final schema = await verifier.schemaAt(23);
      schema.rawDatabase.execute(
        'INSERT INTO local_asset (id, source, source_id, size, mtime, '
        "favorite) VALUES (?, 'folder', '1', 7, 8, 1)",
        [_id(1)],
      );
      final db = await migrate(schema, 27);
      const state = 'favorite, hidden, archived, bin, fingerprint';
      expect(await row(db, state), [1, 0, 0, null, null]);
      expect(await db.timelineDays(false, null).get(), hasLength(1));
      expect(await db.select(db.keptState).get(), isEmpty);
    });

    test('schema v24 keeps its backup states, none with an upload under way, '
        'and starts a log of backup runs', () async {
      final schema = await verifier.schemaAt(24);
      schema.rawDatabase.execute(
        'INSERT INTO backup_state (local_asset_id, state, reason, updated_at) '
        "VALUES (?, 'failed', 'unreadable', 5)",
        [_id(1)],
      );
      final db = await migrate(schema, 25);
      final [state] = await db.select(db.backupState).get();
      expect(
        (state.state, state.reason, state.upload, state.attempts),
        ('failed', 'unreadable', null, 0),
      );
      expect(await db.select(db.backupRun).get(), isEmpty);
    });

    test('schema v25 counts the photos it shows and what on-device ML read '
        'of their present versions', () async {
      final schema = await verifier.schemaAt(25);
      // A photo read, one read before its file changed, one that failed, a
      // video without a mime type and a photo in the trash.
      for (final (n, (path, trashed)) in [
        ('a.jpg', 0),
        ('b.jpg', 0),
        ('c.jpg', 0),
        ('d.mp4', 0),
        ('e.jpg', 1),
      ].indexed) {
        schema.rawDatabase.execute(
          'INSERT INTO local_asset (id, source, source_id, size, mtime, path, '
          "trashed) VALUES (?, 'folder', '$n', 7, 8, ?, ?)",
          [_id(n), path, trashed],
        );
      }
      for (final (n, size, failure) in [
        (0, 7, null),
        (1, 6, null),
        (2, 7, 'x'),
      ]) {
        schema.rawDatabase.execute(
          'INSERT INTO local_ml (local_asset_id, model, size, mtime, failure, '
          "rt_flags) VALUES (?, 'm@1', ?, 8, ?, 'cpu')",
          [_id(n), size, failure],
        );
      }
      final db = await migrate(schema, 26);
      final p = await mlProgress(db, null).getSingle();
      expect((p.total, p.done, p.failed), (3, 2, 1));
    });

    test('schema v27 keeps what on-device ML read and gives it room for the '
        'text OCR reads', () async {
      final schema = await verifier.schemaAt(27);
      schema.rawDatabase.execute(
        'INSERT INTO local_ml (local_asset_id, model, size, mtime, vec, '
        "rt_flags) VALUES (?, 'm@1', 7, 8, x'0001', 'cpu')",
        [_id(1)],
      );
      final db = await migrate(schema, 28);
      final [ml] = await db.select(db.localMl).get();
      expect((ml.model, ml.ocrText, ml.ocrFolded), ('m@1', null, null));
      expect(ml.vec, [0, 1]);
      await db.customStatement(
        'UPDATE local_ml SET ocr_text = ?, ocr_folded = ?',
        ['Москва', 'москва'],
      );
      expect((await db.select(db.localMl).getSingle()).ocrFolded, 'москва');
    });

    test('schema v26 shows a backed-up device item as the one tile of its '
        'asset, and counts its days and photos by tile', () async {
      final schema = await verifier.schemaAt(26);
      schema.rawDatabase
        ..execute(
          'INSERT INTO library (id, owner_id, kind, privacy, access, state, '
          "txid) VALUES (?, ?, 'managed', 'standard', 'rw', 'online', 1)",
          [_id(1), _id(9)],
        )
        ..execute(
          'INSERT INTO asset (id, library_id, owner_id, original_filename, '
          "source, media_kind, created_at, txid) VALUES (?, ?, ?, 'a.jpg', "
          "'upload', 'image', 0, 1)",
          [_id(2), _id(1), _id(9)],
        )
        ..execute(
          'INSERT INTO local_asset (id, source, source_id, size, mtime, '
          "asset_id) VALUES (?, 'folder', ?, 7, 8, ?), "
          "(?, 'folder', ?, 7, 8, ?)",
          [_id(3), '1', _id(2), _id(4), '2', _id(2)],
        );
      final db = await migrate(schema, 27);
      expect(
        [
          for (final t
              in await db.timelinePage(99999999, false, null, 9, 0).get())
            (t.id[15], t.backup),
        ],
        [(3, 'backed_up')],
      );
      expect(
        [
          for (final d in await db.timelineDays(false, null).get())
            (d.day, d.count),
        ],
        [(19700101, 1)],
      );
      expect(
        [
          for (final d in await db.timelineAddedDays(0, false, null).get())
            (d.day, d.count),
        ],
        [(19700101, 1)],
      );
      expect((await mlProgress(db, null).getSingle()).total, 1);
    });

    test(
      'the current schema is dumped (dart run drift_dev make-migrations)',
      () => expect(GeneratedHelper.versions.last, _current),
    );
  });

  test('a first open that the disk cuts short leaves nothing half-made: the '
      'next creates the whole schema', () async {
    final path = File('${dir.path}/replica');
    final full = Replica(
      NativeDatabase(
        path,
        setup: (db) => db.execute('PRAGMA max_page_count = 40'),
      ),
    );
    await expectLater(
      full.customSelect('SELECT 1').get(),
      throwsA(isA<SqliteException>()),
    );
    await full.close().catchError((_) {});

    final db = Replica(NativeDatabase(path));
    addTearDown(db.close);
    expect(await db.select(db.localAsset).get(), isEmpty);
    final [version] = await db.customSelect('PRAGMA user_version').get();
    expect(version.read<int>('user_version'), _current);
  });

  test('every table is synced, device-only or rebuilt by syncing', () {
    const rebuilt = {
      'sync_cursor',
      'partner_library',
      'timeline_day',
      'timeline_added',
      'ml_count',
    };
    for (final table in Replica(NativeDatabase.memory()).allTables) {
      final name = table.actualTableName;
      expect(
        [
          if (table.$columns.any((c) => c.name == 'txid')) 'synced',
          if (deviceTables.contains(name)) 'device',
          if (rebuilt.contains(name)) 'rebuilt',
        ],
        hasLength(1),
        reason:
            '$name: give it a txid column, or list it in deviceTables '
            '(a failed migration keeps it) or in rebuilt here',
      );
    }
  });
}
