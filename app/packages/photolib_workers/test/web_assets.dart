// The VM side of web_test.dart: compiles test/worker.dart where the test server serves this package from, since a
// browser runs workers only from the page's own origin.
import 'dart:io';

import 'package:stream_channel/stream_channel.dart';

Future<void> hybridMain(StreamChannel<Object?> channel) async {
  const out = '.dart_tool/web_test/worker.js';
  final build = await Process.run(Platform.resolvedExecutable, [
    'compile',
    'js',
    '-O4',
    '--no-source-maps',
    '-o',
    out,
    'test/worker.dart',
  ]);
  if (build.exitCode != 0) {
    throw StateError('dart compile js failed:\n${build.stdout}${build.stderr}');
  }
  channel.sink.add(out);
}
