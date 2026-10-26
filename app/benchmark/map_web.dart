// The map page alone in a browser, over `?n=` synthetic located photos (a
// million by default) in the page's own kernel, for looking at it in Chrome's
// device emulation: flutter build web --target benchmark/map_web.dart (after
// tools/kernel/wasm.sh app/web/kernel and tools/data/web.sh app/web). Photos
// cluster around twelve cities, as a library's trips do.
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:photolib/features/map/map_page.dart';
import 'package:photolib/features/map/map_state.dart';
import 'package:photolib/l10n/app_localizations.dart';
import 'package:photolib/ui/theme.dart';
import 'package:photolib_data/photolib_data.dart';

const _cities = [
  (52.52, 13.40),
  (48.86, 2.35),
  (40.71, -74.0),
  (35.68, 139.69),
  (-33.87, 151.21),
  (51.51, -0.13),
  (37.77, -122.42),
  (-23.55, -46.63),
  (28.61, 77.21),
  (55.75, 37.62),
  (-1.29, 36.82),
  (64.15, -21.94),
];

GeoPoints synthetic(int n) {
  final random = Random(42);
  final lat = Float64List(n);
  final lon = Float64List(n);
  final time = List<int>.filled(n, 0);
  for (var i = 0; i < n; i++) {
    final (clat, clon) = _cities[random.nextInt(_cities.length)];
    // A few km around the city, a tenth of them far from it (a trip).
    final far = random.nextInt(10) == 0 ? 20.0 : 0.3;
    lat[i] = (clat + (random.nextDouble() - 0.5) * far).clamp(-80, 80);
    lon[i] = clon + (random.nextDouble() - 0.5) * far * 2;
    time[i] = 1262304000 + random.nextInt(15 * 365 * 86400);
  }
  return GeoPoints(
    ids: List.filled(n, Uint8List(1)),
    cloud: Uint8List(n),
    latitudes: lat,
    longitudes: lon,
    times: time,
  );
}

void main() {
  final n = int.tryParse(Uri.base.queryParameters['n'] ?? '') ?? 1000000;
  runApp(
    ProviderScope(
      overrides: [
        mapDataProvider.overrideWith((ref) async {
          try {
            final points = synthetic(n);
            final kernel = await ref.watch(mapKernelOpenerProvider)();
            ref.onDispose(kernel.close);
            return MapData(points, await MapIndex.build(kernel.call, points));
          } on Object catch (e, s) {
            // error-ok: a benchmark page, read in the browser's console
            debugPrint('map_web: $e\n$s');
            rethrow;
          }
        }),
      ],
      child: MaterialApp(
        theme: appTheme(Brightness.light),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: MapPage(
          // The browser's console is the benchmark's log.
          onQuery: (took, clusters) =>
              debugPrint('map_web: query ${took.inMicroseconds} $clusters'),
        ),
      ),
    ),
  );
}
