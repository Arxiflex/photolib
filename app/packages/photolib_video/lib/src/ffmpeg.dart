import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'executor.dart';
import 'plan.dart';

/// The desktop and server executor: FFmpeg's programs, run from [bin] as child processes. The apps' own FFmpeg is an
/// LGPL build (ADR-0013).
class Ffmpeg implements Executor {
  Ffmpeg(this.bin, {this.threads});

  final String bin;

  /// Caps the threads of each decoder, filter graph and encoder; null leaves FFmpeg's default of about one per core.
  final int? threads;

  /// Encoders by codec, in order of preference (ADR-0043): Media Foundation on Windows, VA-API or NVENC on Linux, then
  /// OpenH264, and libx265 only in an FFmpeg the user installed or the server's. No LGPL software encoder writes
  /// 10-bit HEVC (kvazaar is 8-bit only).
  static const encoders = {
    'h264': ['h264_mf', 'h264_vaapi', 'h264_nvenc', 'libopenh264'],
    'hevc': ['hevc_mf', 'hevc_vaapi', 'hevc_nvenc', 'libx265'],
    'av1': ['libsvtav1'],
  };

  /// The first of [encoders] for [codec] that encodes a frame here: hardware encoders are built in whether or not
  /// their device exists, and Fedora's VA-API has no H.264 or HEVC.
  Future<String?> encoder(String codec, {bool tenBit = false}) async {
    for (final encoder in encoders[codec]!) {
      final upload = _upload(encoder, tenBit);
      final test = await Process.run('$bin/ffmpeg', [
        ..._split('-v error'),
        ..._device(encoder),
        ..._split('-f lavfi -i testsrc2=s=320x180:d=1 -frames:v 1 -vf'),
        'format=${tenBit ? 'yuv420p10le' : 'yuv420p'}${upload.isEmpty ? '' : ',$upload'}',
        ..._split('-c:v $encoder'),
        ..._cap(encoder, 1),
        ..._split('-f null -'),
      ]);
      if (test.exitCode == 0) return encoder;
    }
    return null;
  }

  /// What this FFmpeg lets its device declare (design 04 §3).
  Future<Set<String>> capabilities() async {
    final hevc = await encoder('hevc', tenBit: true);
    return {
      if (await encoder('h264') != null) Capability.h264,
      if (hevc != null) hevc == 'libx265' ? Capability.x265 : Capability.hevc10,
      if (await encoder('av1', tenBit: true) != null) Capability.av1,
    };
  }

  @override
  Future<SourceInfo> probe(String path) async {
    final json = jsonDecode(
      await _run('ffprobe', [
        ..._split('-v error -show_format -show_streams -of json'),
        path,
      ]),
    );
    final streams = (json['streams'] as List).cast<Map<String, Object?>>();
    final video = streams.firstWhere((s) => s['codec_type'] == 'video');
    final matrix = ((video['side_data_list'] as List?) ?? const [])
        .cast<Map>()
        .where((d) => d['side_data_type'] == 'Display Matrix');
    final packets = await _run('ffprobe', [
      ..._split(
        '-v error -select_streams v:0 -show_entries packet=pts_time,flags -of csv=p=0',
      ),
      path,
    ]);
    return SourceInfo(
      width: video['width'] as int,
      height: video['height'] as int,
      // FFmpeg's display matrix turns counter-clockwise.
      rotation: matrix.isEmpty
          ? 0
          : -(matrix.first['rotation'] as num).round() % 360,
      fps: Rational.parse(video['avg_frame_rate'] as String),
      transfer: video['color_transfer'] as String?,
      hasAudio: streams.any((s) => s['codec_type'] == 'audio'),
      durationUs: _us(json['format']['duration'] as String),
      keyframesUs: [
        for (final [time, flags]
            in const LineSplitter().convert(packets).map((l) => l.split(',')))
          if (flags.contains('K')) _us(time),
      ],
      tags: ((json['format']['tags'] as Map?) ?? const {})
          .cast<String, String>(),
    );
  }

  /// A [reference] render runs the same filter graph into lossless FFV1 and PCM in Matroska: what the conformance
  /// suite compares every executor's output with.
  @override
  Future<void> run(
    Plan plan,
    Map<String, String> paths,
    String out, {
    bool reference = false,
  }) async {
    final video = plan.video;
    final encoder = video == null || reference
        ? null
        : await this.encoder(video.codec, tenBit: video.hdr) ??
              (throw StateError('this FFmpeg cannot encode ${video.codec}'));
    await _run('ffmpeg', args(plan, paths, out, encoder, reference: reference));
  }

