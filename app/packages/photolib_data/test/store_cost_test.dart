// What encrypting the local store costs on the VM (store_cost.dart), against the budgets of docs/21 §8 as ADR-0090
// holds them: `flutter test test/store_cost_test.dart [--dart-define=assets=1000000]` prints the numbers.
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:ffi' show Abi;
import 'dart:io';

import 'package:drift/native.dart';
import 'package:photolib_data/photolib_data.dart';
import 'package:photolib_data/testing.dart';
import 'package:photolib_kernel/testing.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

import 'kernel.dart';

const _assets = int.fromEnvironment('assets', defaultValue: 100000);

/// Where the CPU has AES instructions, as on every machine the gate runs on, AEGIS-256 keeps the timeline's reads and
/// a snapshot's writes within 10 % of plaintext; a batch of random changes costs more under every cipher (ADR-0090).
const _within = ['bucket', 'window', 'fling', 'snapshot'];

void main() {
  final kernel = testKernel();
  late Directory dir;
  setUp(
    () async => dir = await Directory.systemTemp.createTemp('photolib-cost-'),
  );
  tearDown(() => dir.delete(recursive: true));
  Database open(String name, List<String> keying) {
    final db = sqlite3.open('${dir.path}/$name');
    keying.forEach(db.execute);
    db.execute('PRAGMA journal_mode = WAL');
    return db;
  }

  test(
    'a moment of quiet that one side of a round had moves its ratio, not the overhead',
    () {
      expect(
        overheads({
          'plaintext': {
            'window': [9, 12, 12, 12, 12],
          },
          'aegis-256': {
            'window': [12.5, 12.5, 12.5, 12.5, 12.5],
          },
        }),
        {
          'aegis-256': {'window': 4.2},
        },
      );
    },
  );

  test(
    'a cipher that costs 15 % more in every round costs 15 % more under any load',
    () {
      expect(
        overheads({
          'plaintext': {
            'fling': [10, 20, 15, 30],
          },
          'aegis-256': {
            'fling': [11.5, 23, 17.25, 34.5],
          },
        }),
        {
          'aegis-256': {'fling': 15.0},
        },
      );
    },
  );

  test(
    'the local store meets its budgets with AEGIS-256 pages',
    tags: 'alone',
    () async {
      pinToFastestCores(pid);
      final watch = Stopwatch()..start();
      final clock = threadClock() ?? () => watch.elapsedMicroseconds;
      Iterable<double> aegis(Map<String, Map<String, double>> overhead) =>
          _within.map((w) => overhead['aegis-256']![w]!);
      final cost = databaseCost(
        open,
        await replicaSchema(NativeDatabase.memory()),
        assets: _assets,
        clock: clock,
        enough: (overhead) => aegis(overhead).every((p) => p <= 10),
      );
      final vault = Vault(
        location: '${dir.path}/store',
        keystore: MemoryKeystore(),
        files: storeFiles('${dir.path}/store'),
        keyring: kernel.keyring,
      );
      final start = await storeOpenCost(vault, vault.openReplica);
      final thumbnails = await thumbnailCost(
        vault,
        storeFiles('${dir.path}/store'),
      );
      await vault.lock();
      final unlock = unlockCost(
        kernel.keyring,
        open,
        ciphers['aegis-256']!,
        clock: clock,
      );
      print(
        jsonEncode({
          'target': '${Abi.current()}',
          'assets': _assets,
          'ms': cost.ms,
          'overhead_percent': cost.overhead,
          'store_open_ms': start,
          ...thumbnails,
          ...unlock,
        }),
      );
      expect(
        aegis(cost.overhead),
        everyElement(lessThanOrEqualTo(10)),
        reason: 'AEGIS-256 over plaintext, %: ${cost.overhead['aegis-256']}',
      );
      for (final cipher in ['aegis-256', 'chacha20']) {
        expect(brokenBudgets(cost.ms[cipher]!), isEmpty, reason: cipher);
      }
      expect(thumbnails['thumbnail_p95_ms'], lessThanOrEqualTo(12));
      expect(thumbnails['thumbnail_tiles_s'], greaterThanOrEqualTo(320));
      expect(unlock['unlock_ms'], lessThanOrEqualTo(600));
    },
    timeout: const Timeout(Duration(minutes: 10)),
  );
}
