/// The rendering spike's probe (ADR-0054), shared by the VM and browser tests and runnable on a phone: the shader
/// renderer against the kernel's CPU reference renderer on synthetic cards, a preview against a tiled
/// full-resolution export, the memory and time of an export by either renderer
/// or by the reference with its tiles on every core, and slider frame times.
library;

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:photolib_editor/edit.dart' show KernelCall;

import 'photolib_editor.dart';

/// Synthetic pictures: a landscape with grain, and the dark gradient and underexposed sky of the precision stress.
enum Card { photo, gradient, sky }

/// The LUT of the parity set: a film-like look with curvature and crosstalk between channels.
final film = () {
  const n = 33;
  final rgb16 = Uint16List(n * n * n * 3);
  for (var i = 0; i < n * n * n; i++) {
    final (r, g, b) = (
      i % n / (n - 1),
      i ~/ n % n / (n - 1),
      i ~/ (n * n) / (n - 1),
    );
    final l = (r + g + b) / 3;
    final out = [
      0.9 * r + 0.1 * l + 0.06 * math.sin(math.pi * r),
      0.95 * g + 0.05 * l,
      0.8 * b + 0.1 * (1 - l) + 0.1 * b * b,
    ];
    for (var c = 0; c < 3; c++) {
      rgb16[i * 3 + c] = (out[c].clamp(0, 1) * 65535).round();
    }
  }
  return Lut(n, rgb16);
}();

/// Each adjustment at its extremes, the LUT, everything at once, and the precision stress of design 11 §4.4.
final recipes = <String, Develop>{
  'neutral': const Develop(),
  'exposure +2': const Develop(exposure: 2),
  'exposure -2': const Develop(exposure: -2),
  'temperature +1': const Develop(temperature: 1),
  'temperature -1': const Develop(temperature: -1),
  'tint +1': const Develop(tint: 1),
  'tint -1': const Develop(tint: -1),
  'contrast +1': const Develop(contrast: 1),
  'contrast -1': const Develop(contrast: -1),
  'clarity +1': const Develop(clarity: 1),
  'clarity -1': const Develop(clarity: -1),
  'saturation +1': const Develop(saturation: 1),
  'saturation -1': const Develop(saturation: -1),
  'lut': Develop(lut: film),
  'all': Develop(
    temperature: 0.3,
    tint: -0.2,
    exposure: 0.5,
    contrast: 0.6,
    clarity: 0.5,
    saturation: 0.3,
    lut: film,
  ),
  'stress': const Develop(exposure: 2, contrast: 1, clarity: 0.8),
};

/// The pixels of a [card] of [width] × [height] in the rectangle at ([x], [y]) of [w] × [h], as a region decoder
/// delivers them: the same picture at every size, with grain per pixel.
Uint8List source(Card card, int width, int height, int x, int y, int w, int h) {
  final out = Uint8List(w * h * 4);
  var i = 0;
  for (var py = y; py < y + h; py++) {
    final v = (py + 0.5) / height;
    for (var px = x; px < x + w; px++) {
      final u = (px + 0.5) / width;
      final (r, g, b) = switch (card) {
        Card.gradient => (0.02 + 0.33 * u, 0.02 + 0.31 * u, 0.02 + 0.29 * u),
        Card.sky => (0.10 + 0.12 * v, 0.18 + 0.14 * v, 0.35 + 0.10 * v),
        Card.photo => _landscape(u, v),
      };
      // Grain of ±4 codes on the photo; the products stay exact as doubles, so dart2js agrees with the VM.
      final grain = card == Card.photo
          ? (((px * 73856093) & 0x3fffffff) ^ ((py * 19349663) & 0x3fffffff)) %
                    9 -
                4
          : 0;
      for (final c in [r, g, b]) {
        out[i++] = ((c * 255 + 0.5).floor() + grain).clamp(0, 255);
      }
      out[i++] = 255;
    }
  }
  return out;
}

