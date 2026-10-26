// What encrypting the local store costs (design 21 §8), measured the same way on the VM (store_cost_test.dart), in
// browsers (web_test.dart) and on devices (app/benchmark/store_cost_test.dart); docs/dev/local-store-spike.md has the
// numbers and ADR-0090 the decisions. For tests only.
import 'dart:math';

import 'package:drift/drift.dart';
import 'package:photolib_data/src/keys.dart';
import 'package:photolib_data/src/replica.dart';
import 'package:photolib_data/src/vault.dart';
import 'package:photolib_kernel/keyring.dart';
import 'package:sqlite3/common.dart';

/// How each cipher keys a connection with a 32-byte page key. The key is uniform, so every KDF runs at its minimum.
/// Plaintext and AEGIS-256, whose ratio has a budget, are in the middle: in [databaseCost]'s turns neither runs first.
const ciphers = {
  'chacha20': ["PRAGMA cipher = 'chacha20'", 'PRAGMA kdf_iter = 1'],
  'plaintext': <String>[],
  'aegis-256': [
    "PRAGMA cipher = 'aegis'",
    "PRAGMA algorithm = 'aegis-256'",
    'PRAGMA tcost = 1',
    'PRAGMA mcost = 8',
  ],
  'aes256cbc': ["PRAGMA cipher = 'aes256cbc'", 'PRAGMA kdf_iter = 1'],
};

/// Opens database [name] with [keying] as its first statements: natively a file, in a browser through sqlite3mc's VFS.
typedef Open = CommonDatabase Function(String name, List<String> keying);

/// The replica's schema, as drift creates it on [memory].
Future<List<String>> replicaSchema(QueryExecutor memory) async {
  final db = Replica(memory);
  final rows = await db
      .customSelect(
        "SELECT sql FROM sqlite_schema WHERE sql NOT NULL AND name NOT LIKE 'sqlite%' ORDER BY rowid",
      )
      .get();
  await db.close();
  return [for (final row in rows) row.read<String>('sql')];
}

/// What a workload costs under each cipher: [ms], its fastest sample in ms, and [overhead], each cipher's cost over
/// plaintext's in percent.
typedef Cost = ({
  Map<String, Map<String, double>> ms,
  Map<String, Map<String, double>> overhead,
});

/// The cost by [clock] (µs) of each workload in a store of [assets] assets under each cipher the build has: 50 reads of
/// the day counts, 100 windows of 120 cells and a fling of 100 windows, read with nothing cached; a page of a sync
/// snapshot (1,000 new assets) and a log batch (1,000 assets changed at random). The ciphers take turns at each
/// workload, in the opposite order every other round, for 7 rounds and for up to 28 while [enough] is false: other work
/// on the machine slows both sides of a round's ratio to plaintext, and [overheads] takes their median.
Cost databaseCost(
  Open open,
  List<String> schema, {
  required int assets,
  required int Function() clock,
  bool Function(Map<String, Map<String, double>> overhead)? enough,
}) {
  final random = Random(1);
  // 15 years, so that the timeline has as many days at any size.
  final every = 473040000000 ~/ assets;
  final stores = <String, CommonDatabase>{};
  for (final MapEntry(key: cipher, value: keying) in ciphers.entries) {
    try {
      stores[cipher] = open('cost-$cipher', [
        ...keying,
        if (keying.isNotEmpty) _hexkey,
      ]);
    } on SqliteException catch (e) {
      // sqlite3mc's WebAssembly build has ChaCha20 only.
      if (!e.message.contains('unknown')) rethrow;
    }
  }

  for (final db in stores.values) {
    [...schema, ..._timeline].forEach(db.execute);

    for (var at = 0; at < assets; at += 10000) {
      _apply(db, at, min(10000, assets - at), every);
    }
  }
  final samples = {
    for (final cipher in stores.keys) cipher: <String, List<double>>{},
  };
  for (
    var round = 0, added = assets;
    round < 7 || round < 28 && !(enough?.call(overheads(samples)) ?? true);
    round++, added += 1000
  ) {
    final keys = [
      for (var i = 0; i < 100; i++) 1 + random.nextInt(assets),
    ].join(',');
    final changed =
        '[${[for (var i = 0; i < 1000; i++) 1 + random.nextInt(assets)].join(',')}]';
    final order = round.isEven ? stores.keys : stores.keys.toList().reversed;
    final workloads = {
      for (final cipher in order)
        cipher: _workloads(stores[cipher]!, keys, changed, added, every),
    };
    for (final workload in workloads[order.first]!.run.keys) {
      for (final cipher in order) {
        final start = clock();
        workloads[cipher]!.run[workload]!();
        (samples[cipher]![workload] ??= []).add((clock() - start) / 1000);
      }
    }
    for (final w in workloads.values) {
      w.window.close();
    }
  }
  for (final db in stores.values) {
    db.close();
  }
  return (
    ms: {
      for (final MapEntry(key: cipher, value: ms) in samples.entries)
        cipher: {
          for (final MapEntry(:key, :value) in ms.entries)
            key: value.reduce(min),
        },
    },
    overhead: overheads(samples),
  );
}

