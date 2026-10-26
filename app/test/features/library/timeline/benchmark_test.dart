import 'dart:ui';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:photolib/features/library/timeline/benchmark.dart';
import 'package:photolib/l10n/app_localizations.dart';

void main() {
  test('the generated library is the size of the spike\'s', () {
    final library = syntheticLibrary();
    expect((library.assets, library.days.length), (1000000, 5569));
    expect(library.days.take(2), [20260331, 20260330]);
    expect(library.counts.every((n) => n > 0), isTrue);
  });

  testWidgets('a test build shows the results as JSON to copy once the '
      'benchmark is done, and stays until then', (tester) async {
    late ValueChanged<Map<String, Object>> done;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        initialRoute: '/benchmark',
        routes: {
          '/': (_) => const SizedBox(),
          '/benchmark': (_) => TimelineBenchmarkPage(
            benchmark: (onDone) {
              done = onDone;
              return const Placeholder();
            },
          ),
        },
      ),
    );
    expect(find.text('Timeline benchmark'), findsOneWidget);
    expect(find.byType(BackButton), findsNothing);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(Placeholder), findsOneWidget, reason: 'still running');

    final copied = <Object?>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async => call.method == 'Clipboard.setData'
          ? copied.add((call.arguments as Map)['text'])
          : null,
    );
    done({'assets': 1000000, 'layout_ms': 0.02});
    await tester.pumpAndSettle();
    const json = '{\n  "assets": 1000000,\n  "layout_ms": 0.02\n}';
    expect(find.text(json), findsOneWidget);
    await tester.tap(find.byTooltip('Copy the results'));
    expect(copied, [json]);
    expect(find.byType(BackButton), findsOneWidget);
  });

  test('nearest-rank percentiles, in milliseconds to two decimals', () {
    final values = [for (var i = 100; i >= 1; i--) i / 10];
    expect(percentiles(values), [5.0, 9.0, 9.9]);
    expect(percentiles([7.123]), [7.12, 7.12, 7.12]);
    expect(percentiles([]), isEmpty);
  });

  test('frames: build, raster, their sum and the share over 60 Hz', () {
    // Frame i builds for i/10 ms and rasterises for 1 ms; two take 20 ms more.
    var t = 0;
    final frames = [
      for (var i = 1; i <= 100; i++)
        FrameTiming(
          vsyncStart: t,
          buildStart: t,
          buildFinish: t += i * 100,
          rasterStart: t,
          rasterFinish: t += i % 50 == 0 ? 21000 : 1000,
          rasterFinishWallTime: t,
          frameNumber: i,
        ),
    ];
    expect(summarize(frames, const Duration(seconds: 2)), {
      'frames': 100,
      'fps': 50.0,
      'build_ms': [5.0, 9.0, 9.9],
      'raster_ms': [1.0, 1.0, 21.0],
      'frame_ms': [6.1, 10.1, 26.0],
      'janky_pct': 2.0,
    });
  });
}
