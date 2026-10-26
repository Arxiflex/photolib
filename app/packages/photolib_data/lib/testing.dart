/// The checks every target must pass with the local store: the package's tests run them on the VM and in browsers,
/// the app's integration test on all six targets. For tests only.
library;

import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:photolib_data/photolib_data.dart'
    show MediaAccess, MediaStore, MediaStoreItem, storeFiles;
import 'package:photolib_data/src/replica.dart';
import 'package:photolib_data/src/search.dart';
import 'package:photolib_data/src/stored_native.dart'
    if (dart.library.js_interop) 'package:photolib_data/src/stored_web.dart';
import 'package:photolib_data/src/vault.dart';
import 'package:photolib_kernel/keyring.dart';

export 'src/store_cost.dart';
export 'src/stored_native.dart'
    if (dart.library.js_interop) 'src/stored_web.dart';

/// A MediaStore volume: generations count every change, as on Android.
class FakeVolume {
  /// A volume of MediaStore [version].
  FakeVolume([this.version = 'v1']);

  /// What `MediaStore.getVersion` says.
  final String version;

  /// The generation of the last change.
  int generation = 0;

  /// The items by id.
  final items = SplayTreeMap<int, MediaStoreItem>();

  /// The generation that last changed each item.
  final modified = <int, int>{};
  var _next = 0;

  /// Adds the item [name] to the folder [path], as taken at [taken].
  MediaStoreItem add(
    String name, {
    String path = 'DCIM/Camera/',
    int taken = 1600000000000,
  }) => _put(
    MediaStoreItem(
      id: ++_next,
      generation: generation + 1,
      size: 1000 + name.length,
      modified: 1700000000000,
      name: name,
      mime: name.endsWith('.mp4') ? 'video/mp4' : 'image/jpeg',
      path: path,
      bucketId: path,
      bucketName: path.split('/').reversed.skip(1).first,
      taken: taken,
    ),
  );

  /// Edits item [id] in place, as a favourite or trash request does.
  MediaStoreItem change(
    int id, {
    bool trashed = false,
    int? size,
    bool? favorite,
  }) {
    final i = items[id] ?? (throw ArgumentError.value(id, 'id'));
    return _put(
      MediaStoreItem(
        id: id,
        generation: i.generation,
        size: size ?? i.size,
        modified: i.modified + (size == null ? 0 : 1),
        name: i.name,
        mime: i.mime,
        path: i.path,
        bucketId: i.bucketId,
        bucketName: i.bucketName,
        taken: i.taken,
        favorite: favorite ?? !i.favorite,
        trashed: trashed,
        expires: trashed ? 1800000000000 : null,
      ),
    );
  }

  MediaStoreItem _put(MediaStoreItem item) {
    modified[item.id] = ++generation;
    return items[item.id] = item;
  }
}

/// A MediaStore of [mounted] volumes, which records the queries it answers.
class FakeMediaStore implements MediaStore {
  /// What the user lets the app read.
  MediaAccess granted = MediaAccess.full;

  /// The install the app data is of.
  String install = 'install-1';

  /// The volumes by name.
  final mounted = <String, FakeVolume>{};

  /// Which ids and pages were read.
  final queries = <String>[];

  /// Where the volumes are mounted, each in a directory of its name.
  String roots = '/storage';

  FakeVolume _volume(String name) =>
      mounted[name] ?? (throw StateError('$name is not mounted'));

  @override
  Future<MediaAccess> access() async => granted;
  @override
  Future<String> installId() async => install;
  @override
  Future<List<String>> volumes() async => [...mounted.keys];
  @override
  Future<String?> root(String volume) async => '$roots/$volume';
  @override
  Future<String> version(String volume) async => _volume(volume).version;
  @override
  Future<int> generation(String volume) async => _volume(volume).generation;
  @override
  Future<int> count(String volume) async => _volume(volume).items.length;
  @override
  Future<List<int>> ids(String volume) async {
    queries.add('ids $volume');
    return [..._volume(volume).items.keys];
  }

