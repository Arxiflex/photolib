// The shared edit decision lists of testdata/edl through the FFmpeg executor, checked like design 11 §9's video
// conformance suite: duration, A/V sync, VMAF against the lossless reference render, rotation, colour and HDR
// signalling, metadata, no pairing ids, and keyframe trims packet by packet. The sources are test patterns made by the
// pinned LGPL FFmpeg of tools/video/ffmpeg.sh.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:photolib_video/photolib_video.dart';

import 'fixtures.dart';

const pairingId = 'com.apple.quicktime.content.identifier';
const landscapeTags = {
  'creation_time': '2021-07-14T08:15:42Z',
  'com.apple.quicktime.creationdate': '2021-07-14T10:15:42+0200',
  'location': '+48.8584+002.2945/',
  pairingId: 'C0FFEE',
};

late Ffmpeg ffmpeg;
late Directory dir;
final paths = <String, String>{};
final sources = <String, SourceInfo>{};

List<String> split(String args) => args.trim().split(RegExp(r' +'));

/// Runs an FFmpeg program; its output is Latin-1, so raw frames come back byte for byte.
Future<String> tool(String name, String args) async {
  final result = await Process.run(
    '${ffmpeg.bin}/$name',
    split(args),
    stdoutEncoding: latin1,
  );
  expect(result.exitCode, 0, reason: '$name $args: ${result.stderr}');
  return '${result.stdout}${result.stderr}';
}

/// A test-pattern clip with a 1 s GOP; [rotation] is clockwise and [hlg] makes it 10-bit AV1 tagged HLG.
Future<void> make(
  String name,
  String size,
  int rate,
  int seconds, {
  bool audio = true,
  bool hlg = false,
  int rotation = 0,
  Map<String, String> tags = const {},
}) async {
  final upright = '${dir.path}/$name-upright.mp4',
      path = paths[name] = '${dir.path}/$name.mp4';
  final sound = audio
      ? '-f lavfi -i sine=r=48000:d=$seconds -c:a aac -ac 2'
      : '';
  final codec = hlg
      ? '-vf setparams=color_primaries=bt2020:color_trc=arib-std-b67:colorspace=bt2020nc,format=yuv420p10le '
            '-c:v libsvtav1 -preset 10 -svtav1-params lp=1'
      : '-c:v libopenh264 -b:v 1M';
  await tool(
    'ffmpeg',
    '-y -v error -threads 1 -filter_threads 1 -f lavfi -i testsrc2=s=$size:r=$rate:d=$seconds $sound $codec '
        '-g $rate $upright',
  );
  // The rotation is an input option, and FFmpeg's default metadata copy drops creation_time.
  final metadata = [
    for (final MapEntry(:key, :value) in tags.entries) '-metadata $key=$value',
  ].join(' ');
  await tool(
    'ffmpeg',
    '-y -v error -display_rotation ${-rotation} -i $upright -map 0 -c copy $metadata '
        '-movflags +use_metadata_tags $path',
  );
  sources[name] = await ffmpeg.probe(path);
}

/// The first video and audio streams of [path], as ffprobe reports them.
Future<(Map, Map?)> streams(String path) async {
  final json = jsonDecode(
    await tool('ffprobe', '-v error -show_streams -of json $path'),
  );
  Map? of(String type) => (json['streams'] as List)
      .cast<Map>()
      .where((s) => s['codec_type'] == type)
      .firstOrNull;
  return (of('video')!, of('audio'));
}

/// Each video packet's presentation time and SHA-256.
Future<List<(double, String)>> packets(String path) async => [
  for (final [time, hash]
      in const LineSplitter()
          .convert(
            await tool(
              'ffprobe',
              '-v error -select_streams v:0 -show_entries packet=pts_time,data_hash -show_data_hash sha256 -of csv=p=0 $path',
            ),
          )
          .map((line) => line.split(',')))
    (double.parse(time), hash),
];

