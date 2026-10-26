import 'dart:math';

import 'edl.dart';

/// A frame rate.
class Rational {
  const Rational(this.num, this.den);

  factory Rational.parse(String text) {
    final [num, den] = text.split('/').map(int.parse).toList();
    final divisor = num.gcd(den);
    return Rational(num ~/ divisor, den ~/ divisor);
  }

  final int num;
  final int den;

  double get value => num / den;

  @override
  bool operator ==(Object other) =>
      other is Rational && other.num == num && other.den == den;

  @override
  int get hashCode => Object.hash(num, den);

  @override
  String toString() => '$num/$den';
}

/// What an executor reads from a source file before planning.
class SourceInfo {
  const SourceInfo({
    required this.width,
    required this.height,
    this.rotation = 0,
    required this.fps,
    this.transfer,
    required this.hasAudio,
    required this.durationUs,
    required this.keyframesUs,
    this.tags = const {},
  });

  /// The JSON the native executors' `probe` returns.
  factory SourceInfo.fromJson(Map<String, Object?> json) => SourceInfo(
    width: json['width'] as int,
    height: json['height'] as int,
    rotation: json['rotation'] as int,
    fps: Rational.parse(json['fps'] as String),
    transfer: json['transfer'] as String?,
    hasAudio: json['hasAudio'] as bool,
    durationUs: json['durationUs'] as int,
    keyframesUs: (json['keyframesUs'] as List).cast<int>(),
    tags: (json['tags'] as Map).cast<String, String>(),
  );

  /// Coded size; [rotation] is clockwise degrees that make it upright.
  final int width;
  final int height;
  final int rotation;
  final Rational fps;

  /// FFmpeg's name of the transfer function: `arib-std-b67` (HLG) and `smpte2084` (PQ) are HDR.
  final String? transfer;
  final bool hasAudio;
  final int durationUs;
  final List<int> keyframesUs;

  /// Container metadata, in FFmpeg's names.
  final Map<String, String> tags;

  bool get hdr => transfer == 'arib-std-b67' || transfer == 'smpte2084';
  int get displayWidth => rotation % 180 == 0 ? width : height;
  int get displayHeight => rotation % 180 == 0 ? height : width;
}

/// A range of one source. A transcode marks the clips that need [silence] (no audio track) or a [toneMap] to SDR.
class Cut {
  const Cut(
    this.assetId,
    this.startUs,
    this.durationUs, {
    this.silence = false,
    this.toneMap = false,
  });

  final String assetId;
  final int startUs;
  final int durationUs;
  final bool silence;
  final bool toneMap;

  Map<String, Object?> toJson() => {
    'assetId': assetId,
    'startUs': startUs,
    'durationUs': durationUs,
    if (silence) 'silence': true,
    if (toneMap) 'toneMap': true,
  };
}

/// The output of a transcode.
class VideoFormat {
  const VideoFormat(
    this.width,
    this.height,
    this.fps,
    this.transfer,
    this.codec,
  );

  final int width;
  final int height;
  final Rational fps;

  /// `bt709` for SDR, else the HDR transfer kept from the sources.
  final String transfer;

  /// `h264`, `hevc` or `av1`.
  final String codec;

  bool get hdr => transfer != 'bt709';
  int get bitDepth => hdr ? 10 : 8;

  Map<String, Object?> toJson() => {
    'width': width,
    'height': height,
    'fps': '$fps',
    'transfer': transfer,
    'bitDepth': bitDepth,
    'codec': codec,
  };
}

/// Capabilities a device declares (design 04 §3) that the planner reads.
abstract final class Capability {
  /// An H.264 encoder: the OS's, VA-API or NVENC, else OpenH264 (the system's or Cisco's download) on Linux.
  static const h264 = 'video.encode.h264';

  /// A 10-bit HEVC encoder of the OS or the GPU.
  static const hevc10 = 'video.encode.hevc10';

  /// libx265 in an FFmpeg the user installed on Linux, which we do not distribute.
  static const x265 = 'video.encode.x265';

  /// A 10-bit AV1 encoder.
  static const av1 = 'video.encode.av1';
  static const playAv1 = 'video.play.av1';
}

/// The library's devices as the planner sees them: this one's capabilities, the others', and whether the server
/// (standard libraries) or a trusted node (private ones) can run an edit.
class Devices {
  const Devices(this.local, {this.others = const [], this.remote = false});

  final Set<String> local;
  final List<Set<String>> others;
  final bool remote;
}

/// What every executor does for an [Edl]: the deterministic part, so that executors differ only in their engine.
class Plan {
  const Plan(
    this.cuts,
    this.video, {
    required this.audio,
    required this.tags,
    this.remote = false,
    this.hdrNotice = false,
  });

