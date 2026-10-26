// Where the corpus' 360° twins (sphere_twins.dart) are seen for their golden
// frames, and their spheres: shared by test/features/viewer/
// sphere_golden_test.dart (the shader), sphere_web_test.dart (the browser's
// <video>) and integration_test/playback_probe.dart (libmpv and the filter).
import 'dart:io';
import 'dart:math';

import 'package:material_ui/material_ui.dart';
import 'package:photolib/features/viewer/sphere.dart';

import 'sphere_twins.dart';

// On testsrc's counter and its scrolling band, which change with the time.
const goldenView = SphereView(
  yaw: 120 * pi / 180,
  pitch: -20 * pi / 180,
  fov: pi / 2,
);
const goldenSize = Size(320, 240);

/// The sphere of a twin, a [cube]map or not, [stereo] or not, cropped or not.
Sphere sphereOf({required bool cube, String? stereo, String? crop}) =>
    Sphere(cube: cube, crop: Sphere.cropOf(crop), eye: Sphere.eyeOf(stereo));

/// The golden view of [sphere], within its picture.
SphereView goldenViewOf(Sphere sphere) => goldenView.clamp(sphere, goldenSize);

/// FFmpeg's v360 filter of the golden view of a twin's sphere.
String goldenFilter({required bool cube, String? stereo, String? crop}) {
  final sphere = sphereOf(cube: cube, stereo: stereo, crop: crop);
  return goldenViewOf(sphere).v360(sphere, goldenSize);
}

/// The corpus' 360° twins and their golden frames, made in [dir].
Future<List<SphereTwin>> goldenTwins(
  String corpus,
  String ffmpeg,
  Directory dir,
) => sphereTwins(corpus, ffmpeg, dir, goldenFilter);