/// The VMAF of [path] against [reference], frame by frame.
Future<double> vmaf(String path, String reference) async {
  const align = 'settb=1/30,setpts=N';
  final log = await tool(
    'ffmpeg',
    '-hide_banner -threads 1 -i $path -threads 1 -i $reference -filter_complex_threads 1 '
        '-lavfi [0:v]$align[d];[1:v]$align[r];[d][r]libvmaf=n_threads=1 -f null -',
  );
  return double.parse(RegExp(r'VMAF score: ([\d.]+)').firstMatch(log)![1]!);
}

/// The mean luma, in 8-bit code values, of the frame shown at [seconds].
Future<double> luma(String path, double seconds) async {
  final log = await tool(
    'ffmpeg',
    '-hide_banner -ss $seconds -i $path -frames:v 1 '
        '-vf format=yuv420p,signalstats,metadata=print:key=lavfi.signalstats.YAVG -f null -',
  );
  return double.parse(RegExp(r'YAVG=([\d.]+)').firstMatch(log)![1]!);
}

/// Whether columns [from, to) of the frame shown at [seconds] are black, in a 320-pixel-wide video.
Future<bool> black(String path, double seconds, int from, int to) async {
  final frame = await tool(
    'ffmpeg',
    '-v error -ss $seconds -i $path -frames:v 1 -vf format=gray -f rawvideo -',
  );
  return [
    for (var i = 0; i < frame.length; i++)
      if (i % 320 >= from && i % 320 < to) frame.codeUnitAt(i),
  ].every((luma) => luma <= 24);
}

void expectTiming((Map, Map?) s, double seconds) {
  double at(Map stream, String key) => double.parse(stream[key] as String);
  final (video, audio) = s;
  expect(
    at(video, 'duration'),
    closeTo(seconds, 1 / 30 + 0.001),
    reason: 'duration ± 1 frame',
  );
  expect(
    at(audio!, 'start_time'),
    closeTo(at(video, 'start_time'), 0.02),
    reason: 'A/V sync ± 20 ms',
  );
}

/// Runs the plan of fixture [name] for [devices] and its lossless reference, checks the video stream's [format], the
/// timing and VMAF ≥ 93, and returns the output.
Future<String> transcode(
  String name,
  Devices devices,
  String format,
  double seconds,
) async {
  final plan = Plan.of(fixture(name), sources, devices: devices);
  final out = '${dir.path}/$name.mp4', reference = '${dir.path}/$name.mkv';
  await ffmpeg.run(plan, paths, out);
  await ffmpeg.run(plan, paths, reference, reference: true);
  final s = await streams(out);
  const keys =
      'codec_name width height r_frame_rate avg_frame_rate pix_fmt color_primaries color_transfer color_space';
  expect(split(keys).map((key) => s.$1[key]).join(' '), format);
  expectTiming(s, seconds);
  expect(await vmaf(out, reference), greaterThanOrEqualTo(93));
  return out;
}

