@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:drift/drift.dart' hide isNull;
import 'package:photolib_api/kernel.dart';
import 'package:photolib_data/photolib_data.dart';
import 'package:photolib_data/src/extract_native.dart';
import 'package:photolib_kernel/photolib_kernel.dart';
import 'package:photolib_kernel/testing.dart';
import 'package:photolib_workers/photolib_workers.dart';
import 'package:protobuf/well_known_types/google/protobuf/timestamp.pb.dart';
import 'package:test/test.dart';

final String corpus = Directory('../../../testdata/corpus/files').absolute.path;

MediaFile file(String path) => (root: corpus, path: path);

/// The extracted columns: capture time (wall clock, offset, instant, source,
/// precision), camera, dimensions, orientation, duration, location and
/// facets; `-` for what is left as it was.
List<Object?> describe(LocalAssetCompanion? c) {
  if (c == null) return ['unreadable'];
  Object? v(Value<Object?> value) => value.present ? value.value : '-';
  // To 0.1 m, as the golden records round them.
  double? degrees(double? d) => d == null ? null : (d * 1e6).round() / 1e6;
  final utc = c.takenUtc.value;
  return [
    v(c.takenLocal),
    v(c.tzOffsetMin),
    if (utc == null)
      null
    else
      DateTime.fromMillisecondsSinceEpoch(utc, isUtc: true).toIso8601String(),
    v(c.timeSource),
    v(c.timePrecision),
    v(c.make),
    v(c.model),
    v(c.width),
    v(c.height),
    v(c.orientation),
    v(c.durationMs),
    degrees(c.lat.value),
    degrees(c.lon.value),
    v(c.facets),
  ];
}

