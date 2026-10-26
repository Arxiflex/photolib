import 'dart:typed_data';

import 'package:flutter_map/flutter_map.dart'
    show NetworkTileProvider, TileProvider;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:photolib/core/kernel.dart'
    if (dart.library.js_interop) 'package:photolib/core/kernel_web.dart';
import 'package:photolib/core/replica.dart';
import 'package:photolib/features/library/library.dart' show veiledProvider;
import 'package:photolib/features/library/timeline/pipeline.dart';
import 'package:photolib/features/map/map_kernel.dart';
import 'package:photolib/features/map/map_logic.dart';
import 'package:photolib_data/photolib_data.dart';

/// How a page gets the kernel its map index lives in; a test brings its own.
final mapKernelOpenerProvider = Provider<Future<MapKernel> Function()>(
  (ref) => openMapKernel,
);

/// Where the map's background comes from: the tile server of OpenStreetMap,
/// only once the user agreed (`Settings.maps`, docs/admin/privacy.md).
const String tileUrl = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

/// The tiles' source; a test brings its own so that none touches a network.
final mapTileProviderProvider = Provider<TileProvider>(
  (ref) => NetworkTileProvider(httpClient: TileClient(http.Client())),
);

/// How long a tile may take (docs/admin/privacy.md).
const Duration tileTimeout = Duration(seconds: 10);

/// The HTTP client of the map's tiles: it names the app, as the tile servers'
/// usage policy asks, and gives up on a tile after [tileTimeout].
class TileClient extends http.BaseClient {
  /// A client that sends through [_inner].
  new(this._inner);

  final http.Client _inner;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers['User-Agent'] = 'Photolib (org.photolib.app)';
    return _inner.send(request).timeout(tileTimeout);
  }

  @override
  void close() => _inner.close();
}

/// The located items of the library and the kernel's index over them.
class MapData {
  /// The index over [points].
  new(this.points, this.index) : span = timeSpan(points);

  /// The items on the map, by position.
  final GeoPoints points;

  /// The kernel's index of them.
  final MapIndex index;

  /// The earliest and latest capture, or null with no items.
  final ({int from, int to})? span;
}

/// The map's data, built when the page opens (hidden items only while they
/// show) and freed with it.
final FutureProvider<MapData> mapDataProvider = FutureProvider.autoDispose((
  ref,
) async {
  final db = await ref.watch(replicaProvider.future);
  final points = await geoPoints(db, veiled: ref.watch(veiledProvider));
  final kernel = await ref.watch(mapKernelOpenerProvider)();
  ref.onDispose(kernel.close);
  return MapData(points, await MapIndex.build(kernel.call, points));
});

/// The timeline tiles of the items with [ids], newest first.
Future<List<ThumbnailItem>> mapThumbnails(
  Replica db,
  List<Uint8List> ids,
) async => [
  for (final item in await db.mapItems(ids).get()) ThumbnailItem.local(item),
];