  /// A single clip that may stay lossless is remuxed from the keyframe at or before its start (the UI shows the
  /// snapped cut); anything else is transcoded under the merge rules of design 11 §6.3, in a codec and on a device
  /// that [devices] allow (ADR-0043).
  factory Plan.of(
    Edl edl,
    Map<String, SourceInfo> sources, {
    Devices devices = const Devices({}),
  }) {
    final infos = [
      for (final clip in edl.clips)
        switch (sources[clip.assetId]) {
          final info? when clip.startUs < info.durationUs => info,
          _ => throw ArgumentError('${clip.assetId} is unknown or too short'),
        },
    ];
    final first = infos.first;
    final tags = {
      for (final MapEntry(:key, :value) in first.tags.entries)
        if (_keptTags.contains(key) &&
            (edl.keepLocation || !_locationTags.contains(key)))
          key: value,
    };
    if (edl.preferLossless && infos.length == 1) {
      final clip = edl.clips.single;
      final end = min(clip.startUs + clip.durationUs, first.durationUs);
      final start = first.keyframesUs.lastWhere(
        (k) => k <= clip.startUs,
        orElse: () => 0,
      );
      return Plan(
        [Cut(clip.assetId, start, end - start)],
        null,
        audio: first.hasAudio,
        tags: tags,
      );
    }
    final (width, height, fps, transfer) = _normalise(edl, infos);
    final hdr = transfer == 'bt709' ? null : _keepHdr(devices);
    final (codec, remote) = hdr ?? ('h264', _remoteH264(devices));
    final video = VideoFormat(
      width,
      height,
      fps,
      hdr == null ? 'bt709' : transfer,
      codec,
    );
    final audio = infos.any((i) => i.hasAudio);
    final cuts = [
      for (final (i, clip) in edl.clips.indexed)
        Cut(
          clip.assetId,
          clip.startUs,
          min(clip.durationUs, infos[i].durationUs - clip.startUs),
          silence: audio && !infos[i].hasAudio,
          toneMap: infos[i].hdr && !video.hdr,
        ),
    ];
    return Plan(
      cuts,
      video,
      audio: audio,
      tags: tags,
      remote: remote,
      hdrNotice: transfer != 'bt709' && hdr == null,
    );
  }

  final List<Cut> cuts;

  /// Null for a remux, which keeps the source's streams.
  final VideoFormat? video;

  /// A transcode writes AAC-LC 48 kHz stereo, with silence for clips that have no audio.
  final bool audio;

  /// The first clip's capture time, location, make and model; never pairing identifiers.
  final Map<String, String> tags;

  /// The server or the trusted node runs it, from the EDL; else this device.
  final bool remote;

  /// Kept HDR was tone-mapped for want of an encoder whose codec every device plays: the user is told.
  final bool hdrNotice;

  int get durationUs => cuts.fold(0, (sum, cut) => sum + cut.durationUs);

  Map<String, Object?> toJson() => {
    'mode': video == null ? 'remux' : 'transcode',
    'cuts': [for (final cut in cuts) cut.toJson()],
    if (video != null) 'video': video!.toJson(),
    'audio': audio,
    'tags': tags,
    if (remote) 'remote': true,
    if (hdrNotice) 'hdrNotice': true,
  };
}

const _locationTags = {'location', 'com.apple.quicktime.location.ISO6709'};
const _keptTags = {
  'creation_time',
  'com.apple.quicktime.creationdate',
  'com.apple.quicktime.make',
  'com.apple.quicktime.model',
  ..._locationTags,
};

/// Size, rate and the transfer of 11 §6.3: HDR when it may be kept.
(int, int, Rational, String) _normalise(Edl edl, List<SourceInfo> infos) {
  final first = infos.first;
  final shortSides = [
    for (final i in infos) min(i.displayWidth, i.displayHeight),
  ];
  final short = _even(
    [
      shortSides.reduce(max),
      shortSides.every((s) => s >= 2160) ? 2160 : 1080,
      ?edl.maxShortSide,
    ].reduce(min),
  );
  final long = _even(
    short *
        max(first.displayWidth, first.displayHeight) /
        min(first.displayWidth, first.displayHeight),
  );
  int count(Rational fps) => infos.where((i) => i.fps == fps).length;
  final fps = infos
      .map((i) => i.fps)
      .reduce(
        (a, b) =>
            count(a) > count(b) || count(a) == count(b) && a.value >= b.value
            ? a
            : b,
      );
  final transfers = {for (final i in infos) i.transfer};
  final keepHdr =
      edl.keepHdr && infos.every((i) => i.hdr) && transfers.length == 1;
  return (
    first.displayHeight > first.displayWidth ? short : long,
    first.displayHeight > first.displayWidth ? long : short,
    fps.value > 60 ? const Rational(60, 1) : fps,
    keepHdr ? first.transfer! : 'bt709',
  );
}

/// Kept HDR's codec and whether it is encoded remotely, in ADR-0043's order; null to tone-map it.
(String, bool)? _keepHdr(Devices devices) {
  final local = devices.local;
  if (local.contains(Capability.hevc10)) return ('hevc', false);
  if (devices.remote) return ('hevc', true);
  if (local.contains(Capability.x265)) return ('hevc', false);
  final everyonePlaysAv1 = [
    local,
    ...devices.others,
  ].every((d) => d.contains(Capability.playAv1));
  if (local.contains(Capability.av1) && everyonePlaysAv1) return ('av1', false);
  return null;
}

/// Whether H.264 goes to the server or the trusted node, for want of an encoder here.
bool _remoteH264(Devices devices) {
  if (devices.local.contains(Capability.h264)) return false;
  if (devices.remote) return true;
  throw StateError('no H.264 encoder here, and no server or trusted node');
}

int _even(num value) => (value / 2).round() * 2;
