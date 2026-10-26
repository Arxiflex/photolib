// The corpus' 360° videos as decodable twins, and each one's golden frame:
// what FFmpeg's v360 filter, the reference renderer, shows of the twin at
// [goldenAt] through the golden view (sphere_goldens.dart; docs/10-client-
// app.md §4.4). The corpus' payloads do not decode, so each twin is a clip of
// the same projection, picture size and stereo packing (as
// playback_probe.dart's twins). Plain Dart, for browser tests' VM side too.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

const goldenAt = Duration(seconds: 1);

/// How far a target's frame may be from the golden one: the mean absolute
/// difference of their RGB channels, out of 255. Decoders, chroma
/// upsampling and the shader's filtering differ by less; the frame a second
/// on, or 10° of yaw away, by far more.
const goldenTolerance = 4.0;

/// A corpus 360° video's twin, a cubemap or not, stereo or not
/// (`top_bottom`, `left_right`), cropped or not (its Spherical Video V2
/// bounds as the replica's crop: `left,top,width,height,full width,full
/// height`), and its golden frame (PNG).
typedef SphereTwin = ({
  String path,
  bool cube,
  String? stereo,
  String? crop,
  File twin,
  File golden,
});

/// The kind of a twin, which its golden filter depends on.
typedef GoldenFilter = FutureOr<String> Function({
  required bool cube,
  String? stereo,
  String? crop,
});

/// The corpus' spheres and stereo videos, each made in [dir] with the
/// FFmpeg binaries in [ffmpeg], its golden frame through [golden]'s v360
/// filter: a stereo one's twin is a 360° video of its packing, seen one eye
/// (the corpus' own say no projection, so the viewer shows them flat).
Future<List<SphereTwin>> sphereTwins(
  String corpus,
  String ffmpeg,
  Directory dir,
  GoldenFilter golden,
) async {
  final twins = <SphereTwin>[];
  for (final f in Directory('$corpus/golden').listSync(recursive: true)) {
    if (f is! File) continue;
    final r = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
    final m = r['metadata'] as Map<String, dynamic>;
    final quirks = r['quirks'] as List;
    final projection = (m['pano'] as Map?)?['projection'];
    final stereo = [
      for (final q in quirks)
        if ('$q'.startsWith('stereo_')) '$q'.substring(7),
    ].firstOrNull;
    final media = r['media'] as Map<String, dynamic>;
    if (media['kind'] != 'video' || projection == null && stereo == null) {
      continue;
    }
    final (w, h) = (m['width'] as int, m['height'] as int);
    final path = r['path'] as String;
    final cube = projection == 'cubemap';
    final crop = (m['pano'] as Map?)?['cropped'] == true
        ? _bounds(File('$corpus/files/$path').readAsBytesSync(), w, h)
        : null;
    final name = path.replaceAll('/', '-');
    final twin = File('${dir.path}/$name');
    // testsrc, drawn small and scaled, so that its counter is large; the
    // other eye negated.
    String eye(int w, int h) =>
        'testsrc=s=${w ~/ 4}x${h ~/ 4}:r=30:d=2,scale=$w:$h';
    final source = switch (stereo) {
      'top_bottom' => '${eye(w, h ~/ 2)},split[a][b];[b]negate[n];[a][n]vstack',
      'left_right' => '${eye(w ~/ 2, h)},split[a][b];[b]negate[n];[a][n]hstack',
      _ when cube => '${eye(w, h)},v360=e:c3x2:w=$w:h=$h',
      _ => eye(w, h),
    };
    // BT.709, said: players guess it for HD pictures, FFmpeg BT.601.
    await ffmpegRun(ffmpeg, [
      ...['-f', 'lavfi', '-i', '$source,scale=out_color_matrix=bt709'],
      ...['-colorspace', 'bt709', '-color_primaries', 'bt709'],
      ...['-color_trc', 'bt709', '-pix_fmt', 'yuv420p'],
      ...['-c:v', 'libopenh264', '-b:v', '8M', '-movflags', '+faststart'],
      twin.path,
    ]);
    final frame = File('${dir.path}/$name.png');
    await ffmpegRun(ffmpeg, [
      ...['-ss', '${goldenAt.inMilliseconds / 1000}', '-i', twin.path],
      ...[
        '-vf',
        '${await golden(cube: cube, stereo: stereo, crop: crop)},format=rgb24',
      ],
      ...['-frames:v', '1', frame.path],
    ]);
    twins.add((
      path: path,
      cube: cube,
      stereo: stereo,
      crop: crop,
      twin: twin,
      golden: frame,
    ));
  }
  twins.sort((a, b) => a.path.compareTo(b.path));
  return twins;
}

/// The bounds of the Spherical Video V2 `equi` box in [file], whose picture
/// is [w] × [h], as GPano's pixels.
String _bounds(Uint8List file, int w, int h) {
  final at = latin1.decode(file).indexOf('equi') + 8;
  final [top, bottom, left, right] = [
    for (var i = 0; i < 4; i++)
      ByteData.sublistView(file).getUint32(at + 4 * i) / (1 << 32),
  ];
  final (fw, fh) = (
    (w / (1 - left - right)).round(),
    (h / (1 - top - bottom)).round(),
  );
  return [(left * fw).round(), (top * fh).round(), w, h, fw, fh].join(',');
}

/// Runs [ffmpeg]'s `ffmpeg` with [args] on two threads, which share a limit
/// with everything else running.
Future<void> ffmpegRun(String ffmpeg, List<String> args) async {
  final r = await Process.run('$ffmpeg/ffmpeg', [
    ...['-nostdin', '-hide_banner', '-loglevel', 'error', '-y'],
    ...args.take(args.length - 1),
    ...['-threads', '2', args.last],
  ]);
  if (r.exitCode != 0) throw StateError('ffmpeg $args: ${r.stderr}');
}

/// The mean absolute difference of the RGB channels of two RGBA frames.
double frameDifference(Uint8List a, Uint8List b) {
  var sum = 0;
  for (var i = 0; i < a.length; i++) {
    if (i % 4 != 3) sum += (a[i] - b[i]).abs();
  }
  return sum / (a.length * 3 / 4);
}
