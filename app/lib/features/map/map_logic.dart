import 'dart:math' as math;
import 'dart:ui';

import 'package:fixnum/fixnum.dart';
import 'package:photolib_api/kernel.dart' show MapCluster, MapFilter;
import 'package:photolib_data/photolib_data.dart' show GeoPoints;
import 'package:xml/xml.dart';

/// One cell of the heatmap: its column and row in a grid of cells of
/// [heatCells]'s size, and its weight from 0 to 1.
typedef HeatCell = ({int col, int row, double weight});

/// The heat of [clusters] over a view of [size] pixels, as a grid of square
/// [cell] pixels: [project] puts a position on the view, a cluster weighs its
/// count in the cell it falls in, and the heaviest cell is 1. What projects
/// outside the view is left out.
List<HeatCell> heatCells(
  Iterable<MapCluster> clusters,
  Offset Function(double lat, double lon) project,
  Size size, {
  required double cell,
}) {
  final sums = <(int, int), int>{};
  for (final c in clusters) {
    final at = project(c.latitude, c.longitude);
    if (at.dx < 0 || at.dy < 0 || at.dx >= size.width || at.dy >= size.height) {
      continue;
    }
    final key = (at.dx ~/ cell, at.dy ~/ cell);
    sums[key] = (sums[key] ?? 0) + c.count;
  }
  final heaviest = sums.values.fold(0, math.max);
  return [
    for (final MapEntry(key: (col, row), value: n) in sums.entries)
      (col: col, row: row, weight: n / heaviest),
  ];
}

/// The earliest and latest capture time (seconds) of [points], or null when
/// there are none.
({int from, int to})? timeSpan(GeoPoints points) {
  if (points.length == 0) return null;
  var (from, to) = (points.times.first, points.times.first);
  for (final t in points.times) {
    if (t < from) from = t;
    if (t > to) to = t;
  }
  return (from: from, to: to);
}

/// The filter of a slider that shows [start] to [end] (0 to 1) of [span]: null
/// for all of it, which keeps queries lookups, else a time range with an end
/// the slider has not moved left open.
MapFilter? timeFilter(({int from, int to}) span, double start, double end) {
  if (start <= 0 && end >= 1) return null;
  final length = span.to - span.from;
  final filter = MapFilter();
  if (start > 0) filter.timeFrom = Int64(span.from + (length * start).round());
  if (end < 1) filter.timeTo = Int64(span.from + (length * end).round());
  return filter;
}

/// The pause between photos that ends a trip.
const int tripGapSeconds = 6 * 3600;

/// The trips among the photos at [assets] (positions in [points]): in time
/// order, photos less than [tripGapSeconds] apart are one trip, drawn as the
/// line through their places (MAP-12). A trip that stays in one place, or has
/// one photo, has no line.
List<List<(double, double)>> tripLines(GeoPoints points, Iterable<int> assets) {
  final order = [...assets]
    ..sort((a, b) {
      final byTime = points.times[a].compareTo(points.times[b]);
      return byTime != 0 ? byTime : a.compareTo(b);
    });
  final lines = <List<(double, double)>>[];
  var line = <(double, double)>[];
  int? last;
  void close() {
    if (line.length >= 2 && line.toSet().length >= 2) lines.add(line);
    line = [];
  }

  for (final i in order) {
    if (last != null && points.times[i] - last > tripGapSeconds) close();
    line.add((points.latitudes[i], points.longitudes[i]));
    last = points.times[i];
  }
  close();
  return lines;
}

/// A box on the map in degrees, as the kernel takes it.
typedef MapBox = ({double west, double south, double east, double north});

/// The latitude the map ends at (Web Mercator).
const double maxLatitude = 85.0511287798;

/// The box a camera shows as the kernel takes it: latitudes held to the map,
/// longitudes wrapped into -180 to 180 so that a view across the date line has
/// west greater than east, and a view of all longitudes is all of them.
MapBox viewport(double west, double south, double east, double north) {
  double wrap(double lon) => (lon + 180) % 360 - 180;
  final all = east - west >= 360;
  return (
    west: all ? -180 : wrap(west),
    south: south.clamp(-maxLatitude, maxLatitude),
    east: all ? 180 : (east == 180 ? 180 : wrap(east)),
    north: north.clamp(-maxLatitude, maxLatitude),
  );
}

