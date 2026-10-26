import 'dart:async';

import 'package:photolib_harness/photolib_harness.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) =>
    strictTests(testMain);