(double, double, double) _landscape(double u, double v) {
  var (r, g, b) = v < 0.45
      ? (0.35 + 0.5 * v, 0.55 + 0.4 * v, 0.85 - 0.2 * v)
      : (0.42 - 0.25 * v, 0.5 - 0.3 * v, 0.12 + 0.05 * (u - 0.5).abs());
  for (final (cu, cv, radius, colour) in _discs) {
    final d = math.sqrt((u - cu) * (u - cu) + (v - cv) * (v - cv));
    if (d < radius) (r, g, b) = colour;
  }
  final sun = math.sqrt((u - 0.75) * (u - 0.75) + (v - 0.2) * (v - 0.2));
  final glow = sun < 0.04 ? 1.0 : 0.4 * math.exp(-(sun - 0.04) * 30);
  return (r + glow, g + glow, b + glow * 0.8);
}

const _discs = [
  (0.2, 0.7, 0.09, (0.8, 0.12, 0.1)),
  (0.45, 0.78, 0.08, (0.15, 0.7, 0.2)),
  (0.68, 0.72, 0.07, (0.1, 0.25, 0.85)),
  (0.85, 0.85, 0.05, (0.95, 0.85, 0.2)),
];

/// The CIEDE2000 differences between two RGBA images (sRGB, D65): mean, 99th percentile and maximum.
({double mean, double p99, double max}) deltaE(Uint8List a, Uint8List b) {
  final d = Float64List(a.length ~/ 4);
  for (var i = 0; i < d.length; i++) {
    d[i] = _ciede2000(_lab(a, i * 4), _lab(b, i * 4));
  }
  final mean = d.fold(0.0, (s, v) => s + v) / d.length;
  d.sort();
  return (mean: mean, p99: d[((d.length - 1) * 0.99).round()], max: d.last);
}

final _linear = Float64List.fromList([
  for (var v = 0; v < 256; v++)
    v / 255 <= 0.04045
        ? v / 255 / 12.92
        : math.pow((v / 255 + 0.055) / 1.055, 2.4).toDouble(),
]);

List<double> _lab(Uint8List rgba, int at) {
  final (r, g, b) = (
    _linear[rgba[at]],
    _linear[rgba[at + 1]],
    _linear[rgba[at + 2]],
  );
  double f(double t) => t > 216 / 24389
      ? math.pow(t, 1 / 3).toDouble()
      : t * 24389 / 27 / 116 + 16 / 116;
  final fx = f((0.4124564 * r + 0.3575761 * g + 0.1804375 * b) / 0.95047);
  final fy = f(0.2126729 * r + 0.7151522 * g + 0.0721750 * b);
  final fz = f((0.0193339 * r + 0.1191920 * g + 0.9503041 * b) / 1.08883);
  return [116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz)];
}

double _ciede2000(List<double> x, List<double> y) {
  const deg = math.pi / 180;
  final (l1, a1, b1, l2, a2, b2) = (x[0], x[1], x[2], y[0], y[1], y[2]);
  final cMean =
      (math.sqrt(a1 * a1 + b1 * b1) + math.sqrt(a2 * a2 + b2 * b2)) / 2;
  final c7 = math.pow(cMean, 7);
  final g = 0.5 * (1 - math.sqrt(c7 / (c7 + math.pow(25, 7))));
  final (ap1, ap2) = ((1 + g) * a1, (1 + g) * a2);
  final (cp1, cp2) = (
    math.sqrt(ap1 * ap1 + b1 * b1),
    math.sqrt(ap2 * ap2 + b2 * b2),
  );
  double hue(double b, double a) =>
      a == 0 && b == 0 ? 0 : (math.atan2(b, a) / deg + 360) % 360;
  final (hp1, hp2) = (hue(b1, ap1), hue(b2, ap2));
  final dL = l2 - l1, dC = cp2 - cp1;
  var dh = hp2 - hp1;
  if (cp1 * cp2 == 0) {
    dh = 0;
  } else if (dh > 180) {
    dh -= 360;
  } else if (dh < -180) {
    dh += 360;
  }
  final dH = 2 * math.sqrt(cp1 * cp2) * math.sin(dh * deg / 2);
  final lMean = (l1 + l2) / 2, cpMean = (cp1 + cp2) / 2;
  var hMean = hp1 + hp2;
  if (cp1 * cp2 != 0) {
    hMean = (hp1 - hp2).abs() > 180
        ? (hMean + (hMean < 360 ? 360 : -360)) / 2
        : hMean / 2;
  }
  final t =
      1 -
      0.17 * math.cos((hMean - 30) * deg) +
      0.24 * math.cos(2 * hMean * deg) +
      0.32 * math.cos((3 * hMean + 6) * deg) -
      0.20 * math.cos((4 * hMean - 63) * deg);
  final l50 = (lMean - 50) * (lMean - 50);
  final sL = 1 + 0.015 * l50 / math.sqrt(20 + l50);
  final sC = 1 + 0.045 * cpMean, sH = 1 + 0.015 * cpMean * t;
  final cp7 = math.pow(cpMean, 7);
  final rT =
      -2 *
      math.sqrt(cp7 / (cp7 + math.pow(25, 7))) *
      math.sin(60 * math.exp(-math.pow((hMean - 275) / 25, 2)) * deg);
  return math.sqrt(
    math.pow(dL / sL, 2) +
        math.pow(dC / sC, 2) +
        math.pow(dH / sH, 2) +
        rT * (dC / sC) * (dH / sH),
  );
}

