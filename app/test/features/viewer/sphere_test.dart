import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:photolib/features/viewer/sphere.dart';
import 'package:photolib_data/photolib_data.dart' show LocalAssetData;

LocalAssetData row({
  String? projection,
  String? crop,
  String? stereo,
  double? heading,
}) => LocalAssetData(
  id: Uint8List(16),
  source: 'folder',
  volume: '/',
  sourceId: '1',
  size: 1,
  mtime: 0,
  state: 'present',
  favorite: 0,
  trashed: 0,
  edited: 0,
  folder: 0,
  hidden: 0,
  archived: 0,
  tile: 0,
  projection: projection,
  crop: crop,
  stereo: stereo,
  heading: heading,
  width: 6000,
  height: 2000,
);

double deg(double r) => r * 180 / pi;
double rad(double d) => d * pi / 180;

void main() {
  test('a sphere is what its metadata says, and anything else is flat', () {
    expect(Sphere.of(row(projection: 'equirectangular')), const Sphere());
    expect(
      Sphere.of(row(projection: 'equirectangular', heading: 270))?.heading,
      closeTo(3 * pi / 2, 1e-12),
    );
    expect(
      Sphere.of(
        row(
          projection: 'equirectangular',
          crop: '0,1024,8192,2048,8192,4096',
          stereo: 'top_bottom',
        ),
      ),
      const Sphere(
        crop: Rect.fromLTWH(0, 0.25, 1, 0.5),
        eye: Rect.fromLTWH(0, 0, 1, 0.5),
      ),
    );
    expect(
      Sphere.of(row(projection: 'cubemap', stereo: 'right_left')),
      const Sphere(cube: true, eye: Rect.fromLTWH(0.5, 0, 0.5, 1)),
    );
    // A cylinder's picture has the panorama's shape, which says how tall it
    // is on the sphere.
    expect(
      Sphere.of(
        row(projection: 'cylindrical', crop: '0,500,6000,1000,6000,2000'),
      ),
      const Sphere(
        cylinder: true,
        aspect: 3,
        crop: Rect.fromLTWH(0, 0.25, 1, 0.5),
      ),
    );
    final cylinder = Sphere.of(row(projection: 'cylindrical'))!;
    // tan(45°) × 6000 / 2π ≈ 955 pixels above the horizon of 2000.
    expect(cylinder.covers(0, rad(40)), isTrue);
    expect(cylinder.covers(0, rad(50)), isFalse);
    expect(Sphere.of(row(stereo: 'left_right')), isNull);
    expect(Sphere.of(row(projection: 'mesh')), isNull);
    expect(Sphere.of(null), isNull);
  });

  test('a fisheye lens is equidistant: a point twice as far from the middle '
      'is twice the angle off, out to a half turn', () {
    (double, double) degrees((double, double) r) => (
      double.parse(deg(r.$1).toStringAsFixed(6)),
      double.parse(deg(r.$2).toStringAsFixed(6)),
    );
    const fish = SphereView(fov: pi, fisheye: true);
    expect(degrees(fish.ray(const Offset(0.5, 0))), (45.0, 0.0));
    expect(degrees(fish.ray(const Offset(1, 0))), (90.0, 0.0));
    expect(degrees(fish.ray(const Offset(0, -1))), (0.0, 90.0));
    expect(degrees(fish.ray(const Offset(1.5, 0))), (135.0, 0.0));
    expect(
      fish.v360(const Sphere(), const Size(400, 200)),
      'v360=input=e:output=fisheye:interp=linear:w=400:h=200'
      ':h_fov=360.000:v_fov=180.000:yaw=0.000:pitch=0.000',
    );
  });

  test('a panorama larger than its picture loaded is tiled where a view '
      'needs more of it: 512 pixels at the coarsest sample that still puts a '
      'texel on each pixel, only those in view', () {
    const size = Size(16384, 8192);
    const viewport = Size(1000, 800);
    expect(
      const SphereView().tiles(const Sphere(), viewport, size, 4096),
      isNull,
    );
    final (sample, tiles) = SphereView(fov: rad(20))
        .tiles(const Sphere(), viewport, size, 4096)!;
    expect(sample, 1);
    expect(tiles, containsAll([(15, 7), (16, 8)]));
    expect(
      tiles.every((t) => t.$1 >= 14 && t.$1 <= 17 && t.$2 >= 7 && t.$2 <= 8),
      isTrue,
      reason: '$tiles',
    );
    expect(
      SphereView(
        yaw: pi,
        fov: rad(40),
      ).tiles(const Sphere(), viewport, size, 4096)?.$1,
      2,
    );
    expect(
      const SphereView.planet().tiles(const Sphere(), viewport, size, 4096),
      isNull,
    );
  });

  test('a view looks east by its yaw and up by its pitch, through a '
      'rectilinear or a stereographic lens', () {
    (double, double) degrees((double, double) r) => (
      double.parse(deg(r.$1).toStringAsFixed(6)),
      double.parse(deg(r.$2).toStringAsFixed(6)),
    );
    final v = SphereView(yaw: rad(30), pitch: rad(10));
    expect(degrees(v.ray(Offset.zero)), (30.0, 10.0));
    // Half the short side away, at the edge of the lens.
    const level = SphereView(fov: pi / 2);
    expect(degrees(level.ray(const Offset(1, 0))), (45.0, 0.0));
    expect(degrees(level.ray(const Offset(0, -1))), (0.0, 45.0));
    expect(degrees(level.ray(const Offset(0, 1))), (0.0, -45.0));
    const planet = SphereView.planet();
    expect(degrees(planet.ray(Offset.zero)).$2, -90.0);
    // 150° from the nadir, past the horizon.
    expect(degrees(planet.ray(const Offset(1, 0))).$2, 60.0);
  });

  group('a partial panorama is clamped so that no black shows', () {
    // GPano's band from 45° south to 45° north (photosphere-cropped.jpg).
    const band = Sphere(crop: Rect.fromLTWH(0, 0.25, 1, 0.5));
    const size = Size(800, 600);

    test('looking up stops where the picture ends', () {
      final v = SphereView(pitch: rad(80), fov: rad(60)).clamp(band, size);
      expect(v.within(band, size), isTrue);
      expect(deg(v.pitch), closeTo(15.0, 0.6));
      expect(deg(v.fov), closeTo(60, 1e-9));
    });

    test('a lens wider than the band narrows to it', () {
      final v = SphereView(fov: rad(110)).clamp(band, size);
      expect(v.within(band, size), isTrue);
      expect(deg(v.fov), inInclusiveRange(85, 90.01));
      expect(v.pitch, closeTo(0, 1e-6));
    });

    test('a half sphere stops turning at its sides, the nearer way round', () {
      const half = Sphere(crop: Rect.fromLTWH(0.25, 0, 0.5, 1));
      final v = SphereView(yaw: rad(170)).clamp(half, size);
      expect(v.within(half, size), isTrue);
      expect(deg(v.yaw), inInclusiveRange(40, 90));
      final w = SphereView(yaw: rad(-170)).clamp(half, size);
      expect(deg(w.yaw), inInclusiveRange(-90, -40));
    });

    test('any view ends within the picture', () {
      final random = Random(7);
      for (var i = 0; i < 200; i++) {
        final v = SphereView(
          yaw: (random.nextDouble() - 0.5) * 4 * pi,
          pitch: (random.nextDouble() - 0.5) * pi,
          fov: random.nextDouble() * pi,
        ).clamp(band, size);
        expect(v.within(band, size), isTrue, reason: '$i');
      }
    });

    test('a whole sphere and a little planet keep any yaw and pitch', () {
      final v = SphereView(yaw: 3, pitch: 1.2, fov: rad(150));
      expect(v.clamp(const Sphere(), size), v.copyWith(fov: rad(120)));
      const planet = SphereView.planet();
      expect(planet.clamp(band, size), planet);
    });
  });

  test('the level of detail has a texel or more to each pixel', () {
    const sphere = Sphere();
    // 2 tan(37.5°) / 1000 px over 2π / 8192 texels: 2.0 texels a pixel.
    expect(const SphereView().level(sphere, 1000, 8192, 6), 1);
    expect(const SphereView().level(sphere, 1000, 4096, 6), 0);
    expect(const SphereView().level(sphere, 250, 8192, 6), 3);
    expect(const SphereView().level(sphere, 10, 8192, 6), 5);
    expect(SphereView(fov: rad(20)).level(sphere, 1000, 8192, 6), 0);
    // One eye of a stereo frame has half the texels across.
    const eye = Sphere(eye: Rect.fromLTWH(0, 0, 0.5, 1));
    expect(const SphereView().level(eye, 1000, 8192, 6), 0);
  });

  test('libmpv projects a view with the v360 filter of the same lens', () {
    final view = SphereView(yaw: rad(30), pitch: rad(-10), fov: rad(90));
    expect(
      view.v360(const Sphere(), const Size(1280, 720)),
      'v360=input=e:output=flat:interp=linear:w=1280:h=720'
      ':h_fov=121.284:v_fov=90.000:yaw=30.000:pitch=-10.000',
    );
    expect(
      const SphereView.planet().v360(
        const Sphere(cube: true, eye: Rect.fromLTWH(0, 0, 1, 0.5)),
        const Size(600, 800),
      ),
      'v360=input=c3x2:output=sg:in_stereo=tb:interp=linear:w=600:h=800'
      ':h_fov=300.000:v_fov=314.548:yaw=0.000:pitch=-90.000',
    );
    // A cropped picture padded to its full panorama, one eye of it.
    expect(
      view.v360(
        const Sphere(
          crop: Rect.fromLTWH(0.25, 0, 0.5, 1),
          eye: Rect.fromLTWH(0, 0, 0.5, 1),
        ),
        const Size(1280, 720),
      ),
      startsWith(
        'crop=iw*0.500000:ih*1.000000:iw*0.000000:ih*0.000000,'
        'pad=iw/0.500000:ih/1.000000:iw*0.500000:ih*0.000000,'
        'v360=input=e:output=flat:interp=linear:',
      ),
    );
    // v360 takes no yaw past a half turn either way, and drags turn on.
    for (final (turned, yaw) in [(210.0, -150), (-190.0, 170), (540.0, -180)]) {
      expect(
        SphereView(yaw: rad(turned)).v360(const Sphere(), const Size(2, 2)),
        endsWith(':yaw=$yaw.000:pitch=0.000'),
      );
    }
  });
}
