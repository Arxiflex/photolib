import 'dart:math';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:fixnum/fixnum.dart';
import 'package:photolib_api/kernel.dart';
import 'package:photolib_data/src/metadata.dart';
import 'package:photolib_data/src/organise.dart' as organise;
import 'package:photolib_data/src/replica.dart';
import 'package:protobuf/protobuf.dart' show GeneratedMessage;
import 'package:protobuf/well_known_types/google/protobuf/timestamp.pb.dart';

/// A kernel's entry point: a `photolib.kernel.v1.Method` on its encoded
/// request.
typedef KernelCall = Uint8List Function(int method, Uint8List request);

/// The first range read, which holds most files' metadata; and what the
/// reader may ask for in all, in how many rounds, so that a hostile file
/// costs at most that. As the server's ingest reads
/// (server/…/ingest/extract.rs).
const int _first = 64 << 10;
const int _maxRead = 64 << 20;
const int _maxRounds = 32;

/// What the file at [_path], of [_size] bytes, says about itself, read
/// through [_kernel]'s calls, in rounds: [next] gives the spans to read,
/// which [add] hands over, until it gives none; then [meta] is its metadata
/// and [resolve] its capture time. Synchronous, so that native reads stay so.
/// Throws [KernelPanicked] when the kernel panicked on it.
final class MetadataRead {
  /// A read of the file at [_path], of [_size] bytes, through [_kernel].
  MetadataRead(this._kernel, this._size, this._path);

  final KernelCall _kernel;
  final int _size;
  final String _path;
  final List<FileRange> _ranges = [];
  int _total = 0;

  /// What the kernel read in the spans handed over.
  late ReadMetadataResponse meta;

  /// The spans to read next, as offsets and lengths: the head of the file,
  /// then what the kernel asks for; none once it asks for nothing new or for
  /// more than a file may cost.
  List<(int, int)> next() {
    if (_ranges.isEmpty) return [(0, _total = min(_size, _first))];
    meta = ReadMetadataResponse.fromBuffer(
      _call(
        _kernel,
        Method.METHOD_READ_METADATA,
        ReadMetadataRequest(ranges: _ranges, size: Int64(_size)),
      ),
    );
    final spans = <(int, int)>[];
    for (final s in meta.missing) {
      final at = s.offset.toInt();
      final length = min(s.length.toInt(), _size - at);
      if (at < _size &&
          !_ranges.any((r) => r.offset == at && r.data.length == length)) {
        spans.add((at, length));
      }
    }
    final wanted = spans.fold(0, (n, s) => n + s.$2);
    if (_ranges.length > _maxRounds || _total + wanted > _maxRead) {
      return const [];
    }
    _total += wanted;
    return spans;
  }

  /// Hands over the [data] read at [at].
  void add(int at, Uint8List data) =>
      _ranges.add(FileRange(offset: Int64(at), data: data));

  /// Whether the file's head, the first span read, is an animated image's.
  bool get animated => isAnimated(_ranges.first.data);

  /// The span of the file's last [organise.fingerprintEdge] bytes, which
  /// [fingerprint] takes.
  (int, int) get tail {
    final n = min(_size, organise.fingerprintEdge);
    return (_size - n, n);
  }

  /// What names the file's content (organise.fingerprint), with the bytes of
  /// its [tail].
  Uint8List fingerprint(Uint8List tail) => organise.fingerprint(
    _size,
    _ranges.first.data.sublist(0, tail.length),
    tail,
  );

  /// The capture time resolved, at [now], from what was read and the file's
  /// name and folders.
  ResolveCaptureTimeResponse resolve(Timestamp now) {
    final slash = _path.lastIndexOf('/');
    return ResolveCaptureTimeResponse.fromBuffer(
      _call(
        _kernel,
        Method.METHOD_RESOLVE_CAPTURE_TIME,
        ResolveCaptureTimeRequest(
          ranges: _ranges,
          size: Int64(_size),
          fileName: _path.substring(slash + 1),
          folder: slash < 0 ? '' : _path.substring(0, slash),
          resolvedAt: now,
        ),
      ),
    );
  }
}