/// The largest difference of a channel between neighbouring pixels: the height of the worst band.
int maxStep(Uint8List rgba, int width) {
  var step = 0;
  for (var i = 0; i < rgba.length; i++) {
    if (i % 4 == 3) continue;
    for (final next in [
      if ((i ~/ 4) % width != width - 1) i + 4,
      i + width * 4,
    ]) {
      if (next < rgba.length) {
        step = math.max(step, (rgba[next] - rgba[i]).abs());
      }
    }
  }
  return step;
}

/// The CPU reference renderer through a kernel binding.
class Reference {
  Reference(this.call);

  final KernelCall call;

  /// `METHOD_DEVELOP` of `proto/photolib/kernel/v1/call.proto`.
  static const _develop = 36;

  /// Renders [rgba] whole, or as the tile at ([x], [y]) of a [fullWidth] × [fullHeight] image with the [guide] of a
  /// previous whole render; returns the pixels and the guide that a whole render computed.
  ({Uint8List rgba, Uint8List? guide}) render(
    Develop develop,
    Uint8List rgba,
    int width,
    int height, {
    Uint8List? guide,
    int fullWidth = 0,
    int fullHeight = 0,
    int x = 0,
    int y = 0,
  }) {
    final lut = develop.lut;
    final request = _Proto()
      ..message(
        1,
        _Proto()
          ..float(1, develop.temperature)
          ..float(2, develop.tint)
          ..float(3, develop.exposure)
          ..float(4, develop.contrast)
          ..float(5, develop.clarity)
          ..float(6, develop.saturation)
          ..message(
            7,
            lut == null
                ? null
                : (_Proto()
                    ..uint(1, lut.size)
                    ..bytes(2, Uint8List.sublistView(lut.rgb16))),
          ),
      )
      ..message(
        2,
        _Proto()
          ..uint(1, width)
          ..uint(2, height)
          ..bytes(3, rgba),
      )
      ..bytes(4, guide)
      ..uint(5, fullWidth)
      ..uint(6, fullHeight)
      ..uint(7, x)
      ..uint(8, y);
    final answer = _fields(call(_develop, request.build()));
    final response = answer[1];
    if (response == null) throw StateError('kernel error: ${answer[2]}');
    final fields = _fields(response as Uint8List);
    return (
      rgba: _fields(fields[1]! as Uint8List)[3]! as Uint8List,
      guide: fields[3] as Uint8List?,
    );
  }
}

