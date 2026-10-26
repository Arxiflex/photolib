// The pool on Web Workers, in the `web` part of tools/check.sh.
@TestOn('browser')
@Timeout(Duration(minutes: 1))
library;

import 'package:photolib_harness/photolib_harness.dart';
import 'package:photolib_workers/photolib_workers.dart';
import 'package:test/test.dart';

import 'pool_tests.dart';
import 'tasks.dart';

void main() {
  strict();
  late Uri script;
  setUpAll(() async {
    final path = await spawnHybridUri('web_assets.dart').stream.first;
    script = Uri.base.resolve('../$path');
  });

  poolTests(({size}) => WorkerPool(tasks, script: script, size: size));
}
