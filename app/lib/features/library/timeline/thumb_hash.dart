import 'dart:math';
import 'dart:typed_data';

import 'package:photolib_api/kernel.dart';

/// The ThumbHash of a [w] × [h] image of unpremultiplied RGBA, at most 100 px
/// a side, by the kernel's encoder through [call], the one of the server and
/// the device indexers (ADR-0070).
Uint8List encodeThumbHash(
  Uint8List Function(int method, Uint8List request) call,
  int w,
  int h,
  List<int> rgba,
) {
  final request = EncodeThumbHashRequest(width: w, height: h, rgba: rgba);
  final answer = CallResponse.fromBuffer(
    call(Method.METHOD_ENCODE_THUMB_HASH.value, request.writeToBuffer()),
  );
  if (!answer.hasResponse()) throw StateError('ThumbHash: ${answer.error}');
  return Uint8List.fromList(
    EncodeThumbHashResponse.fromBuffer(answer.response).hash,
  );
}

/// A ThumbHash (https://evanw.github.io/thumbhash/): an image's colours,
/// alpha and aspect ratio in about 25 bytes, which a cell paints until its
/// thumbnail is decoded (docs/10-client-app.md §3.4, T0). Only decoded here;
/// it matches the reference implementation's vectors in
/// `testdata/thumbhash.json`.
class ThumbHash {
  ThumbHash._(this._lx, this._ly, this._alpha, this._dc, this._ac, this.aspect);

  final int _lx, _ly;
  final bool _alpha;
  // L, P, Q and A: a constant term and the varying ones of each channel.
  final List<double> _dc;
  final List<List<double>> _ac;

  /// Width over height, roughly.
  final double aspect;

  /// The hash, or null if [hash] is not one.
  static ThumbHash? tryParse(List<int> hash) {
    if (hash.length < 5) return null;
    final h24 = hash[0] | hash[1] << 8 | hash[2] << 16;
    final h16 = hash[3] | hash[4] << 8;
    final alpha = h24 >> 23 == 1, landscape = h16 >> 15 == 1;
    final long = alpha ? 5 : 7, short = h16 & 7;
    if (short == 0 || (alpha && hash.length < 6)) return null;
    final lx = landscape ? long : short, ly = landscape ? short : long;
    var nibble = 2 * (alpha ? 6 : 5);
    List<double>? channel(int nx, int ny, double scale) {
      final ac = <double>[];
      for (final _ in _terms(nx, ny)) {
        if (nibble >> 1 >= hash.length) return null;
        final bits = hash[nibble >> 1] >> ((nibble++ & 1) << 2) & 15;
        ac.add((bits / 7.5 - 1) * scale);
      }
      return ac;
    }

    // Saturation is boosted 1.25 times to make up for the quantisation.
    final ac = [
      channel(max(3, lx), max(3, ly), (h24 >> 18 & 31) / 31),
      channel(3, 3, (h16 >> 3 & 63) / 63 * 1.25),
      channel(3, 3, (h16 >> 9 & 63) / 63 * 1.25),
      if (alpha) channel(5, 5, (hash[5] >> 4) / 15),
    ];
    if (ac.contains(null)) return null;
    return ThumbHash._(
      max(3, lx),
      max(3, ly),
      alpha,
      [
        (h24 & 63) / 63,
        (h24 >> 6 & 63) / 31.5 - 1,
        (h24 >> 12 & 63) / 31.5 - 1,
        alpha ? (hash[5] & 15) / 15 : 1,
      ],
      ac.cast(),
      lx / ly,
    );
  }

  /// The colour at ([x], [y]) of the image, both from 0 to 1, as unpremultiplied
  /// RGBA from 0 to 1.
  (double, double, double, double) at(double x, double y) =>
      _at(_cosines(x), _cosines(y));

  /// The colours of an [n] + 1 by [n] + 1 grid over the image's centred
  /// square, which a square cell shows, row by row as ARGB.
  Int32List square(int n) {
    final (w, h) = aspect > 1 ? (1 / aspect, 1.0) : (1.0, aspect);
    List<Float64List> axis(double span) => [
      for (var i = 0; i <= n; i++) _cosines(0.5 + span * (i / n - 0.5)),
    ];
    final columns = axis(w);
    return Int32List.fromList([
      for (final fy in axis(h))
        for (final fx in columns)
          switch (_at(fx, fy)) {
            (final r, final g, final b, final a) =>
              (255 * a).round() << 24 |
                  (255 * r).round() << 16 |
                  (255 * g).round() << 8 |
                  (255 * b).round(),
          },
    ]);
  }

  static Float64List _cosines(double t) =>
      Float64List.fromList([for (var c = 0; c < 7; c++) cos(pi * t * c)]);

  (double, double, double, double) _at(Float64List fx, Float64List fy) => _rgba(
    _sum(0, _lx, _ly, fx, fy),
    _sum(1, 3, 3, fx, fy),
    _sum(2, 3, 3, fx, fy),
    _alpha ? _sum(3, 5, 5, fx, fy) : 1,
  );

  double _sum(int channel, int nx, int ny, Float64List fx, Float64List fy) {
    final ac = _ac[channel];
    var sum = _dc[channel], j = 0;
    for (var cy = 0; cy < ny; cy++) {
      for (var cx = cy == 0 ? 1 : 0; cx * ny < nx * (ny - cy); cx++) {
        sum += ac[j++] * fx[cx] * (fy[cy] * 2);
      }
    }
    return sum;
  }

  static (double, double, double, double) _rgba(
    double l,
    double p,
    double q,
    double a,
  ) {
    final b = l - 2 / 3 * p;
    final r = (3 * l - b + q) / 2;
    return (
      r.clamp(0.0, 1.0),
      (r - q).clamp(0.0, 1.0),
      b.clamp(0.0, 1.0),
      a.clamp(0.0, 1.0),
    );
  }

  // The varying terms of an nx × ny channel, in the order the hash stores them.
  static Iterable<(int, int)> _terms(int nx, int ny) sync* {
    for (var cy = 0; cy < ny; cy++) {
      for (var cx = cy == 0 ? 1 : 0; cx * ny < nx * (ny - cy); cx++) {
        yield (cx, cy);
      }
    }
  }
}