  @override
  Future<List<MediaStoreItem>> items(
    String volume, {
    required int since,
    required int after,
    required int limit,
  }) async {
    queries.add('items $volume since $since after $after');
    final v = _volume(volume);
    return v.items.values
        .where((i) => i.id > after && (v.modified[i.id] ?? 0) > since)
        .take(limit)
        .toList();
  }
}

/// A keystore in memory.
class MemoryKeystore implements DeviceKeystore {
  final keys = <String, Uint8List>{};

  @override
  Future<Uint8List?> read(String name) async =>
      keys[name] == null ? null : Uint8List.fromList(keys[name]!);

  @override
  Future<Uint8List> create(String name) async {
    keys[name] = Uint8List.fromList(
      List.generate(32, (i) => i * 7 + name.length),
    );
    return (await read(name))!;
  }

  @override
  Future<void> delete(String name) async => keys.remove(name);
}

/// A vault in [location] under a keystore in memory, unlocked, and a tile
/// cipher of its with the kernel library at [kernel] or the bundled one:
/// natively, for tests and benchmarks of the thumbnails' disk cache.
Future<(Vault, TileCipher)> scratchVault(
  String location,
  KernelKeyring Function() keyring, {
  String? kernel,
}) async {
  final vault = Vault(
    location: location,
    keystore: MemoryKeystore(),
    files: storeFiles(location),
    keyring: keyring,
  );
  await vault.unlock();
  return (vault, await vault.tileCipher(kernel: kernel));
}

/// The marker library of the forensic test (docs/21 §10): a file name, a caption, EXIF strings, a place name and a
/// thumbnail's perceptual hash.
const markers = [
  'IMG_20260704_FORENSIC.HEIC',
  'Grandma blowing out ninety candles',
  'ForensiCam Mark IV',
  'Forensic Optics 35mm f/1.4',
  'Ljubljana Forensic Square',
  'phash:c3f0a1b2d4e5f607',
];

/// Writes every marker where Photolib keeps such data: the replica, through [db], and a cached thumbnail. Writing
/// them again changes nothing.
Future<void> storeMarkers(Vault vault, Replica db) async {
  final id = Uint8List(16)..[0] = 0xfe;
  const replace = InsertMode.insertOrReplace;
  await db.batch((b) {
    b.insert(
      db.localAsset,
      LocalAssetCompanion.insert(
        id: id,
        source: 'folder',
        sourceId: '/DCIM/${markers[0]}',
        size: 1,
        mtime: 1,
      ),
      mode: replace,
    );
    b.insert(
      db.asset,
      AssetCompanion.insert(
        id: id,
        libraryId: id,
        ownerId: id,
        originalFilename: markers[0],
        source: 'scan',
        mediaKind: 'image',
        createdAt: 1,
        description: Value(markers[1]),
        make: Value(markers[2]),
        lens: Value(markers[3]),
      ),
      mode: replace,
    );
    b.insert(
      db.tag,
      TagCompanion.insert(
        id: id,
        ownerId: id,
        name: markers[4],
        path: 'Places|${markers[4]}',
      ),
      mode: replace,
    );
  });
  await vault.write('thumbnail ${markers[0]}', utf8.encode(markers.join('\n')));
}

/// The markers that each file of the store in [location] holds, as UTF-8 or UTF-16 ([storedBytes]).
Future<Map<String, List<String>>> markerHits(String location) async => {
  for (final MapEntry(key: name, value: bytes) in (await storedBytes(
    location,
  )).entries)
    if (_hits(latin1.decode(bytes)) case final hits when hits.isNotEmpty)
      name: hits,
};

List<String> _hits(String text) => [
  for (final marker in markers)
    if (text.contains(marker) || text.contains(marker.split('').join('\x00')))
      marker,
];

Uint8List _id(int n) => Uint8List(16)..[15] = n;