/// The values of the `local_asset` row of the file at [path] in which
/// [MetadataRead] read [meta] and [resolved], [animated] if it is an
/// animated image, its content named by [fingerprint].
LocalAssetCompanion companionOf(
  ReadMetadataResponse meta,
  ResolveCaptureTimeResponse resolved,
  String path, {
  required bool animated,
  required Uint8List fingerprint,
}) {
  final time = resolved.captureTime;
  final (motionOffset, motionLength) = _motion(meta);
  final (projection, crop, stereo, heading) = _sphere(meta, path);
  Value<int> known(int n) => n == 0 ? const Value.absent() : Value(n);
  String? text(String s) => s.isEmpty ? null : s;
  return LocalAssetCompanion(
    takenLocal: Value(text(time.localDatetime)),
    tzOffsetMin: Value(time.hasOffsetMinutes() ? time.offsetMinutes : null),
    takenUtc: Value(
      resolved.hasTakenAt()
          ? resolved.takenAt.toDateTime().millisecondsSinceEpoch
          : null,
    ),
    timeSource: Value(time.source),
    timeConfidence: Value(time.confidence),
    timePrecision: Value(_precisions.elementAtOrNull(time.precision.value)),
    lat: Value(meta.hasLocation() ? meta.location.latitude : null),
    lon: Value(meta.hasLocation() ? meta.location.longitude : null),
    make: Value(text(meta.make)),
    model: Value(text(meta.model)),
    width: known(meta.width),
    height: known(meta.height),
    orientation: Value(_degrees.elementAtOrNull(meta.orientation)),
    durationMs: known(meta.durationMs.toInt()),
    frameRate: Value(meta.frameRate > 0 ? meta.frameRate : null),
    facets: Value(_facets(meta, animated: animated)),
    motionOffset: Value(motionOffset),
    motionLength: Value(motionLength),
    projection: Value(projection),
    crop: Value(crop),
    stereo: Value(stereo),
    heading: Value(heading),
    fingerprint: Value(fingerprint),
  );
}

/// Where [meta]'s motion video is in its file, as offset and length.
(int?, int?) _motion(ReadMetadataResponse meta) => meta.hasMotionVideo()
    ? (meta.motionVideo.offset.toInt(), meta.motionVideo.length.toInt())
    : (null, null);

/// [meta]'s facets: `hdr` for what the viewer's native HDR leaf shows
/// (docs/10 §4.5), a gain map, PQ (16), HLG (18) or Dolby Vision.
String _facets(ReadMetadataResponse meta, {required bool animated}) => [
  if (meta.hasMotionVideo()) 'motion_photo',
  if (meta.hasPanorama()) 'panorama',
  if (animated) 'animated',
  if (meta.gainMap ||
      meta.dolbyVision ||
      const {16, 18}.contains(meta.transfer))
    'hdr',
].join(',');

/// How [meta]'s picture is projected (docs/10-client-app.md §4.4), as the
/// replica keeps it: its projection, unless GPano says not to show it as a
/// panorama or [path] is an Insta360 dual fisheye, which says it is
/// equirectangular; its GPano crop when partial; its stereo packing; its
/// middle's compass heading.
(String?, String?, String?, double?) _sphere(
  ReadMetadataResponse meta,
  String path,
) {
  final p = meta.panorama;
  final shown =
      meta.hasPanorama() &&
      (!p.hasUsePanoramaViewer() || p.usePanoramaViewer) &&
      !RegExp(r'\.ins[pv]$', caseSensitive: false).hasMatch(path);
  final partial =
      p.croppedWidth < p.fullWidth || p.croppedHeight < p.fullHeight;
  return (
    shown ? p.projection : null,
    shown && partial
        ? [
            p.croppedLeft,
            p.croppedTop,
            p.croppedWidth,
            p.croppedHeight,
            p.fullWidth,
            p.fullHeight,
          ].join(',')
        : null,
    const {
      StereoMode.STEREO_MODE_TOP_BOTTOM: 'top_bottom',
      StereoMode.STEREO_MODE_LEFT_RIGHT: 'left_right',
      StereoMode.STEREO_MODE_RIGHT_LEFT: 'right_left',
    }[meta.stereoMode],
    shown && p.hasPoseHeadingDegrees() ? p.poseHeadingDegrees : null,
  );
}

const List<String?> _precisions = [
  null,
  'year',
  'month',
  'day',
  'minute',
  'second',
  'ms',
];

/// EXIF orientations as the clockwise rotation MediaStore gives, as Android's
/// ExifInterface maps them: a mirror is dropped.
const List<int> _degrees = [0, 0, 0, 180, 180, 270, 90, 90, 270];

List<int> _call(KernelCall call, Method method, GeneratedMessage request) {
  final response = CallResponse.fromBuffer(
    call(method.value, request.writeToBuffer()),
  );
  if (response.error.code == CallErrorCode.CALL_ERROR_CODE_PANIC) {
    throw const KernelPanicked();
  }
  if (response.hasError()) {
    throw FormatException('kernel error ${response.error.code.name}');
  }
  return response.response;
}

/// The kernel panicked on a file (kernel.panic): it is read as nothing, so
/// that only a change of the file sends it back.
class KernelPanicked implements Exception {
  /// The kernel's panic on a file.
  const KernelPanicked();
}
