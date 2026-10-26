// What encrypting the local store costs on a device (photolib_data's store_cost.dart), for the phones of
// docs/dev/local-store-spike.md. In app/, with the device's kernel in build/kernel/ (tools/kernel/build.py):
//   PERF_RESULTS=<file> flutter drive --profile -d <device> [--flavor play] \
//     --driver test_driver/perf_driver.dart --target benchmark/store_cost_test.dart
import 'dart:ffi' show Abi;
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:photolib/core/kernel.dart';
import 'package:photolib_data/photolib_data.dart';
import 'package:photolib_data/testing.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('the local store’s encryption cost', (tester) async {
    await tester.runAsync(() async {
      final dir = await Directory.systemTemp.createTemp('photolib-cost-');
      Database open(String name, List<String> keying) {
        final db = sqlite3.open('${dir.path}/$name');
        keying.forEach(db.execute);
        db.execute('PRAGMA journal_mode = WAL');
        return db;
      }

      final keyring = await loadKernel();
      final watch = Stopwatch()..start();
      final cost = databaseCost(
        open,
        await replicaSchema(NativeDatabase.memory()),
        assets: 100000,
        clock: () => watch.elapsedMicroseconds,
      );
      final vault = Vault(
        location: '${dir.path}/store',
        keystore: MemoryKeystore(),
        files: storeFiles('${dir.path}/store'),
        keyring: keyring,
      );
      final start = await storeOpenCost(vault, vault.openReplica);
      final thumbnails = await thumbnailCost(
        vault,
        storeFiles('${dir.path}/store'),
      );
      await vault.lock();
      final cpu = File('/proc/cpuinfo');
      binding.reportData = {
        'results': [
          {
            'target': '${Platform.operatingSystem} ${Abi.current()}',
            if (cpu.existsSync())
              'aes': RegExp(r'\baes\b').hasMatch(cpu.readAsStringSync()),
            'ms': cost.ms,
            'overhead_percent': cost.overhead,
            'store_open_ms': start,
            ...thumbnails,
            for (final cipher in ['chacha20', 'aegis-256'])
              'unlock_$cipher': unlockCost(keyring, open, ciphers[cipher]!),
          },
        ],
      };
      await dir.delete(recursive: true);
    });
  }, timeout: const Timeout(Duration(minutes: 15)));
}
