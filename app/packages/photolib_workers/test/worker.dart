import 'package:photolib_workers/worker.dart';

import 'tasks.dart';

/// The Web Worker of web_test.dart, compiled by web_assets.dart.
void main() => serveWorker(tasks);
