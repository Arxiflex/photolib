// PP-OCRv5 in Dart (M5-08, ADR-0388): the charsets are the server's, the
// pipeline reads as the server's does. The pure parts run in every `flutter
// test`; reading the pictures of testdata/ocr/ with the real models (about
// 190 MB from tools/ml/fetch.py) runs with PHOTOLIB_ML_MODELS=all or a list
// that names `ppocr`.
@TestOn('vm')
@Timeout(Duration(minutes: 30))
library;

import 'dart:convert';
import 'dart:ffi' show Abi;
import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:photolib_ml/ocr.dart';
import 'package:photolib_ml/photolib_ml.dart';
import 'package:photolib_ml/src/ocr.dart';
import 'package:photolib_ml/src/ocr_charsets.g.dart';
import 'package:test/test.dart';

import '../tool/ocr_charsets.dart' as tool;

String dictionary(String name) =>
    File('../../../server/crates/photolib-ml/data/ocr/$name.txt')
        .readAsStringSync();

/// Probabilities with one hot class per step.
Float32List steps(int classes, List<int> hot) {
  final out = Float32List(classes * hot.length);
  for (final (i, h) in hot.indexed) {
    out[i * classes + h] = 0.9;
  }
  return out;
}

OcrPicture white(int width, int height) => (
  width: width,
  height: height,
  rgba: Uint8List(width * height * 4)..fillRange(0, width * height * 4, 255),
);

