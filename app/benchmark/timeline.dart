/// The timeline benchmark (lib/features/library/timeline/benchmark.dart) over
/// the library `tools/timeline_bench.py` puts in `bench/library.json`; prints
/// or posts its JSON.
library;

import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:photolib/features/library/timeline/benchmark.dart';
import 'package:photolib/features/library/timeline/buckets.dart';
import 'package:photolib/l10n/app_localizations.dart';

import 'platform_io.dart' if (dart.library.js_interop) 'platform_web.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final library = jsonDecode(await rootBundle.loadString('bench/library.json'));
  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: TimelineBenchmark(
          buckets: TimelineBuckets(
            days: List<int>.from(library['days'] as List),
            counts: List<int>.from(library['counts'] as List),
          ),
          onDone: (results) => report(jsonEncode(results)),
        ),
      ),
    ),
  );
}