/// A database opened as it is, never migrated, such as the backup a migration writes.
class Unmigrated extends GeneratedDatabase {
  Unmigrated(super.executor);

  @override
  Iterable<TableInfo<Table, Object?>> get allTables => const [];

  @override
  int get schemaVersion => 1;
}

/// Empties [db], writes a few rows and reports what the engine, the schema and the queries gave back.
Future<Map<String, Object?>> probeReplica(Replica db) async {
  for (final table in db.allTables) {
    await db.delete(table).go();
  }
  Future<List<String>> strings(String sql) async => [
    for (final row in await db.customSelect(sql).get())
      '${row.data.values.single}',
  ];

  final summaries = StreamIterator(db.backupSummary().watch());
  Future<String> summary() async {
    await summaries.moveNext();
    return summaries.current.map((s) => '${s.state} ${s.count}').join(', ');
  }

  final watched = [await summary()];
  await db.batch((b) {
    for (var i = 1; i <= 3; i++) {
      b.insert(
        db.localAsset,
        LocalAssetCompanion.insert(
          id: _id(i),
          source: 'folder',
          sourceId: '/Фото/$i 📷.jpg',
          size: i,
          mtime: i,
        ),
      );
      b.insert(
        db.backupState,
        BackupStateCompanion.insert(
          localAssetId: _id(i),
          state: i == 1 ? 'hashing' : 'selected',
          updatedAt: i,
        ),
      );
    }
  });
  watched.add(await summary());
  await (db.update(db.backupState)..where((s) => s.localAssetId.equals(_id(3))))
      .write(const BackupStateCompanion(state: Value('backed_up')));
  watched.add(await summary());
  await summaries.cancel();

  for (final (n, taken) in [(4, 300), (5, null), (6, 300), (7, 100)]) {
    await db
        .into(db.asset)
        .insert(
          AssetCompanion.insert(
            id: _id(n),
            libraryId: _id(0),
            ownerId: _id(0),
            originalFilename: 'IMG_$n.JPG',
            source: 'scan',
            mediaKind: 'image',
            takenUtc: Value(taken),
            fileSizeTotal: const Value(9007199254740991),
            createdAt: n,
          ),
        );
  }
  final timeline = db.select(db.asset)
    ..orderBy([
      (a) => OrderingTerm.desc(a.takenUtc),
      (a) => OrderingTerm.asc(a.id),
    ])
    ..limit(3);

  for (final (n, retryAt) in [(1, null), (2, 50), (3, 5)]) {
    await db
        .into(db.outbox)
        .insert(
          OutboxCompanion.insert(
            mutationId: _id(n),
            entity: 'album',
            entityId: _id(0),
            mutation: Uint8List.fromList([n, 0, 255]),
            retryAt: Value(retryAt),
            createdAt: n,
          ),
        );
  }

  return {
    'engine': await strings('SELECT substr(sqlite3mc_version(), 1, 24)'),
    'user_version': await strings('PRAGMA user_version'),
    'schema': await strings(
      "SELECT type || ' ' || name FROM sqlite_master WHERE name NOT LIKE 'sqlite_%' ORDER BY name",
    ),
    'backup summary': watched,
    'local asset': await strings(
      'SELECT source_id FROM local_asset ORDER BY source_id',
    ),
    'device buckets': [
      for (final b in await db.deviceBuckets().get())
        '${b.bucketName} ${b.items}',
    ],
    'device timeline': [
      for (final d in await db.timelineDays(false, null).get())
        '${d.day} ${d.count}',
      for (final a in await db.timelinePage(19700101, false, null, 2, 1).get())
        a.sourceId,
    ],
    'json': await strings("SELECT value FROM json_each('[\"1\", 2]')"),
    'timeline': [
      for (final a in await timeline.get())
        '${a.id.last} ${a.takenUtc} ${a.fileSizeTotal}',
    ],
    'pending outbox': [
      for (final o in await db.pendingOutbox(10, 5).get())
        '${o.seq} ${o.mutation}',
    ],
    'local search': switch (await searchPage(
      db,
      const LocalQuery(),
      limit: 2,
    )) {
      (:final count, :final items) => [
        '$count',
        for (final a in items) a.sourceId,
      ],
    },
  };
}