/// Every case of the parity set: the shader renderer against the reference on each card and recipe, with the
/// stress cards' worst band against the reference's.
Future<List<Map<String, Object>>> parity(
  ShaderRenderer gpu,
  Reference cpu,
) async {
  final results = <Map<String, Object>>[];
  for (final (card, w, h) in [
    (Card.photo, 384, 256),
    (Card.gradient, 1024, 16),
    (Card.sky, 32, 512),
  ]) {
    final rgba = source(card, w, h, 0, 0, w, h);
    final image = await upload(rgba, w, h);
    final guide = gpu.guide(image);
    for (final MapEntry(key: name, value: develop) in recipes.entries) {
      final shader = await pixels(await gpu.render(develop, image, guide));
      final reference = cpu.render(develop, rgba, w, h).rgba;
      final d = deltaE(shader, reference);
      results.add({
        'card': card.name,
        'recipe': name,
        'mean': d.mean,
        'p99': d.p99,
        'max': d.max,
        'band_excess': maxStep(shader, w) - maxStep(reference, w),
      });
    }
    image.dispose();
    guide.dispose();
  }
  return results;
}

/// A tiled export of the photo card at [width] × [height] with the `all` recipe, by the shader renderer ([gpu]) or
/// the reference ([cpu]), against the preview of its proxy, [scale] times smaller: memory above the baseline
/// ([memory], in bytes, sampled after each tile), time, and the difference of the export, box-filtered in linear
/// light to the proxy's size, from the preview.
Future<Map<String, Object>> export(
  int width,
  int height,
  int scale, {
  ShaderRenderer? gpu,
  Reference? cpu,
  required int Function() memory,
  int tile = 1024,
}) async {
  final develop = recipes['all']!;
  final (pw, ph) = (width ~/ scale, height ~/ scale);
  final sums = Float32List(pw * ph * 3);
  void accumulate(Uint8List rgba, int x, int y, int w) =>
      _place(sums, pw, _blockSums(rgba, w, scale), x, y, w, scale);
  Uint8List average() => _average(sums, pw, ph, scale);

  Future<void> tiles(
    Future<void> Function(Uint8List, int, int, int, int) each,
  ) async {
    for (var y = 0; y < height; y += tile) {
      for (var x = 0; x < width; x += tile) {
        final (w, h) = (math.min(tile, width - x), math.min(tile, height - y));
        await each(source(Card.photo, width, height, x, y, w, h), x, y, w, h);
      }
    }
  }

  await tiles((rgba, x, y, w, h) async => accumulate(rgba, x, y, w));
  final proxy = average();
  final Uint8List preview;
  final Future<Uint8List> Function(Uint8List, int, int, int, int) render;
  if (gpu != null) {
    final image = await upload(proxy, pw, ph);
    final guide = gpu.guide(image);
    preview = await pixels(await gpu.render(develop, image, guide));
    render = (rgba, x, y, w, h) async {
      final tileImage = await upload(rgba, w, h);
      final out = await gpu.render(
        develop,
        tileImage,
        guide,
        x: x,
        y: y,
        fullWidth: width,
        fullHeight: height,
      );
      tileImage.dispose();
      final bytes = await pixels(out);
      out.dispose();
      return bytes;
    };
  } else {
    final whole = cpu!.render(develop, proxy, pw, ph);
    preview = whole.rgba;
    render = (rgba, x, y, w, h) async => cpu
        .render(
          develop,
          rgba,
          w,
          h,
          guide: whole.guide,
          fullWidth: width,
          fullHeight: height,
          x: x,
          y: y,
        )
        .rgba;
  }

  final baseline = memory();
  var peak = baseline;
  var rendering = Duration.zero;
  final total = Stopwatch()..start();
  await tiles((rgba, x, y, w, h) async {
    final watch = Stopwatch()..start();
    final out = await render(rgba, x, y, w, h);
    rendering += watch.elapsed;
    accumulate(out, x, y, w);
    peak = math.max(peak, memory());
  });
  final d = deltaE(average(), preview);
  return {
    'renderer': gpu != null ? 'shader' : 'reference',
    'megapixels': (width * height / 1e6).round(),
    'width': width,
    'height': height,
    'seconds': total.elapsed.inMilliseconds / 1000,
    'render_seconds': rendering.inMilliseconds / 1000,
    'peak_above_baseline_mib': (peak - baseline) / (1 << 20),
    'preview_vs_export': {'mean': d.mean, 'p99': d.p99, 'max': d.max},
  };
}