/// One round's workloads on [db], and the statement they share, to close once they ran.
({Map<String, void Function()> run, CommonPreparedStatement window}) _workloads(
  CommonDatabase db,
  String keys,
  String changed,
  int added,
  int every,
) {
  final starts = db.select(
    'SELECT -taken_utc AS s, id FROM asset WHERE rowid IN ($keys)',
  );
  final window = db.prepare(
    'SELECT * FROM timeline_entry WHERE (sort_key, id) > (?, ?) ORDER BY sort_key, id LIMIT 120',
  );
  return (
    window: window,
    run: {
      'bucket': () {
        for (var i = 0; i < 50; i++) {
          db.execute('PRAGMA shrink_memory');
          db.select('SELECT * FROM timeline_bucket ORDER BY day DESC');
        }
      },
      'window': () {
        for (final start in starts) {
          db.execute('PRAGMA shrink_memory');
          window.select([start['s'], start['id']]);
        }
      },
      'fling': () {
        db.execute('PRAGMA shrink_memory');
        List<Object?> at = [-9007199254740991, Uint8List(0)];
        for (var i = 0; i < 100; i++) {
          final rows = window.select(at);
          if (rows.isEmpty) break;
          at = [rows.last['sort_key'], rows.last['id']];
        }
      },
      'snapshot': () => _apply(db, added, 1000, every),
      'log': () {
        db.execute('BEGIN');
        db.execute(
          "UPDATE asset SET rating = (rating + 1) % 6, title = 'Edited' WHERE rowid IN (SELECT value FROM json_each(?))",
          [changed],
        );
        db.execute(
          'UPDATE timeline_entry SET flags = flags + 1 WHERE (sort_key, id) IN '
          '(SELECT -taken_utc, id FROM asset WHERE rowid IN (SELECT value FROM json_each(?)))',
          [changed],
        );
        db.execute('COMMIT');
      },
    },
  );
}

/// Each cipher's cost over plaintext's in percent, from [samples] of each workload taken in rounds: the median of the
/// rounds' ratios, so that load which slows one side of a round moves one ratio, not the overhead.
Map<String, Map<String, double>> overheads(
  Map<String, Map<String, List<double>>> samples,
) {
  double percent(List<double> rounds, List<double> plaintext) {
    final ratios = [for (final (i, t) in rounds.indexed) t / plaintext[i]]
      ..sort();
    final median =
        (ratios[(ratios.length - 1) ~/ 2] + ratios[ratios.length ~/ 2]) / 2;
    return (1000 * (median - 1)).round() / 10;
  }

  return {
    for (final MapEntry(key: cipher, value: ms) in samples.entries)
      if (cipher != 'plaintext')
        cipher: {
          for (final MapEntry(key: w, value: rounds) in ms.entries)
            w: percent(rounds, samples['plaintext']![w]!),
        },
  };
}

/// The absolute budgets that [ms], one cipher's costs, breaks: design 10 §2's bucket table in 50 ms and window in
/// 8 ms, and a batch of 1,000 assets in 150 ms, so that sync applies 100k within NFR-PERF-5's 15 s.
List<String> brokenBudgets(Map<String, double> ms) => [
  if (ms['bucket']! / 50 > 50) 'bucket table: ${ms['bucket']! / 50} ms',
  if (ms['window']! / 100 > 8) 'window: ${ms['window']! / 100} ms',
  for (final batch in ['snapshot', 'log'])
    if (ms[batch]! > 150) '$batch: ${ms[batch]} ms',
];