  /// The command line for [plan], transcoded with [encoder].
  List<String> args(
    Plan plan,
    Map<String, String> paths,
    String out,
    String? encoder, {
    bool reference = false,
  }) {
    final cap = threads == null ? <String>[] : ['-threads', '$threads'];
    final upload = encoder == null ? '' : _upload(encoder, plan.video!.hdr);
    final args = [
      ..._split('-y -v error'),
      if (encoder != null) ..._device(encoder),
      if (threads != null)
        ..._split('-filter_threads $threads -filter_complex_threads $threads'),
      for (final cut in plan.cuts) ...[
        ...cap,
        ..._split('-ss ${cut.startUs}us -t ${cut.durationUs}us -i'),
        paths[cut.assetId]!,
      ],
    ];
    final video = plan.video;
    if (video == null) {
      args.addAll(_split('-map 0:v:0 -map 0:a? -c copy'));
    } else {
      final graph = StringBuffer();
      var next = plan.cuts.length;
      for (final (i, cut) in plan.cuts.indexed) {
        graph.write(
          '[$i:v:0]${cut.toneMap ? _toneMap : ''}${_conform(video)}[v$i];',
        );
        if (!plan.audio) continue;
        if (cut.silence) {
          args.addAll(_split('-f lavfi -t ${cut.durationUs}us -i $_silence'));
        }
        graph.write('[${cut.silence ? '${next++}:a' : '$i:a:0'}]$_audio[a$i];');
      }
      final pads = [
        for (var i = 0; i < plan.cuts.length; i++)
          plan.audio ? '[v$i][a$i]' : '[v$i]',
      ];
      final v = upload.isEmpty ? '[v]' : '[c]';
      graph.write(
        '${pads.join()}concat=n=${plan.cuts.length}:v=1:a=${plan.audio ? '1$v[a]' : '0$v'}',
      );
      if (upload.isNotEmpty) graph.write(';[c]$upload[v]');
      args.addAll([
        '-filter_complex',
        '$graph',
        ..._split('-map [v]'),
        if (plan.audio) ..._split('-map [a]'),
      ]);
      if (reference) {
        args.addAll(_split('-c:v ffv1 -c:a pcm_s16le'));
      } else {
        final bitrate = (video.width * video.height * video.fps.value * 0.25)
            .round();
        args.addAll([
          ..._split(
            '-c:v $encoder -g ${video.fps.value.round()} -b:v $bitrate',
          ),
          if (plan.audio) ..._split('-c:a aac -b:a 160k'),
          if (threads != null) ..._cap(encoder!, threads!),
        ]);
      }
    }
    if (!reference) {
      args.addAll([
        ..._split('-map_metadata -1'),
        for (final MapEntry(:key, :value) in plan.tags.entries) ...[
          '-metadata',
          '$key=$value',
        ],
        ..._split('-movflags +faststart+use_metadata_tags'),
      ]);
    }
    return args..add(out);
  }

  Future<String> _run(String tool, List<String> args) async {
    final result = await Process.run('$bin/$tool', args);
    if (result.exitCode != 0) {
      throw ProcessException(tool, args, '${result.stderr}', result.exitCode);
    }
    return result.stdout as String;
  }
}

/// Caps [encoder] at [n] threads; SVT-AV1 ignores -threads and takes a level of parallelism.
List<String> _cap(String encoder, int n) => [
  ..._split('-threads $n'),
  if (encoder == 'libsvtav1') ..._split('-svtav1-params lp=${min(n, 6)}'),
];

/// VA-API encoders take frames uploaded to the GPU.
List<String> _device(String encoder) => encoder.endsWith('_vaapi')
    ? _split('-init_hw_device vaapi=va -filter_hw_device va')
    : const [];
String _upload(String encoder, bool tenBit) => encoder.endsWith('_vaapi')
    ? 'format=${tenBit ? 'p010' : 'nv12'},hwupload'
    : '';

const _silence = 'anullsrc=r=48000:cl=stereo';
const _audio =
    'aresample=48000,aformat=sample_fmts=fltp:channel_layouts=stereo';
const _toneMap =
    'zscale=t=linear:npl=100,format=gbrpf32le,zscale=p=bt709,tonemap=tonemap=hable:desat=0,'
    'zscale=t=bt709:m=bt709:r=tv,';

/// Restarts the clip's clock, scales it into the frame with letter- or pillarboxing (after FFmpeg's autorotation),
/// then sets rate and colour.
String _conform(VideoFormat v) {
  final (matrix, space, primaries, pixels) = v.hdr
      ? ('bt2020', 'bt2020nc', 'bt2020', 'yuv420p10le')
      : ('bt709', 'bt709', 'bt709', 'yuv420p');
  return 'setpts=PTS-STARTPTS,'
      'scale=${v.width}:${v.height}:force_original_aspect_ratio=decrease:out_color_matrix=$matrix:out_range=tv,'
      'pad=${v.width}:${v.height}:-1:-1,setsar=1,fps=${v.fps},format=$pixels,'
      'setparams=color_primaries=$primaries:color_trc=${v.transfer}:colorspace=$space';
}

List<String> _split(String args) => args.split(' ');

int _us(String seconds) => (double.parse(seconds) * 1e6).round();
