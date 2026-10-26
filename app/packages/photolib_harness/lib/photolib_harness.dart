/// Fails a test on the failures it would otherwise swallow: every problem
/// reported while it runs, every error-level record of the isolate's [Log],
/// and in a browser any uncaught error, unhandled rejection or
/// `console.error` of the page. A test's timeout counts no time its process
/// was stopped.
library;

import 'dart:async';
import 'dart:convert';

import 'package:photolib_harness/src/browser.dart'
    if (dart.library.js_interop) 'package:photolib_harness/src/browser_web.dart';
import 'package:photolib_harness/src/testing/stops.dart';
import 'package:photolib_log/photolib_log.dart';
import 'package:test_api/hooks.dart' show TestFailure;
import 'package:test_api/scaffolding.dart'
    show setUp, setUpAll, tearDown, tearDownAll;

export 'package:photolib_harness/src/testing/stops.dart' show thawed;

/// Records a problem that fails the running test.
typedef Report = void Function(String problem);

/// Undoes what an [Install] did.
typedef Uninstall = void Function();

/// Wires a package's sources of problems to [Report] for one test.
typedef Install = Uninstall Function(Report report);

/// Prints a message as Flutter's `debugPrint` does.
typedef DebugPrint = void Function(String? message, {int? wrapWidth});

final _problems = <String>[];
var _running = false;

/// Makes every test that the caller declares after it fail on a problem
/// reported during it, through [install], [reportingErrorLogs], the
/// error-level records of [Log] and, in a browser, the page's own errors; a
/// problem of a `setUpAll` or of the time between tests fails the next test,
/// one after the last test the suite's `tearDownAll`. A test's timeout starts
/// again after a stop ([sparingStops]). Call it first in `main`
/// or `testExecutable`, so that its `setUpAll` runs first and its `tearDown`
/// and `tearDownAll` last.
void strict({Install? install}) {
  final uninstalls = <Uninstall>[];
  setUpAll(() {
    _running = true;
    uninstalls
      ..add(installBrowser(_report))
      ..add(_reportingErrorRecords());
    if (install != null) uninstalls.add(install(_report));
  });
  Timer? ticking;
  setUp(() {
    ticking = sparingStops();
    _check('The time before the test (a setUpAll, or the end of the last)');
  });
  tearDown(() {
    ticking?.cancel();
    _check('The test');
  });
  tearDownAll(() {
    for (final uninstall in uninstalls.reversed) {
      uninstall();
    }
    uninstalls.clear();
    _running = false;
    _check('The time after the last test (tearDownAll)');
  });
}

void _check(String when) {
  final problems = takeProblems();
  if (problems.isNotEmpty) {
    throw TestFailure(
      '$when reported ${problems.length} problem(s) it did not take '
      '(photolib_harness):\n${problems.join('\n')}',
    );
  }
}

/// A `testExecutable` of `flutter_test_config.dart`: [strict], then the
/// suite's [testMain].
Future<void> strictTests(
  FutureOr<void> Function() testMain, {
  Install? install,
}) async {
  strict(install: install);
  await testMain();
}

/// The problems reported so far in the running test, which then no longer
/// fail it: a test that provokes one on purpose takes it and checks it.
List<String> takeProblems() {
  final taken = List.of(_problems);
  _problems.clear();
  return taken;
}

/// [print], which also reports every log record of level error that it
/// prints during a test: a JSON object on a line, as the app's loggers print
/// them.
DebugPrint reportingErrorLogs(DebugPrint print) => (message, {wrapWidth}) {
  print(message, wrapWidth: wrapWidth);
  if (message != null && _isErrorLog(message)) {
    _report('Error-level log record: $message');
  }
};

Uninstall _reportingErrorRecords() {
  final listening = Log.records
      .where((record) => record.level == LogLevel.error)
      .listen(
        (record) => _report('Error-level log record: ${record.toJson()}'),
      );
  return () => unawaited(listening.cancel());
}

void _report(String problem) {
  if (_running) _problems.add(problem);
}

bool _isErrorLog(String line) {
  if (!line.trimLeft().startsWith('{')) return false;
  try {
    final record = jsonDecode(line);
    return record is Map && record['level'] == 'error';
  } on FormatException {
    return false;
  }
}