/// Reads cached thumbnails of 16 KiB (a 256-px WebP) at random through [vault], which opens their PLB envelopes, and
/// as plaintext from [files]: 640 one at a time for the 95th percentile of a read in ms, the tier's latency of design
/// 10 §3.4, and 160 four at a time, as the timeline's queue asks for them (ADR-0070), for the reads per second. The
/// best of up to 10 rounds, taken while design 21 §8's budget is missed (12 ms, 320 per second), as a busy machine
/// only slows a sample.
Future<Map<String, double>> thumbnailCost(Vault vault, StoreFiles files) async {
  const count = 200;
  final random = Random(2);
  final bytes = Uint8List.fromList([
    for (var i = 0; i < 16 << 10; i++) random.nextInt(256),
  ]);
  for (var i = 0; i < count; i++) {
    await vault.write('thumbnail-$i', bytes);
    await files.write('plaintext-$i', bytes);
  }
  Future<List<double>> reads(
    Future<Uint8List?> Function(String name) read,
    String prefix,
    int tiles,
    int lanes,
  ) async {
    final ms = <double>[];
    var started = 0;
    Future<void> lane() async {
      while (started++ < tiles) {
        final one = Stopwatch()..start();
        final tile = await read('$prefix-${random.nextInt(count)}');
        ms.add(one.elapsedMicroseconds / 1000);
        if (tile?.length != bytes.length) throw StateError('a tile is wrong');
      }
    }

    await Future.wait([for (var i = 0; i < lanes; i++) lane()]);
    return ms..sort();
  }

  final best = {
    for (final key in ['thumbnail', 'plaintext']) ...{
      '${key}_p95_ms': double.infinity,
      '${key}_tiles_s': 0.0,
    },
  };
  for (
    var round = 0;
    round < 10 &&
        (best['thumbnail_p95_ms']! > 12 || best['thumbnail_tiles_s']! < 320);
    round++
  ) {
    for (final (key, read) in [
      ('plaintext', files.read),
      ('thumbnail', vault.read),
    ]) {
      final p95 = (await reads(read, key, 640, 1))[607];
      final all = Stopwatch()..start();
      await reads(read, key, 160, 4);
      final rate = 160 / all.elapsedMicroseconds * 1e6;
      best['${key}_p95_ms'] = min(best['${key}_p95_ms']!, p95);
      best['${key}_tiles_s'] = max(best['${key}_tiles_s']!, rate);
    }
  }
  for (var i = 0; i < count; i++) {
    await vault.delete('thumbnail-$i');
    await files.delete('plaintext-$i');
  }
  return best;
}

/// What a cold start at L1 spends in the store, in ms: [vault] unlocked with its keystore key and its replica opened by
/// [replica] (natively in its data isolate, in a browser in its worker) and read. The store exists already; [vault]
/// stays unlocked.
Future<double> storeOpenCost(
  Vault vault,
  Future<Replica> Function() replica,
) async {
  await vault.unlock();
  await replica();
  await vault.lock();
  final watch = Stopwatch()..start();
  await vault.unlock();
  final db = await replica();
  await db.customSelect('SELECT count(*) FROM asset').get();
  return watch.elapsedMicroseconds / 1000;
}

