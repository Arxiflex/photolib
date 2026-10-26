import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:fixnum/fixnum.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photolib/features/map/map_logic.dart';
import 'package:photolib_api/kernel.dart';
import 'package:photolib_data/photolib_data.dart';

MapCluster cluster(double lat, double lon, int count) =>
    MapCluster(latitude: lat, longitude: lon, count: count);

void main() {
  group('heat', () {
    // A flat projection: a degree is ten pixels, longitude to the right.
    Offset project(double lat, double lon) => Offset(lon * 10, -lat * 10);

    test('weights add up per cell and scale to the heaviest', () {
      final cells = heatCells(
        [cluster(0, 1, 3), cluster(0, 2, 1), cluster(-7, 3, 2)],
        project,
        const Size(100, 100),
        cell: 50,
      );
      expect(
        {for (final c in cells) (c.col, c.row): c.weight},
        {(0, 0): 1.0, (0, 1): closeTo(0.5, 1e-9)},
      );
    });

    test('what projects outside the view is left out', () {
      final cells = heatCells(
        [cluster(0, -5, 1), cluster(90, 0, 1), cluster(0, 5, 4)],
        project,
        const Size(100, 100),
        cell: 50,
      );
      expect(cells.map((c) => (c.col, c.row)), [(1, 0)]);
    });

    test('nothing, nothing', () {
      expect(heatCells([], project, const Size(10, 10), cell: 5), isEmpty);
    });
  });

  group('time slider', () {
    final points = GeoPoints(
      ids: [Uint8List(1), Uint8List(1), Uint8List(1)],
      cloud: Uint8List(3),
      latitudes: Float64List(3),
      longitudes: Float64List(3),
      times: [500, 100, 900],
    );

    test('the span is the earliest and the latest capture', () {
      expect(timeSpan(points), (from: 100, to: 900));
      expect(
        timeSpan(
          GeoPoints(
            ids: [],
            cloud: Uint8List(0),
            latitudes: Float64List(0),
            longitudes: Float64List(0),
            times: [],
          ),
        ),
        isNull,
      );
    });

    test('the whole span is no filter, so queries stay lookups', () {
      final span = timeSpan(points)!;
      expect(timeFilter(span, 0, 1), isNull);
    });

    test('a part of it is a time range, ends included', () {
      final span = timeSpan(points)!;
      final f = timeFilter(span, 0.25, 0.5)!;
      expect(f.timeFrom, Int64(300));
      expect(f.timeTo, Int64(500));
      expect(timeFilter(span, 0, 0.5)!.hasTimeFrom(), isFalse);
      expect(timeFilter(span, 0.5, 1)!.hasTimeTo(), isFalse);
    });
  });

  test('the map reaches no Int64List, which browsers do not have', () {
    final files = [
      ...Directory('lib/features/map').listSync().whereType<File>(),
      File('packages/photolib_data/lib/src/geo.dart'),
      File('packages/photolib_data/lib/src/map_index.dart'),
    ];
    expect(files, hasLength(greaterThan(4)));
    for (final file in files) {
      expect(
        file.readAsStringSync(),
        isNot(contains('Int64List')),
        reason: file.path,
      );
    }
  });

  group('trips', () {
    GeoPoints at(List<(double, double, int)> p) => GeoPoints(
      ids: [for (final _ in p) Uint8List(1)],
      cloud: Uint8List(p.length),
      latitudes: Float64List.fromList([for (final (lat, _, _) in p) lat]),
      longitudes: Float64List.fromList([for (final (_, lon, _) in p) lon]),
      times: [for (final (_, _, t) in p) t],
    );

    test('photos in time order, a long pause apart, are two trips', () {
      final points = at([
        (1, 1, 300),
        (2, 2, 100),
        (3, 3, 200),
        (10, 10, 100000),
        (11, 11, 100100),
      ]);
      expect(tripLines(points, [0, 1, 2, 3, 4]), [
        [(2.0, 2.0), (3.0, 3.0), (1.0, 1.0)],
        [(10.0, 10.0), (11.0, 11.0)],
      ]);
    });

    test('a lone photo is no trip, and only the photos asked for count', () {
      final points = at([(1, 1, 0), (2, 2, 10), (3, 3, 20), (50, 50, 1000000)]);
      expect(tripLines(points, [3]), isEmpty);
      expect(tripLines(points, [0, 2]), [
        [(1.0, 1.0), (3.0, 3.0)],
      ]);
      expect(tripLines(points, const []), isEmpty);
    });

    test('photos at one place and time make no line of their own', () {
      final points = at([(1, 1, 5), (1, 1, 5), (1, 1, 5)]);
      expect(tripLines(points, [0, 1, 2]), isEmpty);
    });
  });

  group('viewport', () {
    test('a box inside the world is itself', () {
      expect(viewport(10, -20, 30, 40), (
        west: 10,
        south: -20,
        east: 30,
        north: 40,
      ));
    });

    test('longitudes past the date line wrap, so west may pass east', () {
      expect(viewport(-200, -10, -170, 10), (
        west: 160,
        south: -10,
        east: -170,
        north: 10,
      ));
      expect(viewport(170, -10, 190, 10), (
        west: 170,
        south: -10,
        east: -170,
        north: 10,
      ));
    });

    test('a view of the whole world, or more, is all longitudes', () {
      expect(viewport(-190, -10, 190, 10), (
        west: -180,
        south: -10,
        east: 180,
        north: 10,
      ));
      expect(viewport(0, -10, 360, 10).east, 180);
    });

    test('latitudes stop at the poles of the map', () {
      final v = viewport(0, -90, 1, 90);
      expect((v.south, v.north), (-85.0511287798, 85.0511287798));
    });
  });

  group('lasso', () {
    test('a path becomes latitude, longitude pairs', () {
      expect(lassoPolygon([(1.0, 2.0), (3.0, 4.0), (5.0, 6.0)]), [
        1.0,
        2.0,
        3.0,
        4.0,
        5.0,
        6.0,
      ]);
    });

    test('repeated points count once; fewer than three is no lasso', () {
      expect(
        lassoPolygon([(1.0, 2.0), (1.0, 2.0), (3.0, 4.0), (3.0, 4.0)]),
        isEmpty,
      );
      expect(lassoPolygon([]), isEmpty);
    });

    test('a long path keeps its shape in at most 256 vertices', () {
      final path = [
        for (var i = 0; i < 5000; i++) (i * 0.001, (i % 7) * 0.001),
      ];
      final polygon = lassoPolygon(path);
      expect(polygon.length, lessThanOrEqualTo(512));
      expect(polygon.take(2), [0.0, 0.0]);
    });
  });

  group('GPX', () {
    const gpx = '''
<?xml version="1.0"?>
<gpx version="1.1" xmlns="http://www.topografix.com/GPX/1/1">
  <trk><name>Morning run</name><type>Running</type>
    <trkseg>
      <trkpt lat="48.85" lon="2.35"><time>2026-10-24T08:00:00Z</time></trkpt>
      <trkpt lat="48.86" lon="2.36"><time>2026-10-24T08:05:00Z</time></trkpt>
      <trkpt lat="bad" lon="2.37"/>
    </trkseg>
    <trkseg><trkpt lat="48.87" lon="2.38"/></trkseg>
  </trk>
  <trk><name>Ride</name><type>cycling</type>
    <trkseg><trkpt lat="1" lon="2"/><trkpt lat="3" lon="4"/></trkseg>
  </trk>
  <trk><trkseg><trkpt lat="0" lon="0"/></trkseg></trk>
</gpx>''';

    test('tracks with their activity, name and valid points', () {
      final tracks = parseGpx(gpx);
      expect(tracks.map((t) => (t.name, t.activity)), [
        ('Morning run', Activity.run),
        ('Ride', Activity.cycle),
        ('', Activity.other),
      ]);
      expect(tracks.first.points.map((p) => (p.lat, p.lon)), [
        (48.85, 2.35),
        (48.86, 2.36),
        (48.87, 2.38),
      ]);
      expect(
        tracks.first.points.first.time,
        DateTime.utc(2026, 10, 24, 8).millisecondsSinceEpoch ~/ 1000,
      );
      expect(tracks.first.points.last.time, isNull);
    });

    test('activities are named by common words, any case', () {
      expect(activityOf('Hiking'), Activity.hike);
      expect(activityOf('walking'), Activity.walk);
      expect(activityOf('CAR'), Activity.drive);
      expect(activityOf(''), Activity.other);
      expect(activityOf('kayaking'), Activity.other);
    });

    test('every activity has a colour of its own', () {
      expect(
        {for (final a in Activity.values) a.color}.length,
        Activity.values.length,
      );
    });

    test('a file that is not GPX has no tracks, and a hostile one is safe', () {
      expect(parseGpx('not xml'), isEmpty);
      expect(parseGpx('<html/>'), isEmpty);
      expect(parseGpx('<!DOCTYPE x [<!ENTITY a "b">]><gpx/>'), isEmpty);
    });
  });
}