/// The tile at ([x], [y]) of [w] × [h] of an export by [exportOnCores], as a
/// worker makes it: the photo card's pixels as a region decoder delivers them,
/// developed by [cpu] with the whole image's [guide] (none: left as they are),
/// summed in linear light per [scale] × [scale] block; and the microseconds
/// that developing took.
(Float32List, int) exportTile(
  Reference cpu,
  Uint8List? guide,
  int width,
  int height,
  int scale,
  int x,
  int y,
  int w,
  int h,
) {
  var rgba = source(Card.photo, width, height, x, y, w, h);
  final watch = Stopwatch()..start();
  if (guide != null) {
    rgba = cpu
        .render(
          recipes['all']!,
          rgba,
          w,
          h,
          guide: guide,
          fullWidth: width,
          fullHeight: height,
          x: x,
          y: y,
        )
        .rgba;
  }
  return (_blockSums(rgba, w, scale), watch.elapsedMicroseconds);
}

/// [export] by the reference renderer as every export renders (ADR-0054):
/// [tile] makes each tile with [exportTile] on one of [workers] worker
/// isolates or web workers, all tiles at once. Its time is the wall time from
/// the first tile to the last; its render time the CPU time of developing
/// every tile.
Future<Map<String, Object>> exportOnCores(
  int width,
  int height,
  int scale,
  Reference cpu, {
  required Future<(Float32List, int)> Function(
    Uint8List? guide,
    int x,
    int y,
    int w,
    int h,
  )
  tile,
  required int workers,
  required int Function() memory,
  int size = 1024,
}) async {
  final (pw, ph) = (width ~/ scale, height ~/ scale);
  final sums = Float32List(pw * ph * 3);
  var (peak, rendering) = (0, 0);
  Future<void> tiles(Uint8List? guide) => Future.wait([
    for (var y = 0; y < height; y += size)
      for (var x = 0; x < width; x += size)
        tile(
          guide,
          x,
          y,
          math.min(size, width - x),
          math.min(size, height - y),
        ).then((made) {
          _place(sums, pw, made.$1, x, y, math.min(size, width - x), scale);
          rendering += made.$2;
          peak = math.max(peak, memory());
        }),
  ]);

  await tiles(null);
  final whole = cpu.render(
    recipes['all']!,
    _average(sums, pw, ph, scale),
    pw,
    ph,
  );
  final baseline = peak = memory();
  rendering = 0;
  final watch = Stopwatch()..start();
  await tiles(whole.guide);
  final seconds = watch.elapsedMilliseconds / 1000;
  final d = deltaE(_average(sums, pw, ph, scale), whole.rgba);
  return {
    'renderer': 'reference on $workers workers',
    'megapixels': (width * height / 1e6).round(),
    'width': width,
    'height': height,
    'seconds': seconds,
    'render_seconds': rendering / 1e6,
    'peak_above_baseline_mib': (peak - baseline) / (1 << 20),
    'preview_vs_export': {'mean': d.mean, 'p99': d.p99, 'max': d.max},
  };
}

/// The linear-light sums of a tile [w] pixels wide per [scale] × [scale]
/// block: a pixel of the proxy each.
Float32List _blockSums(Uint8List rgba, int w, int scale) {
  final bw = w ~/ scale;
  final sums = Float32List(rgba.length ~/ 4 ~/ (scale * scale) * 3);
  for (var i = 0; i < rgba.length; i += 4) {
    final p = i ~/ 4 ~/ w ~/ scale * bw + i ~/ 4 % w ~/ scale;
    for (var c = 0; c < 3; c++) {
      sums[p * 3 + c] += _linear[rgba[i + c]];
    }
  }
  return sums;
}