void main() {
  setUpAll(() async {
    final bin = await Process.run('bash', ['../../../tools/video/ffmpeg.sh']);
    expect(bin.exitCode, 0, reason: '${bin.stderr}');
    // Shared machines cap each user's threads, and SVT-AV1 alone starts about a hundred.
    ffmpeg = Ffmpeg('${bin.stdout}'.trim(), threads: 1);
    dir = await Directory.systemTemp.createTemp('photolib_video');
    await make('landscape', '320x180', 30, 4, tags: landscapeTags);
    await make(
      'portrait',
      '320x180',
      30,
      4,
      rotation: 90,
      tags: {
        'creation_time': '2021-12-24T17:30:00Z',
        'location': '+40.6892-074.0445/',
        pairingId: 'BEEF',
      },
    );
    await make('silent', '256x144', 25, 2, audio: false);
    await make(
      'hlg',
      '320x180',
      30,
      3,
      hlg: true,
      tags: {'creation_time': '2022-03-05T17:00:00Z'},
    );
    await make('hlg-small', '256x144', 25, 2, hlg: true);
  });

  tearDownAll(() => dir.delete(recursive: true));

  test('probes size, rotation, rate, transfer, audio, keyframes and tags', () {
    final portrait = sources['portrait']!;
    expect(
      (
        portrait.displayWidth,
        portrait.displayHeight,
        portrait.rotation,
        '${portrait.fps}',
        portrait.hasAudio,
      ),
      (180, 320, 90, '30/1', true),
    );
    expect(portrait.keyframesUs, [0, 1000000, 2000000, 3000000]);
    expect(portrait.tags, containsPair(pairingId, 'BEEF'));
    expect(
      (sources['hlg']!.transfer, sources['hlg']!.hdr),
      ('arib-std-b67', true),
    );
    expect(sources['silent']!.hasAudio, false);
  });

  test(
    'the LGPL build lets its device declare H.264 and 10-bit AV1, never libx265',
    () async {
      final capabilities = await ffmpeg.capabilities();
      expect(capabilities, containsAll([Capability.h264, Capability.av1]));
      expect(capabilities, isNot(contains(Capability.x265)));
    },
  );

  test(
    'a keyframe trim copies every packet and keeps the rotation and metadata, but no pairing id',
    () async {
      final plan = Plan.of(fixture('trim'), sources);
      final out = '${dir.path}/trim.mp4';
      await ffmpeg.run(plan, paths, out);

      expect((await packets(out)).map((p) => p.$2), [
        for (final (time, hash) in await packets(paths['portrait']!))
          if (time >= 1 && time < 3.5) hash,
      ]);
      final result = await ffmpeg.probe(out);
      expect(result.rotation, 90);
      expect(
        result.tags,
        containsPair('creation_time', '2021-12-24T17:30:00Z'),
      );
      expect(result.tags, containsPair('location', '+40.6892-074.0445/'));
      expect(result.tags, isNot(contains(pairingId)));
      expectTiming(await streams(out), 2.5);
    },
  );

  test(
    'heterogeneous clips merge into one SDR H.264 stream with the first clip\'s metadata',
    () async {
      final out = await transcode(
        'merge',
        Devices(await ffmpeg.capabilities()),
        'h264 320 180 30/1 30/1 yuv420p bt709 bt709 bt709',
        7.5,
      );
      final audio = (await streams(out)).$2!;
      expect(
        split(
          'codec_name sample_rate channels',
        ).map((key) => audio[key]).join(' '),
        'aac 48000 2',
      );
      // The portrait clip (2 s to 4 s) is turned upright and pillarboxed; the landscape one fills the frame.
      expect(
        (
          await black(out, 3, 0, 80),
          await black(out, 3, 240, 320),
          await black(out, 1, 0, 80),
        ),
        (true, true, false),
      );
      // The HLG clip (5.5 s to 7.5 s) is tone-mapped, not merely relabelled BT.709: its luma moves.
      expect(
        (await luma(out, 6.5) - await luma(paths['hlg']!, 1)).abs(),
        greaterThan(6),
      );
      final tags = (await ffmpeg.probe(out)).tags;
      for (final key in [
        'creation_time',
        'com.apple.quicktime.creationdate',
        'location',
      ]) {
        expect(tags, containsPair(key, landscapeTags[key]));
      }
      expect(tags, isNot(contains(pairingId)));
    },
  );

  test(
    'HLG clips merge into 10-bit HLG in AV1 when every device plays it and there is no HEVC encoder',
    () async {
      final out = await transcode(
        'merge-hdr',
        const Devices(
          {Capability.h264, Capability.av1, Capability.playAv1},
          others: [
            {Capability.playAv1},
          ],
        ),
        'av1 320 180 30/1 30/1 yuv420p10le bt2020 arib-std-b67 bt2020nc',
        2.5,
      );
      expect(
        (await ffmpeg.probe(out)).tags,
        containsPair('creation_time', '2022-03-05T17:00:00Z'),
      );
    },
  );

  test(
    'HLG clips merge into tone-mapped SDR H.264 when a device plays no AV1',
    () => transcode(
      'merge-hdr',
      const Devices(
        {Capability.h264, Capability.av1, Capability.playAv1},
        others: [
          {Capability.h264},
        ],
      ),
      'h264 320 180 30/1 30/1 yuv420p bt709 bt709 bt709',
      2.5,
    ),
  );
}
