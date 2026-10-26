import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver.dart';

/// Appends the results of benchmark/store_cost_test.dart, a test on a device,
/// to $PERF_RESULTS once it ends (benchmark/perf_test.dart prints each).
Future<void> main() => integrationDriver(
  responseDataCallback: (data) =>
      File(Platform.environment['PERF_RESULTS']!).writeAsString(
        [for (final r in data!['results'] as List) '${jsonEncode(r)}\n'].join(),
        mode: FileMode.append,
      ),
);
