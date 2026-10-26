import 'dart:async';

import 'package:photolib_harness/photolib_harness.dart';

Report? _report;

/// Reports [problem] as a package's own source of problems would.
void problem(String problem) => _report?.call(problem);

Future<void> testExecutable(FutureOr<void> Function() testMain) => strictTests(
  testMain,
  install: (report) {
    _report = report;
    return () => _report = null;
  },
);
