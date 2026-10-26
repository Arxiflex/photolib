import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photolib_harness/photolib_harness.dart';

// Kept in step with the packages' own: test/harness/harness_test.dart.
Future<void> testExecutable(FutureOr<void> Function() testMain) {
  _StrictBinding();
  return strictTests(testMain, install: _install);
}

Uninstall _install(Report report) {
  final onError = FlutterError.onError;
  FlutterError.onError = (details) {
    report('FlutterError: ${details.exceptionAsString()}');
    onError?.call(details);
  };
  return () => FlutterError.onError = onError;
}

class _StrictBinding extends AutomatedTestWidgetsFlutterBinding {
  @override
  final DebugPrintCallback debugPrintOverride = reportingErrorLogs(
    debugPrintSynchronously,
  );
}
