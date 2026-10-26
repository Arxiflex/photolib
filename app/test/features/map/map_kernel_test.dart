@TestOn('vm')
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:photolib/core/kernel.dart';
import 'package:photolib_data/photolib_data.dart';

GeoPoints points(List<(double, double)> p) => GeoPoints(
  ids: [for (final _ in p) Uint8List(1)],
  cloud: Uint8List(p.length),
  latitudes: Float64List.fromList([for (final (lat, _) in p) lat]),
  longitudes: Float64List.fromList([for (final (_, lon) in p) lon]),
  times: List.filled(p.length, 0),
);

void main() {
  test(
    'a map index lives in an isolate of its own and answers queries',
    () async {
      final kernel = await openMapKernel();
      addTearDown(kernel.close);
      final index = await MapIndex.build(
        kernel.call,
        points([(48.85, 2.35), (48.86, 2.36), (38.72, -9.14), (200, 0)]),
      );
      expect(index.mapped, 3);
      final world = await index.query(-180, -85, 180, 85, 3);
      expect(world.map((c) => c.count).toList()..sort(), [1, 2]);
      // Another index in the same isolate has its own handle.
      final other = await MapIndex.build(kernel.call, points([(0, 0)]));
      expect((await other.query(-180, -85, 180, 85, 3)).single.count, 1);
      expect(
        (await index.query(
          -180,
          -85,
          180,
          85,
          3,
        )).fold<int>(0, (n, c) => n + c.count),
        3,
      );
    },
  );

  test('requests in flight answer in their own order of ask', () async {
    final kernel = await openMapKernel();
    addTearDown(kernel.close);
    final index = await MapIndex.build(
      kernel.call,
      points([for (var i = 0; i < 50; i++) (i * 1.0, i * 2.0)]),
    );
    final answers = await Future.wait([
      for (var z = 0; z < 8; z++) index.query(-180, -85, 180, 85, z),
    ]);
    expect(
      answers.map((a) => a.fold<int>(0, (n, c) => n + c.count)),
      everyElement(50),
    );
  });

  test(
    'closing frees the isolate, twice is fine, and a call after fails',
    () async {
      final kernel = await openMapKernel();
      final index = await MapIndex.build(kernel.call, points([(1, 1)]));
      await kernel.close();
      await kernel.close();
      await expectLater(index.query(-180, -85, 180, 85, 3), throwsStateError);
    },
  );
}