void main() {
  final kernel = buildKernel();
  late WorkerPool pool;
  setUpAll(() => pool = WorkerPool([readMetadata], size: 2));
  tearDownAll(() => pool.close());

  test('reads in each file what its golden record says, '
      'the capture time as the kernel resolves it', () async {
    // From testdata/corpus/golden; this host has no zone tables, so no zone
    // comes from a GPS position.
    final expected = {
      'time/zones/india.jpg': [
        ...['2023-04-14T08:30:00', 330, '2023-04-14T03:00:00.000Z'],
        ...['exif:DateTimeOriginal', 'second', 'Canon', 'Canon EOS 5D Mark IV'],
        ...[640, 480, 0, '-', null, null, ''],
      ],
      'stills/gps-sydney.jpg': [
        ...['2019-05-09T15:47:33', 600, '2019-05-09T05:47:33.000Z'],
        ...['exif:DateTimeOriginal', 'second', 'samsung', 'SM-S911B'],
        ...[640, 480, 0, '-', -33.8688, 151.2093, ''],
      ],
      'stills/irot.heic': [
        ...['2021-07-14T12:15:42', 120, '2021-07-14T10:15:42.000Z'],
        ...['exif:DateTimeOriginal', 'second', 'Apple', 'iPhone 13 Pro'],
        ...[4032, 3024, 90, '-', 48.8584, 2.2945, ''],
      ],
      'compound/pano/photosphere.jpg': [
        ...['2022-06-18T18:30:00', 120, '2022-06-18T16:30:00.000Z'],
        ...['exif:DateTimeOriginal', 'second', 'Google', 'Pixel 7'],
        ...[8192, 4096, 0, '-', null, null, 'panorama'],
      ],
      'compound/motion/PXL_20230330_184138390.MP.jpg': [
        ...['2023-03-30T14:41:38.390', -240, '2023-03-30T18:41:38.390Z'],
        ...['exif:DateTimeOriginal', 'ms', 'Google', 'Pixel 7'],
        ...[4080, 3072, 0, '-', null, null, 'motion_photo'],
      ],
      // Its motion photo markers are stale: there is no video.
      'compound/motion/PXL_20230514_100000000.jpg': [
        ...['2023-05-14T12:00:00.000', 120, '2023-05-14T10:00:00.000Z'],
        ...['exif:DateTimeOriginal', 'ms', 'Google', 'Pixel 7'],
        ...[4080, 3072, 0, '-', null, null, ''],
      ],
      // The corpus' movies hold no make or model (kernel/tests/corpus.rs reads none either).
      'video/iphone.mov': [
        ...['2021-07-14T12:15:42', 120, '2021-07-14T10:15:42.000Z'],
        ...['quicktime:creationdate', 'second', null, null],
        ...[1920, 1080, 0, 3000, 48.8584, 2.2945, ''],
      ],
      'video/samsung.mp4': [
        ...[null, null, '2022-07-01T12:00:00.000Z'],
        ...['quicktime:mvhd', 'second', null, null],
        ...[1920, 1080, 0, 3000, null, null, ''],
      ],
      'time/VID_20220107_113306.mp4': [
        ...['2022-01-07T11:33:06', null, null],
        ...['filename:F01', 'second', null, null],
        ...[1920, 1080, 0, 3000, null, null, ''],
      ],
    };
    final paths = expected.keys.toList();

    final found = await kernelExtract(pool, kernel: kernel)([
      for (final p in paths) file(p),
    ], visible: false);

    expect({
      for (final (i, p) in paths.indexed) p: describe(found[i]),
    }, expected);
  });

  test('finds the video of every corpus motion photo where its golden record '
      'says, and none in other files', () async {
    final golden = <String, List<int>?>{
      // Its markers are stale: there is no video.
      'compound/motion/PXL_20230514_100000000.jpg': null,
      'stills/gps-sydney.jpg': null,
    };
    for (final f in Directory(
      '$corpus/../golden',
    ).listSync(recursive: true).whereType<File>()) {
      final record = jsonDecode(f.readAsStringSync());
      if (record['metadata']['motion'] case {
        'offset': final int offset,
        'length': final int length,
      }) {
        golden[record['path'] as String] = [offset, length];
      }
    }
    expect(golden.values.nonNulls, hasLength(greaterThanOrEqualTo(4)));
    final paths = golden.keys.toList();
    final found = await kernelExtract(pool, kernel: kernel)([
      for (final p in paths) file(p),
    ], visible: false);
    expect({
      for (final (i, p) in paths.indexed)
        p: found[i]!.motionOffset.value == null
            ? null
            : [found[i]!.motionOffset.value, found[i]!.motionLength.value],
    }, golden);
  });

  test("marks the corpus' animated GIF, WebP and APNG files animated, and no "
      'still GIF, WebP, PNG or AVIF (FMT-13)', () async {
    final golden = <String, bool>{};
    for (final f in Directory(
      '$corpus/../golden',
    ).listSync(recursive: true).whereType<File>()) {
      final r = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
      final path = r['path'] as String;
      if (RegExp(r'\.(gif|webp|a?png|avif)$').hasMatch(path)) {
        golden[path] = (r['quirks'] as List).contains('animated');
      }
    }
    expect(golden.values.where((a) => a), hasLength(3));
    expect(golden.values.where((a) => !a), hasLength(greaterThan(30)));
    final paths = golden.keys.toList();
    final found = await kernelExtract(pool, kernel: kernel)([
      for (final p in paths) file(p),
    ], visible: false);
    expect({
      for (final (i, p) in paths.indexed)
        p: found[i]!.facets.value!.split(',').contains('animated'),
    }, golden);
  });

  test('an AVIF image sequence is animated, an AVIF image is not', () {
    Uint8List ftyp(String brands) => Uint8List.fromList([
      0,
      0,
      0,
      8 + brands.length,
      ...'ftyp$brands'.codeUnits,
    ]);
    expect(isAnimated(ftyp('avis\x00\x00\x00\x00avifavismsf1')), isTrue);
    expect(isAnimated(ftyp('avif\x00\x00\x00\x00avifmif1')), isFalse);
    expect(isAnimated(Uint8List(0)), isFalse);
  });

  test('a damaged or cut head never fails the test for animation', () {
    final random = Random(13);
    for (final name in ['animated.gif', 'animated.apng', 'animated.webp']) {
      final bytes = File('$corpus/stills/$name').readAsBytesSync();
      for (var i = 0; i < 2000; i++) {
        final head = Uint8List.fromList(
          bytes.sublist(0, random.nextInt(min(bytes.length, 4096))),
        );
        if (head.isNotEmpty) {
          head[random.nextInt(head.length)] ^= 1 << random.nextInt(8);
        }
        expect(() => isAnimated(head), returnsNormally, reason: name);
      }
    }
  });

  test('names each file by its fingerprint: its size, first and last '
      '4 KiB', () async {
    final paths = ['stills/gps-sydney.jpg', 'compound/raw-jpeg/DSC00789.JPG'];
    final found = await kernelExtract(pool, kernel: kernel)([
      for (final p in paths) file(p),
    ], visible: false);
    for (final (i, p) in paths.indexed) {
      final bytes = File('$corpus/$p').readAsBytesSync();
      final edge = bytes.length < 4096 ? bytes.length : 4096;
      expect(
        found[i]!.fingerprint.value,
        fingerprint(
          bytes.length,
          bytes.sublist(0, edge),
          bytes.sublist(bytes.length - edge),
        ),
        reason: p,
      );
    }
  });

  test("keeps a video's frame rate, when its file says it", () async {
    final paths = ['video/mjpeg.mov', 'video/iphone.mov', 'stills/irot.heic'];
    final found = await kernelExtract(pool, kernel: kernel)([
      for (final p in paths) file(p),
    ], visible: false);
    expect(
      [for (final f in found) f!.frameRate],
      [const Value<double?>(10), const Value(null), const Value(null)],
    );
  });

  test('reads the projection, GPano crop, stereo mode and heading of every '
      'corpus sphere and 360° video as its golden record says, and none of '
      'other files', () async {
    final golden = <String, List<Object?>>{};
    for (final f in Directory(
      '$corpus/../golden',
    ).listSync(recursive: true).whereType<File>()) {
      final r = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
      final path = r['path'] as String;
      final quirks = r['quirks'] as List;
      if (r['media']['support'] != 'supported') continue;
      golden[path] = [
        // Insta360's dual fisheyes say they are equirectangular.
        if (path.endsWith('.insp'))
          null
        else
          r['metadata']['pano']?['projection'] as String?,
        if (quirks.contains('photo_sphere_cropped'))
          '0,1024,8192,2048,8192,4096'
        else if (quirks.contains('spherical_video_v2_bounds'))
          '960,0,1920,1920,3840,1920'
        else
          null,
        for (final s in ['top_bottom', 'left_right'])
          if (quirks.contains('stereo_$s')) s,
        if (!quirks.any((q) => '$q'.startsWith('stereo_'))) null,
        r['metadata']['pano']?['heading'],
      ];
    }
    expect(golden.values.where((g) => g.any((v) => v != null)), hasLength(8));
    final paths = golden.keys.toList();
    final found = await kernelExtract(pool, kernel: kernel)([
      for (final p in paths) file(p),
    ], visible: false);
    expect({
      for (final (i, p) in paths.indexed)
        p: [
          for (final c in [
            found[i]?.projection,
            found[i]?.crop,
            found[i]?.stereo,
            found[i]?.heading,
          ])
            c?.value,
        ],
    }, golden);
  });

  test(
    'marks HDR the corpus files whose golden record says they carry a '
    'gain map platforms apply, PQ, HLG or Dolby Vision, and no other',
    () async {
      const hdr = {
        'ultra_hdr',
        'gain_map_iso',
        'gain_map_apple',
        'hdr_pq',
        'hdr_hlg',
        'dolby_vision',
      };
      final golden = <String, bool>{};
      for (final f in Directory(
        '$corpus/../golden',
      ).listSync(recursive: true).whereType<File>()) {
        final r = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
        golden[r['path'] as String] = (r['quirks'] as List).any(hdr.contains);
      }
      expect(golden.values.where((h) => h), hasLength(greaterThanOrEqualTo(6)));
      final paths = golden.keys.toList();
      final found = await kernelExtract(pool, kernel: kernel)([
        for (final p in paths) file(p),
      ], visible: false);
      expect({
        for (final (i, p) in paths.indexed)
          p: '${found[i]?.facets.value}'.split(',').contains('hdr'),
      }, golden);
    },
  );

  test('a file that cannot be read is null, and the others are read', () async {
    final found = await kernelExtract(pool, kernel: kernel)([
      (root: corpus, path: 'gone.jpg'),
      file('time/zones/india.jpg'),
    ], visible: true);
    expect(found.first, isNull);
    expect(found.last?.make, const Value('Canon'));
  });

  test('a file the kernel panics on is read as nothing, '
      'so that it is marked read until it changes', () {
    final library = Kernel.open(kernel);
    final now = Timestamp.fromDateTime(DateTime.now());
    for (final panics in [
      Method.METHOD_READ_METADATA,
      Method.METHOD_RESOLVE_CAPTURE_TIME,
    ]) {
      Uint8List call(int method, Uint8List request) => method == panics.value
          ? Uint8List.fromList(kernelPanic)
          : library.call(method, request);
      final found = readFile(call, file('time/zones/india.jpg'), now);
      expect(found?.toColumns(false), isEmpty, reason: '$panics');
    }
  });

  test('without a kernel every call fails', () async {
    await expectLater(
      kernelExtract(pool, kernel: '$corpus/none.so')([
        file('time/zones/india.jpg'),
      ], visible: false),
      throwsA(isA<JobFailed>()),
    );
  });
}
