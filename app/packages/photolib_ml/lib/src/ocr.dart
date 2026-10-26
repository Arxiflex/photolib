/// PP-OCRv5 on a picture (M5-08, ADR-0388), as the server's `photolib_ml::ocr`
/// does it: the detector finds lines of text, each recogniser of the three
/// scripts reads each line and the reading surest of itself stands. Pure Dart
/// over an [OcrRun] of the models, so that any isolate can run it.
library;

import 'dart:math';
import 'dart:typed_data';

import 'package:photolib_ml/src/ocr_charsets.g.dart';

/// The detector's name in a registry, as `id@revision/file`.
const ocrDetector = 'ppocr-v5-det@1/det.onnx';

/// The recognisers, by the script they read.
enum OcrScript {
  /// Latin script.
  latin('ppocr-v5-rec-latin@1/rec.onnx'),

  /// Cyrillic: Russian, Ukrainian, Belarusian and Bulgarian.
  eslav('ppocr-v5-rec-eslav@1/rec.onnx'),

  /// Chinese and Japanese.
  chinese('ppocr-v5-rec-chinese@1/rec.onnx');

  new(this.file);

  /// The recogniser's file, as `id@revision/file`.
  final String file;

  /// Its characters: the dictionary's lines, then the space. Class 0 of its
  /// output is the blank, class `n` the `n`-th of these.
  List<String> get charset => _charsets[this] ??= [
    ...switch (this) {
      latin => latinDictionary,
      eslav => eslavDictionary,
      chinese => chineseDictionary,
    }.split('\n').where((line) => line.isNotEmpty),
    ' ',
  ];
}

final _charsets = <OcrScript, List<String>>{};

/// Runs the model [file] (`id@revision/file`) on [data], of [shape], and gives
/// its first output.
typedef OcrRun = Float32List Function(
  String file,
  List<int> shape,
  Float32List data,
);

/// A picture of 8-bit RGBA pixels, row by row.
typedef OcrPicture = ({int width, int height, Uint8List rgba});

/// The longest side the detector sees; larger pictures are shrunk to it.
const _side = 1280;
const _pixel = 0.3;
const _blob = 0.6;
const _height = 48;
const _widest = 3200;

/// The text of [picture], one line of it per line of text, cleaned: empty when
/// it holds none.
String readText(OcrRun run, OcrPicture picture) {
  if (picture.width <= 0 ||
      picture.height <= 0 ||
      picture.rgba.length != picture.width * picture.height * 4) {
    throw ArgumentError('not a picture of 8-bit RGBA pixels');
  }
  final lines = <String>[];
  for (final box in _detect(run, picture)) {
    final crop = _crop(picture, box);
    var best = ('', 0.0);
    for (final script in OcrScript.values) {
      final read = _recognise(run, script, crop);
      if (read.$2 > best.$2) best = read;
    }
    if (best.$1.trim().isNotEmpty) lines.add(best.$1);
  }
  return cleanOcrText(lines.join('\n'));
}

/// The longest text kept for a picture.
const maxOcrChars = 20000;

/// Text as stored and shown: no NUL or control characters but line breaks and
/// tabs, no bidirectional overrides, spaces trimmed, at most [maxOcrChars]
/// characters. Markup stays as it was read, inert text.
String cleanOcrText(String text) {
  final kept = StringBuffer();
  var count = 0;
  for (final rune in text.runes) {
    if (count == maxOcrChars) break;
    final control = rune < 0x20 || (rune >= 0x7f && rune < 0xa0);
    final bidi =
        rune == 0x61c ||
        rune == 0x200e ||
        rune == 0x200f ||
        (rune >= 0x202a && rune <= 0x202e) ||
        (rune >= 0x2066 && rune <= 0x2069);
    if ((control && rune != 0x0a && rune != 0x09) || bidi) continue;
    kept.writeCharCode(rune);
    count++;
  }
  return kept.toString().trim();
}

/// Greedy CTC decoding of [probabilities], steps of `charset.length + 1`
/// scores: class 0 is the blank. A repeat with no blank between is one
/// character. And the mean score of the characters chosen: how sure the
/// recogniser was, 0 for none.
(String, double) decodeCtc(Float32List probabilities, List<String> charset) {
  final classes = charset.length + 1;
  final text = StringBuffer();
  var sum = 0.0;
  var count = 0;
  var last = 0;
  for (var at = 0; at + classes <= probabilities.length; at += classes) {
    var best = 0;
    var score = -double.maxFinite;
    for (var c = 0; c < classes; c++) {
      if (probabilities[at + c] > score) {
        best = c;
        score = probabilities[at + c];
      }
    }
    if (best != last && best > 0) {
      text.write(charset[best - 1]);
      sum += score;
      count++;
    }
    last = best;
  }
  return (text.toString(), count == 0 ? 0 : sum / count);
}

typedef _Box = ({double x0, double y0, double x1, double y1});