/// An unlock at L2 (docs/21 §4), without the hardware binding, which needs a device: `KEK_pass` from the passcode at
/// the parameters calibration picks (crypto-v1: `t` for at least 250 ms at 64 MiB), the lockbox opened with it, the
/// replica's page key, the database keyed with [cipher] and its first timeline window. The fastest of three by [clock]
/// (µs; wall time without one), in ms, with the Argon2id floor it calibrated from and the `t` it picked.
Map<String, double> unlockCost(
  KernelKeyring Function() keyring,
  Open open,
  List<String> cipher, {
  int Function()? clock,
}) {
  final watch = Stopwatch()..start();
  final now = clock ?? () => watch.elapsedMicroseconds;
  final random = Random.secure();
  Uint8List bytes(int n) =>
      Uint8List.fromList([for (var i = 0; i < n; i++) random.nextInt(256)]);
  final salt = bytes(16), fileId = bytes(16), name = 'unlock-${hex(fileId)}';
  Uint8List params(int t) =>
      Uint8List.fromList([1, 0, 1, 0, 0, 0, 0, 0, t, 1, ...salt]);
  double fastest(void Function() run) {
    var best = double.infinity;
    for (var i = 0; i < 3; i++) {
      final start = now();
      run();
      best = min(best, (now() - start) / 1000);
    }
    return best;
  }

  final setup = Keys(keyring());
  // The first derivation also grows the heap (WebAssembly's memory) by 64 MiB.
  setup.drop(setup.stretch('123456', params(3)));
  final floor = fastest(() => setup.drop(setup.stretch('123456', params(3))));
  final t = min(64, max(3, (3 * 250 / floor).ceil()));
  final ddk = setup.import(bytes(32));
  final lockbox = setup.sealLockbox(ddk, bytes(16), [
    (1, setup.stretch('123456', params(t))),
  ]);
  final key = "PRAGMA hexkey = '${hex(setup.databaseKey(ddk, fileId))}'";
  final store = open(name, [...cipher, key]);
  _timeline.forEach(store.execute);
  store.execute(
    'WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i + 1 FROM n WHERE i < 1000) '
    'INSERT INTO timeline_entry SELECT i, randomblob(16), i, randomblob(25), 1.333, 0 FROM n',
  );
  store.close();
  setup.keyring.close();

  final unlock = fastest(() {
    final keys = Keys(keyring());
    final ddk = keys.openLockbox(lockbox, keys.stretch('123456', params(t)));
    final db = open(name, [
      ...cipher,
      "PRAGMA hexkey = '${hex(keys.databaseKey(ddk, fileId))}'",
    ]);
    db.select('SELECT * FROM timeline_entry ORDER BY sort_key, id LIMIT 120');
    db.close();
    keys.keyring.close();
  });
  return {
    'argon2id_floor_ms': floor,
    'passcode_t': t.toDouble(),
    'unlock_ms': unlock,
  };
}

final _hexkey = "PRAGMA hexkey = '${'5a' * 32}'";

/// The timeline's tables as docs/10 §2 designs them (M1-10 adds them to the replica): a row per cell, clustered by
/// sort key, and the count of each day.
const _timeline = [
  'CREATE TABLE timeline_entry (sort_key INTEGER NOT NULL, id BLOB NOT NULL, day INTEGER NOT NULL, '
      'thumbhash BLOB NOT NULL, aspect REAL NOT NULL, flags INTEGER NOT NULL, '
      'PRIMARY KEY (sort_key, id)) WITHOUT ROWID, STRICT',
  'CREATE TABLE timeline_bucket (day INTEGER PRIMARY KEY, count INTEGER NOT NULL, version INTEGER NOT NULL) STRICT',
];

/// Adds [count] assets in one transaction, as a page of a sync snapshot (design 05 §4): the [from]th upload onwards,
/// from 2010 one every [every] ms, each taken up to a week before, with UUIDv7 ids, their cells and their days' counts.
void _apply(CommonDatabase db, int from, int count, int every) {
  final last = db
      .select('SELECT ifnull(max(rowid), 0) AS r FROM asset')
      .single['r'];
  db.execute('BEGIN');
  db.execute(
    '''
    WITH RECURSIVE n(i) AS (SELECT ?1 UNION ALL SELECT i + 1 FROM n WHERE i < ?2),
      upload(id, created, taken) AS (
        SELECT CAST(unhex(printf('%012x', 1262304000000 + i * ?3)) || randomblob(10) AS BLOB), 1262304000000 + i * ?3,
          1262304000000 + i * ?3 - abs(random() % 604800000) FROM n)
    INSERT INTO asset (id, library_id, owner_id, original_filename, source, media_kind, width, height, taken_local,
      tz_offset_min, taken_utc, make, model, file_size_total, created_at, txid)
    SELECT id, zeroblob(16), zeroblob(16), 'IMG_' || created || '.HEIC', 'upload', 'image', 4032, 3024,
      strftime('%Y-%m-%dT%H:%M:%f', taken / 1000.0, 'unixepoch'), 0, taken, 'Google', 'Pixel 7a', 2500000, created,
      created FROM upload''',
    [from, from + count - 1, every],
  );
  db.execute(
    'INSERT INTO timeline_entry SELECT -taken_utc, id, taken_utc / 86400000, randomblob(25), 1.333, 0 FROM asset '
    'WHERE rowid > ?',
    [last],
  );
  db.execute(
    'INSERT INTO timeline_bucket SELECT taken_utc / 86400000, count(*), 1 FROM asset WHERE rowid > ? GROUP BY 1 '
    'ON CONFLICT (day) DO UPDATE SET count = count + excluded.count, version = version + 1',
    [last],
  );
  db.execute('COMMIT');
}