/// Puts a tile's [block] sums, at ([x], [y]) of [w] pixels wide, into the
/// [sums] of a proxy [pw] pixels wide.
void _place(
  Float32List sums,
  int pw,
  Float32List block,
  int x,
  int y,
  int w,
  int scale,
) {
  final bw = w ~/ scale;
  for (var i = 0; i < block.length ~/ 3; i++) {
    final p = (y ~/ scale + i ~/ bw) * pw + x ~/ scale + i % bw;
    sums.setRange(p * 3, p * 3 + 3, block, i * 3);
  }
}

/// The proxy that the [sums] of its [scale] × [scale] blocks average to; the
/// sums start again from zero.
Uint8List _average(Float32List sums, int pw, int ph, int scale) {
  final out = Uint8List(pw * ph * 4);
  for (var p = 0; p < pw * ph; p++) {
    for (var c = 0; c < 3; c++) {
      final l = sums[p * 3 + c] / (scale * scale);
      out[p * 4 + c] = (_encode(l) * 255 + 0.5).floor().clamp(0, 255);
      sums[p * 3 + c] = 0;
    }
    out[p * 4 + 3] = 255;
  }
  return out;
}

double _encode(double l) =>
    l <= 0.0031308 ? 12.92 * l : 1.055 * math.pow(l, 1 / 2.4) - 0.055;

/// Opening the editor on a 2 MP proxy (upload, guide, first frame) and the mean time of a frame while a slider
/// moves. Each frame is read back, as only that waits for the GPU on every backend, so these are upper bounds.
Future<Map<String, Object>> interactivity(ShaderRenderer gpu) async {
  final (w, h) = (1632, 1224);
  final rgba = source(Card.photo, w, h, 0, 0, w, h);
  Future<void> frame(ui.Image image, ui.Image guide, Develop develop) async {
    final out = await gpu.render(develop, image, guide);
    await pixels(out);
    out.dispose();
  }

  final open = Stopwatch()..start();
  final image = await upload(rgba, w, h);
  final guide = gpu.guide(image);
  await frame(image, guide, recipes['all']!);
  open.stop();
  const frames = 10;
  final drag = Stopwatch()..start();
  for (var i = 0; i < frames; i++) {
    await frame(
      image,
      guide,
      Develop(clarity: i / frames, exposure: i / frames, lut: film),
    );
  }
  final ms = drag.elapsedMicroseconds / frames / 1000;
  return {
    'open_ms': open.elapsedMilliseconds,
    'frame_ms': ms,
    'fps': 1000 / ms,
  };
}

/// A protobuf message, written field by field; zero values are left out, as proto3 does.
class _Proto {
  final _bytes = BytesBuilder();

  void _varint(int v) {
    for (; v >= 0x80; v >>= 7) {
      _bytes.addByte(v & 0x7f | 0x80);
    }
    _bytes.addByte(v);
  }

  void uint(int field, int v) {
    if (v == 0) return;
    _varint(field << 3);
    _varint(v);
  }

  void float(int field, double v) {
    if (v == 0) return;
    _varint(field << 3 | 5);
    _bytes.add(
      (ByteData(4)..setFloat32(0, v, Endian.little)).buffer.asUint8List(),
    );
  }

  void bytes(int field, Uint8List? v) {
    if (v == null) return;
    _varint(field << 3 | 2);
    _varint(v.length);
    _bytes.add(v);
  }

  void message(int field, _Proto? m) => bytes(field, m?.build());

  Uint8List build() => _bytes.toBytes();
}

/// The varint and length-delimited fields of a message, by number; the last occurrence wins.
Map<int, Object> _fields(Uint8List m) {
  final fields = <int, Object>{};
  var at = 0;
  int varint() {
    var v = 0;
    for (var shift = 0; ; shift += 7) {
      final b = m[at++];
      v |= (b & 0x7f) << shift;
      if (b < 0x80) return v;
    }
  }

  while (at < m.length) {
    final key = varint();
    switch (key & 7) {
      case 0:
        fields[key >> 3] = varint();
      case 2:
        final length = varint();
        fields[key >> 3] = Uint8List.sublistView(m, at, at += length);
      case 5:
        at += 4;
      default:
        throw FormatException('wire type ${key & 7}');
    }
  }
  return fields;
}