List<_Box> _detect(OcrRun run, OcrPicture picture) {
  final scale = min(1, _side / max(picture.width, picture.height));
  int fit(int n) => max(1, (n * scale / 32).round()) * 32;
  final (w, h) = (fit(picture.width), fit(picture.height));
  const mean = [0.485, 0.456, 0.406];
  const std = [0.229, 0.224, 0.225];
  final input = _planes(
    _resize(picture, w, h),
    (c, v) => (v / 255 - mean[c]) / std[c],
  );
  final map = run(ocrDetector, [1, 3, h, w], input);
  if (map.length != w * h) {
    throw StateError("the detector's map is not the picture's size");
  }
  final seen = Uint8List(w * h);
  final boxes = <_Box>[];
  final stack = <int>[];
  for (var start = 0; start < w * h; start++) {
    if (seen[start] == 1 || map[start] <= _pixel) continue;
    var (x0, y0, x1, y1) = (w, h, 0, 0);
    var sum = 0.0;
    var count = 0;
    stack.add(start);
    seen[start] = 1;
    while (stack.isNotEmpty) {
      final at = stack.removeLast();
      final (x, y) = (at % w, at ~/ w);
      (x0, y0, x1, y1) = (min(x0, x), min(y0, y), max(x1, x), max(y1, y));
      sum += map[at];
      count++;
      for (var dy = -1; dy <= 1; dy++) {
        for (var dx = -1; dx <= 1; dx++) {
          final (nx, ny) = (x + dx, y + dy);
          if (nx < 0 || ny < 0 || nx >= w || ny >= h) continue;
          final next = ny * w + nx;
          if (seen[next] == 0 && map[next] > _pixel) {
            seen[next] = 1;
            stack.add(next);
          }
        }
      }
    }
    final (bw, bh) = ((x1 - x0 + 1).toDouble(), (y1 - y0 + 1).toDouble());
    if (min(bw, bh) < 3 || sum / count <= _blob) continue;
    final grow = bw * bh * 1.5 / (2 * (bw + bh));
    final (sx, sy) = (picture.width / w, picture.height / h);
    boxes.add((
      x0: max(0, (x0 - grow) * sx),
      y0: max(0, (y0 - grow) * sy),
      x1: min(picture.width.toDouble(), (x1 + 1 + grow) * sx),
      y1: min(picture.height.toDouble(), (y1 + 1 + grow) * sy),
    ));
  }
  return _readingOrder(boxes);
}

/// Top to bottom, and left to right among boxes whose tops are within half a
/// box height of each other.
List<_Box> _readingOrder(List<_Box> boxes) {
  boxes.sort((a, b) {
    final top = a.y0.compareTo(b.y0);
    return top != 0 ? top : a.x0.compareTo(b.x0);
  });
  for (var i = 1; i < boxes.length; i++) {
    for (var j = i; j >= 1; j--) {
      final (a, b) = (boxes[j - 1], boxes[j]);
      if ((b.y0 - a.y0).abs() < min(b.y1 - b.y0, a.y1 - a.y0) / 2 &&
          b.x0 < a.x0) {
        boxes[j - 1] = b;
        boxes[j] = a;
      } else {
        break;
      }
    }
  }
  return boxes;
}

OcrPicture _crop(OcrPicture picture, _Box box) {
  final x0 = box.x0.floor().clamp(0, picture.width - 1);
  final y0 = box.y0.floor().clamp(0, picture.height - 1);
  final x1 = box.x1.ceil().clamp(x0 + 1, picture.width);
  final y1 = box.y1.ceil().clamp(y0 + 1, picture.height);
  final (width, height) = (x1 - x0, y1 - y0);
  final rgba = Uint8List(width * height * 4);
  for (var y = 0; y < height; y++) {
    final from = ((y0 + y) * picture.width + x0) * 4;
    rgba.setRange(y * width * 4, (y + 1) * width * 4, picture.rgba, from);
  }
  return (width: width, height: height, rgba: rgba);
}

(String, double) _recognise(OcrRun run, OcrScript script, OcrPicture line) {
  final width = ((line.width * _height + line.height - 1) ~/ line.height).clamp(
    8,
    _widest,
  );
  final input = _planes(
    _resize(line, width, _height),
    (_, v) => (v / 255 - 0.5) / 0.5,
  );
  return decodeCtc(
    run(script.file, [1, 3, _height, width], input),
    script.charset,
  );
}

/// Bilinear, pixel centres aligned as OpenCV does, on pictures taken as
/// opaque over white; the result is RGB, three bytes a pixel.
Uint8List _resize(OcrPicture p, int width, int height) {
  final out = Uint8List(width * height * 3);
  final (sx, sy) = (p.width / width, p.height / height);
  double at(int x, int y, int c) {
    final i = (y * p.width + x) * 4;
    final alpha = p.rgba[i + 3];
    return alpha == 255
        ? p.rgba[i + c].toDouble()
        : (p.rgba[i + c] * alpha + 255 * (255 - alpha)) / 255;
  }

  var o = 0;
  for (var y = 0; y < height; y++) {
    final fy = ((y + 0.5) * sy - 0.5).clamp(0.0, p.height - 1.0);
    final y0 = fy.floor();
    final wy = fy - y0;
    final y1 = min(y0 + 1, p.height - 1);
    for (var x = 0; x < width; x++) {
      final fx = ((x + 0.5) * sx - 0.5).clamp(0.0, p.width - 1.0);
      final x0 = fx.floor();
      final wx = fx - x0;
      final x1 = min(x0 + 1, p.width - 1);
      for (var c = 0; c < 3; c++) {
        final top = at(x0, y0, c) * (1 - wx) + at(x1, y0, c) * wx;
        final bottom = at(x0, y1, c) * (1 - wx) + at(x1, y1, c) * wx;
        out[o++] = (top * (1 - wy) + bottom * wy).round();
      }
    }
  }
  return out;
}

/// Channel-first floats in BGR order, as PaddleOCR's models were trained on
/// (OpenCV's), each value through [scale] with its channel's index in that
/// order. [rgb] is three bytes a pixel.
Float32List _planes(Uint8List rgb, double Function(int c, double v) scale) {
  final n = rgb.length ~/ 3;
  final out = Float32List(n * 3);
  for (var c = 0; c < 3; c++) {
    for (var i = 0; i < n; i++) {
      out[c * n + i] = scale(c, rgb[i * 3 + (2 - c)].toDouble());
    }
  }
  return out;
}