void main() {
  test('the charsets are those of the server, and as long as the models '
      'answer', () {
    expect(
      tool.generate(dictionary),
      File('lib/src/ocr_charsets.g.dart').readAsStringSync().trimRight(),
      reason: 'run dart run tool/ocr_charsets.dart',
    );
    expect(
      [for (final s in OcrScript.values) s.charset.length + 1],
      [504, 519, 18385],
    );
    expect(latinDictionary, isNotEmpty);
  });

  test('CTC decoding reads Latin, Cyrillic and CJK, collapsing repeats but '
      'not across a blank', () {
    for (final (charset, text) in [
      (['a', 'b', 'c'], 'abc'),
      (['п', 'р', 'и', 'в', 'е', 'т'], 'привет'),
      (['東', '京', '駅'], '東京駅'),
    ]) {
      final hot = [
        for (final c in text.split('')) ...[charset.indexOf(c) + 1, 0],
      ];
      expect(decodeCtc(steps(charset.length + 1, hot), charset).$1, text);
    }
    expect(decodeCtc(steps(3, [1, 1, 0, 1, 2, 2]), ['a', 'b']).$1, 'aab');
    expect(decodeCtc(Float32List(0), ['a']), ('', 0.0));
    expect(decodeCtc(steps(3, [0, 0]), ['a', 'b']), ('', 0.0));
  });

  test('text is cleaned of controls and overrides, and markup is kept as '
      'text', () {
    const xss = '<img src=x onerror=alert(1)>"\'<script>alert(1)</script>';
    expect(cleanOcrText(xss), xss);
    expect(
      cleanOcrText(
        '  a\u0000b\u0007c${String.fromCharCode(0x202e)}d'
        '${String.fromCharCode(0x2066)}e\n f\tg \r\n',
      ),
      'abcde\n f\tg',
    );
    expect(cleanOcrText('東京 привет'), '東京 привет');
    expect(cleanOcrText('é' * (maxOcrChars + 5)).runes.length, maxOcrChars);
  });

  /// A detector that sees [rects] (x0, y0, x1, y1 on its map) and
  /// recognisers that each read the one character at `class` of their charset
  /// as sure as `surety`; [seen] collects the files run.
  OcrRun fake(
    List<(int, int, int, int)> rects,
    Map<OcrScript, (int, double)> says,
    List<String> seen,
  ) => (file, shape, data) {
    seen.add(file);
    if (file == ocrDetector) {
      final (h, w) = (shape[2], shape[3]);
      final map = Float32List(h * w);
      for (final (x0, y0, x1, y1) in rects) {
        for (var y = y0; y < y1; y++) {
          map.fillRange(y * w + x0, y * w + x1, 0.9);
        }
      }
      return map;
    }
    final script = OcrScript.values.firstWhere((s) => s.file == file);
    final (cls, surety) = says[script]!;
    final classes = script.charset.length + 1;
    return Float32List(classes * 2)..[cls] = surety;
  };

  test('a line is read by the recogniser surest of itself, once each', () {
    final seen = <String>[];
    final text = readText(
      fake(
        [(4, 8, 28, 16)],
        {
          OcrScript.latin: (1, 0.5),
          OcrScript.eslav: (2, 0.9),
          OcrScript.chinese: (3, 0.7),
        },
        seen,
      ),
      white(32, 32),
    );
    expect(text, OcrScript.eslav.charset[1]);
    expect(seen.length, 4);
  });

  test('a picture without text, a speck and a malformed picture are '
      'handled', () {
    final says = {for (final s in OcrScript.values) s: (1, 0.5)};
    final seen = <String>[];
    expect(readText(fake([], says, seen), white(64, 64)), '');
    expect(seen, [ocrDetector], reason: 'no recogniser runs without a line');
    expect(readText(fake([(4, 4, 6, 20)], says, []), white(32, 32)), '');
    expect(
      () => readText(fake([], says, []), (
        width: 2,
        height: 2,
        rgba: Uint8List(5),
      )),
      throwsArgumentError,
    );
    expect(
      () => readText(fake([], says, []), white(0, 0)),
      throwsArgumentError,
    );
  });

  final models = Platform.environment['PHOTOLIB_ML_MODELS'];
  group(
    'with the real models',
    skip: models == null || !(models == 'all' || models.contains('ppocr'))
        ? 'set PHOTOLIB_ML_MODELS=all or ppocr-v5-det,... to fetch about 190 MB'
        : null,
    () {
      final runtime = {
        Abi.linuxX64: 'ort-linux-x64',
        Abi.linuxArm64: 'ort-linux-arm64',
        Abi.macosArm64: 'ort-macos-arm64',
        Abi.windowsX64: 'ort-windows-x64',
      }[Abi.current()]!;
      const names = [
        'ppocr-v5-det',
        'ppocr-v5-rec-latin',
        'ppocr-v5-rec-eslav',
        'ppocr-v5-rec-chinese',
      ];
      late final Map<String, String> files;
      late final Ort ort;
      final sessions = <String, Session>{};
      setUpAll(() {
        final result = Process.runSync('python3', [
          '../../../tools/ml/fetch.py',
          runtime,
          ...names,
        ]);
        if (result.exitCode != 0) throw StateError('${result.stderr}');
        files = (jsonDecode(result.stdout as String) as Map).map(
          (name, files) =>
              MapEntry(name as String, (files as List).first as String),
        );
        ort = Ort.open(files[runtime]!);
      });
      tearDownAll(() {
        for (final session in sessions.values) {
          session.close();
        }
      });

      Float32List run(String file, List<int> shape, Float32List data) {
        final name = file.split('@').first;
        final session = sessions[name] ??= Session(ort, files[name]!);
        final input = Tensor.float32(shape)..values.setAll(0, data);
        try {
          return session.run({'x': input}, ['fetch_name_0']).single;
        } finally {
          input.free();
        }
      }

      OcrPicture fixture(String name) {
        final image = img.decodePng(
          File('../../../testdata/ocr/$name.png').readAsBytesSync(),
        )!;
        return (
          width: image.width,
          height: image.height,
          rgba: image.convert(numChannels: 4).toUint8List(),
        );
      }

      test('a reader on an isolate of its own reads the same, one picture at a '
          'time or many, and fails once closed', () async {
        final reader = await OcrReader.start(files[runtime], {
          for (final name in ocrModels) name: files[name]!,
        });
        final latin = await reader.read(fixture('latin'));
        expect(latin.split(RegExp(r'\s+')).join(), 'LisboaEstação2026');
        final both = await Future.wait([
          reader.read(fixture('cyrillic')),
          reader.read(fixture('cjk')),
        ]);
        expect(both.map((t) => t.split(RegExp(r'\s+')).join()), [
          'Красная площадь,Москва'.replaceAll(' ', ''),
          '東京駅丸の内',
        ]);
        await reader.close();
        expect(reader.read(fixture('latin')), throwsA(isA<OrtException>()));
        expect(
          OcrReader.start('/nonexistent/libonnxruntime.so', {}),
          throwsA(isA<OrtException>()),
        );
      });

      String squeezed(String text) => text.split(RegExp(r'\s+')).join();

      test(
        'the pictures of every script and a payload are read as they say',
        () {
          final expected = jsonDecode(
            File('../../../testdata/ocr/expected.json').readAsStringSync(),
          ) as Map;
          for (final MapEntry(key: name, value: says) in expected.entries) {
            final text = readText(run, fixture(name as String));
            expect(squeezed(text), squeezed(says as String), reason: name);
          }
        },
      );
    },
  );
}