/// The most vertices a lasso is sent with.
const int maxLassoVertices = 256;

/// A drawn path of (latitude, longitude) points as the filter's polygon, flat
/// pairs: consecutive repeats dropped, thinned to [maxLassoVertices] by
/// stride, and nothing when fewer than three distinct points are left.
List<double> lassoPolygon(List<(double, double)> path) {
  final distinct = <(double, double)>[];
  for (final p in path) {
    if (distinct.isEmpty || distinct.last != p) distinct.add(p);
  }
  if (distinct.length < 3) return const [];
  final stride = (distinct.length / maxLassoVertices).ceil();
  return [
    for (var i = 0; i < distinct.length; i += stride) ...[
      distinct[i].$1,
      distinct[i].$2,
    ],
  ];
}

/// What a track was recorded doing; each has its colour on the map (MAP-12).
enum Activity {
  /// Walking.
  walk(Color(0xFF2E7D32)),

  /// Running.
  run(Color(0xFFD84315)),

  /// Hiking.
  hike(Color(0xFF6D4C41)),

  /// Cycling.
  cycle(Color(0xFF1565C0)),

  /// By car, bus or train.
  drive(Color(0xFF6A1B9A)),

  /// Anything else.
  other(Color(0xFF546E7A));

  new(this.color);

  /// The track's colour.
  final Color color;
}

/// The activity a GPX `type` names, in any case; [Activity.other] for what it
/// does not know.
Activity activityOf(String type) {
  final t = type.trim().toLowerCase();
  bool any(List<String> words) => words.any(t.contains);
  if (any(['hik', 'trek'])) return Activity.hike;
  if (any(['run', 'jog'])) return Activity.run;
  if (any(['walk'])) return Activity.walk;
  if (any(['cycl', 'bik', 'ride'])) return Activity.cycle;
  if (any(['car', 'driv', 'bus', 'train', 'motor'])) return Activity.drive;
  return Activity.other;
}

/// A point of a track; `time` in seconds when the file says.
typedef TrackPoint = ({double lat, double lon, int? time});

/// A GPX track (MAP-12): its name, its activity and the points of all its
/// segments.
class Track {
  /// A track.
  const new(this.name, this.activity, this.points);

  /// Its name, or empty.
  final String name;

  /// What it was recorded doing.
  final Activity activity;

  /// Its valid points, in order.
  final List<TrackPoint> points;
}

/// The tracks of GPX text. Anything that is not GPX, malformed or declaring
/// entities (a DOCTYPE) has none; points whose position is not a number on
/// the map are skipped.
List<Track> parseGpx(String text) {
  final XmlDocument document;
  try {
    document = XmlDocument.parse(text);
  } on XmlException {
    return const [];
  }
  if (document.doctypeElement != null) return const [];
  final tracks = <Track>[];
  for (final trk in document.findAllElements('trk')) {
    String child(XmlElement e, String name) =>
        e.getElement(name)?.innerText.trim() ?? '';
    final points = <TrackPoint>[];
    for (final pt in trk.findAllElements('trkpt')) {
      final lat = double.tryParse(pt.getAttribute('lat') ?? '');
      final lon = double.tryParse(pt.getAttribute('lon') ?? '');
      if (lat == null || lon == null) continue;
      if (lat.abs() > 90 || lon.abs() > 180) continue;
      final time = DateTime.tryParse(child(pt, 'time'));
      points.add((
        lat: lat,
        lon: lon,
        time: time == null ? null : time.millisecondsSinceEpoch ~/ 1000,
      ));
    }
    if (points.isNotEmpty) {
      tracks.add(
        Track(child(trk, 'name'), activityOf(child(trk, 'type')), points),
      );
    }
  }
  return tracks;
}
