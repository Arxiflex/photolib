// The VM side of web_test.dart: writes sqlite3mc.wasm and drift_worker.js (tools/data/web.sh) and the kernel's module
// (tools/kernel/wasm.sh) where the test server serves this package from, since a browser runs workers only from the
// page's own origin.
import 'dart:io';

import 'package:stream_channel/stream_channel.dart';

Future<void> hybridMain(StreamChannel<Object?> channel) async {
  const out = '.dart_tool/web_test';
  for (final script in ['data/web.sh', 'kernel/wasm.sh']) {
    final build = await Process.run('bash', ['../../../tools/$script', out]);
    if (build.exitCode != 0) {
      throw StateError('tools/$script failed:\n${build.stderr}');
    }
  }
  // A worker without its SQLite, which web_test.dart cannot start.
  await Directory('$out/nowasm').create(recursive: true);
  await File('$out/drift_worker.js').copy('$out/nowasm/drift_worker.js');
  channel.sink.add('$out/');
}
