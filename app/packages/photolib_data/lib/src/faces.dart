import 'dart:typed_data';

/// A face found on the device, relative to the upright photo.
class DeviceFace {
  /// A face.
  const DeviceFace({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.score,
    required this.landmarks,
    required this.embedding,
  });

  /// Its box: the top left corner and size, in fractions of the photo.
  final double x;

  /// Its top edge.
  final double y;

  /// Its width.
  final double width;

  /// Its height.
  final double height;

  /// The detector's confidence.
  final double score;

  /// The right eye, left eye, nose and the right and left mouth corners as x, y
  /// pairs.
  final List<double> landmarks;

  /// The unit vector that describes it.
  final List<double> embedding;
}

const _landmarks = 10;
const _header = 2;

/// The faces of a photo as `local_ml` keeps them: the length of an embedding
/// and the number of faces, then for each its score, box, landmarks and
/// embedding, as the half floats `local_ml` stores.
Float32List packFaces(int dim, List<DeviceFace> faces) {
  final out = Float32List(_header + faces.length * (5 + _landmarks + dim));
  out[0] = dim.toDouble();
  out[1] = faces.length.toDouble();
  var at = _header;
  for (final f in faces) {
    for (final v in [
      f.score,
      f.x,
      f.y,
      f.width,
      f.height,
      ...f.landmarks,
      ...f.embedding,
    ]) {
      out[at++] = v;
    }
  }
  return out;
}

/// The faces [packFaces] packed.
List<DeviceFace> unpackFaces(Float32List packed) {
  if (packed.length < _header) return const [];
  final dim = packed[0].toInt();
  final count = packed[1].toInt();
  const fixed = 5 + _landmarks;
  if (packed.length != _header + count * (fixed + dim)) return const [];
  return [
    for (var i = 0; i < count; i++)
      if (_header + i * (fixed + dim) case final at)
        DeviceFace(
          score: packed[at],
          x: packed[at + 1],
          y: packed[at + 2],
          width: packed[at + 3],
          height: packed[at + 4],
          landmarks: packed.sublist(at + 5, at + fixed),
          embedding: packed.sublist(at + fixed, at + fixed + dim),
        ),
  ];
}

/// The floats of IEEE 754 binary16 little-endian [halves], as `local_ml` keeps
/// an output.
Float32List halfFloatsToFloats(Uint8List halves) {
  final data = ByteData.sublistView(halves);
  return Float32List.fromList([
    for (var i = 0; i + 1 < halves.length; i += 2)
      _half(data.getUint16(i, Endian.little)),
  ]);
}

double _half(int h) {
  final sign = h >> 15 == 1 ? -1.0 : 1.0;
  final exponent = h >> 10 & 0x1f;
  final fraction = h & 0x3ff;
  if (exponent == 0) return sign * fraction * 5.960464477539063e-8;
  if (exponent == 0x1f) {
    return fraction == 0 ? sign * double.infinity : double.nan;
  }
  var scale = 1.0;
  for (var e = exponent - 15; e > 0; e--) {
    scale *= 2;
  }
  for (var e = exponent - 15; e < 0; e++) {
    scale /= 2;
  }
  return sign * (1 + fraction / 1024) * scale;
}