/// What [probeReplica] reports on a target that conforms.
const expectedProbe = {
  'engine': ['SQLite3 Multiple Ciphers'],
  'user_version': ['29'],
  'schema': [
    'table album',
    'table album_folder',
    'table album_item',
    'index album_item_order',
    'table album_member',
    'table album_user_state',
    'table asset',
    'index asset_added',
    'trigger asset_changed',
    'trigger asset_deleted',
    'table asset_file',
    'index asset_file_asset',
    'index asset_library',
    'trigger asset_linked',
    'trigger asset_state_hidden_insert',
    'trigger asset_state_hidden_update',
    'table asset_tag',
    'index asset_tag_tag',
    'index asset_taken',
    'index asset_timeline',
    'table asset_user_state',
    'table asset_version',
    'index asset_version_asset',
    'table backup_run',
    'table backup_state',
    'index backup_state_state',
    'table clock',
    'view cloud_item',
    'table device_folder',
    'table device_folder_mode',
    'index device_folder_own',
    'view excluded_folder',
    'table ext_journal_cursor',
    'table face',
    'index face_asset',
    'index face_person',
    'view hidden_folder',
    'table kept_state',
    'table library',
    'trigger library_state_hidden_delete',
    'trigger library_state_hidden_insert',
    'trigger library_state_hidden_update',
    'table library_user_state',
    'view linked_tile',
    'table local_asset',
    'index local_asset_added',
    'index local_asset_asset',
    'index local_asset_file',
    'trigger local_asset_fingerprint',
    'index local_asset_hash',
    'trigger local_asset_kept',
    'trigger local_asset_linked',
    'index local_asset_path',
    'index local_asset_pending',
    'trigger local_asset_relinked',
    'index local_asset_root',
    'index local_asset_timeline',
    'trigger local_asset_unlinked',
    'table local_ml',
    'table media_source',
    'table ml_count',
    'trigger ml_count_delete',
    'trigger ml_count_insert',
    'trigger ml_count_ml_delete',
    'trigger ml_count_ml_insert',
    'trigger ml_count_ml_replace',
    'trigger ml_count_ml_update',
    'trigger ml_count_set',
    'trigger ml_count_unset',
    'view ml_counted',
    'view ml_photo',
    'table outbox',
    'index outbox_entity',
    'table partner_library',
    'table partner_share',
    'table person',
    'table stack',
    'table sync_cursor',
    'table tag',
    'table timeline_added',
    'trigger timeline_added_delete',
    'trigger timeline_added_empty',
    'trigger timeline_added_insert',
    'trigger timeline_added_update',
    'table timeline_day',
    'trigger timeline_day_delete',
    'trigger timeline_day_empty',
    'trigger timeline_day_insert',
    'trigger timeline_day_update',
    'view timeline_item',
    'table volume_cursor',
  ],
  'backup summary': [
    '',
    'hashing 1, selected 2',
    'backed_up 1, hashing 1, selected 1',
  ],
  'local asset': ['/Фото/1 📷.jpg', '/Фото/2 📷.jpg', '/Фото/3 📷.jpg'],
  'device buckets': ['null 3'],
  'device timeline': ['19700101 3', '/Фото/2 📷.jpg', '/Фото/1 📷.jpg'],
  'json': ['1', '2'],
  'timeline': [
    '4 300 9007199254740991',
    '6 300 9007199254740991',
    '7 100 9007199254740991',
  ],
  'pending outbox': ['1 [1, 0, 255]', '3 [3, 0, 255]'],
  'local search': ['3', '/Фото/3 📷.jpg', '/Фото/2 📷.jpg'],
};
