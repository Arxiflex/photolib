import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:photolib/features/library/timeline/pipeline.dart';
import 'package:photolib/features/library/timeline/providers.dart';
import 'package:photolib/features/library/timeline/thumbnails.dart';
import 'package:photolib/features/viewer/animated.dart';
import 'package:photolib/features/viewer/deep_zoom.dart';
import 'package:photolib/features/viewer/regions.dart';
import 'package:photolib_data/photolib_data.dart';

import '../../support/pump_app.dart';

final String _corpus = Directory('../testdata/corpus').absolute.path;

/// The corpus' animations, its files of quirk `animated`.
final List<String> _animated = [
  for (final f in Directory(
    '$_corpus/golden',
  ).listSync(recursive: true).whereType<File>())
    if (jsonDecode(f.readAsStringSync())
        case {'path': final String path, 'quirks': final List<Object?> quirks}
        when quirks.contains('animated'))
      path,
]..sort();

void main() {
  late Replica db;
  setUp(() => db = Replica(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<int> pixels(WidgetTester tester, ui.Image image) async =>
      Object.hashAll(
        (await tester.runAsync(image.toByteData))!.buffer.asUint8List(),
      );

  test("Flutter's codecs give the corpus' GIF, WebP and APNG animations the "
      'frame durations and loops their files declare', () async {
    expect(_animated.map((p) => p.split('.').last), ['apng', 'gif', 'webp']);
    for (final path in _animated) {
      final bytes = File('$_corpus/files/$path').readAsBytesSync();
      final codec = await ui.instantiateImageCodec(bytes);
      expect(codec.repetitionCount, -1, reason: path);
      expect(
        [
          for (var i = 0; i < codec.frameCount; i++)
            (await codec.getNextFrame()).duration.inMilliseconds,
        ],
        _declared(bytes),
        reason: path,
      );
    }
  });

  test('MediaStore and PhotoKit items, read through the viewer channel, '
      'animate as files do; stills and videos do not', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final asked = <List<Object?>>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('org.photolib/viewer'), (
          call,
        ) async {
          final [uri as String, ...limit] = call.arguments as List<Object?>;
          asked.add([call.method, uri, ...limit]);
          final bytes = File(
            '$_corpus/files/${Uri.parse(uri).queryParameters['f']}',
          ).readAsBytesSync();
          return switch (limit) {
            [final int n] when n < bytes.length => bytes.sublist(0, n),
            _ => bytes,
          };
        });
    Future<int?> frames(String scheme, String path, {bool video = false}) =>
        animationOf(
          ThumbnailItem(
            path,
            Uri.parse('$scheme://x?f=${Uri.encodeQueryComponent(path)}'),
            video: video,
            animated: true,
          ),
        ).then((codec) => codec?.frameCount);
    for (final scheme in ['content', 'ph']) {
      for (final path in _animated) {
        expect(await frames(scheme, path), greaterThan(1), reason: path);
      }
      expect(await frames(scheme, 'stills/baseline.jpg'), isNull);
    }
    expect(await frames('content', _animated.first, video: true), isNull);
    expect(asked.first.last, 64 << 10, reason: 'only the head first');
  });

  group('an animation', () {
    late _Codec codec;
    late List<int> shown;
    late List<Duration> at;
    var now = Duration.zero;

    /// Plays [codec] for [length] at 60 Hz, then stops.
    Future<void> play(WidgetTester tester, Duration length) async {
      (shown, at, now) = ([], [], Duration.zero);
      final frames = Frames(codec, const TestVSync(), (image) {
        shown.add(codec.index[image]!);
        at.add(now);
      });
      const vsync = Duration(microseconds: 16667);
      while (now < length) {
        now += vsync;
        await tester.pump(vsync);
      }
      frames.dispose();
    }

    testWidgets('shows each frame for its own duration from the first, '
        'however late vsyncs and decodes come, loop after loop', (
      tester,
    ) async {
      codec = _Codec([40, 70, 130], decode: 25);
      await play(tester, const Duration(milliseconds: 9600));
      expect(shown.length, inInclusiveRange(119, 121));
      var due = at.first;
      for (final (k, frame) in shown.indexed) {
        expect(frame, k % 3);
        expect(
          (at[k] - due).inMicroseconds,
          inInclusiveRange(0, 16667),
          reason: 'frame $k',
        );
        due += Duration(milliseconds: codec.durations[frame]);
      }
    });

    testWidgets('a frame that comes late starts the count again from it', (
      tester,
    ) async {
      codec = _Codec([100, 100], slow: {1: 500});
      await play(tester, const Duration(milliseconds: 1000));
      expect(shown.take(4), [0, 1, 0, 1]);
      expect(at[1] - at[0], greaterThan(const Duration(milliseconds: 500)));
      expect(
        (at[2] - at[1]).inMilliseconds,
        inInclusiveRange(100, 117),
        reason: 'the next frame rushes nowhere',
      );
    });

    testWidgets('plays as many times as its file says, then rests on its '
        'last frame', (tester) async {
      codec = _Codec([100, 100, 100], repetitions: 1);
      await play(tester, const Duration(seconds: 1));
      expect(shown, [0, 1, 2, 0, 1, 2]);
      expect(SchedulerBinding.instance.transientCallbackCount, 0);
    });

    testWidgets('a frame of 10 ms or less shows for 100 ms, as browsers show '
        'it', (tester) async {
      codec = _Codec([0, 10]);
      await play(tester, const Duration(milliseconds: 1000));
      expect(shown.length, inInclusiveRange(9, 11));
    });
  });

  test('a MediaStore or PhotoKit item animates when it is animated, its '
      'bytes read through the viewer channel', () async {
    final asked = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('org.photolib/viewer'), (
          call,
        ) async {
          final [uri as String, ...] = call.arguments as List<Object?>;
          asked.add('${call.method} $uri');
          return File(
            '$_corpus/files/stills/${uri.endsWith('still') ? 'static' : 'animated'}.gif',
          ).readAsBytesSync();
        });
    Future<int?> frames(String uri, {bool animated = true}) async =>
        (await animationOf(
          ThumbnailItem('k', Uri.parse(uri), animated: animated),
        ))?.frameCount;
    expect(await frames('content://media/external/images/media/5'), 3);
    expect(await frames('ph:AB-12/L0/001'), 3);
    expect(
      await frames('content://media/external/images/media/6', animated: false),
      isNull,
    );
    expect(await frames('ph:still'), isNull);
    expect(asked, [
      'read content://media/external/images/media/5',
      'read ph:AB-12/L0/001',
      'read ph:still',
    ]);
  });

  for (final (n, name) in _animated.indexed) {
    testWidgets('the viewer plays $name frame after frame', (tester) async {
      final frames = <int>{};
      final bytes = (await tester.runAsync(
        File('$_corpus/files/$name').readAsBytes,
      ))!;
      final codec = (await tester.runAsync(
        () => ui.instantiateImageCodec(bytes),
      ))!;
      for (var i = 0; i < codec.frameCount; i++) {
        final frame = (await tester.runAsync(codec.getNextFrame))!;
        frames.add(await pixels(tester, frame.image));
      }
      expect(frames.length, greaterThan(1));
      for (final (i, file) in _animated.indexed) {
        await db
            .into(db.localAsset)
            .insert(
              LocalAssetCompanion.insert(
                id: Uint8List(16)..[15] = i + 1,
                source: 'folder',
                volume: Value('$_corpus/files'),
                sourceId: file,
                path: Value(file),
                name: Value(file.split('/').last),
                size: 5000,
                mtime: 0,
                takenLocal: Value('2024-05-03T1$i:00:00'),
                extracted: const Value(1),
              ),
            );
      }
      await pumpApp(
        tester,
        replica: (_) => db,
        overrides: [
          thumbnailPipelineProvider.overrideWith((ref) async => _Grey()),
          regionsProvider.overrideWithValue((_) async => null),
        ],
      );
      final semantics = tester.ensureSemantics();
      await tester.pump();
      // Newest first.
      final count = _animated.length;
      tester.semantics.tap(
        find.semantics.byLabel(RegExp(', ${count - n} of $count\$')),
      );
      semantics.dispose();
      final shown = <int>{};
      // Reading and decoding the file take real time.
      await tester.pumpUntil(step: const Duration(milliseconds: 40), () async {
        final zoom = find.byType(DeepZoom).hitTestable();
        if (zoom.evaluate().isNotEmpty) {
          if (tester.widget<DeepZoom>(zoom).base case final base?) {
            shown.add(await pixels(tester, base));
          }
        }
        return shown.containsAll(frames);
      });
      await tester.pumpWidget(const SizedBox());
      await tester.pump(Duration.zero);
    });
  }
}

/// Grey thumbnails.
class _Grey extends ThumbnailPipeline {
  @override
  Future<ui.Image> load(ThumbnailItem item, int tier, Tile tile) async {
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawColor(const Color(0xff808080), BlendMode.src);
    return recorder.endRecording().toImageSync(40, 30);
  }
}

/// A codec of frames of these [durations] in ms, each a distinct image whose
/// index is in [index], played [repetitions] times more (-1: for ever), each
/// decoding in [decode] ms, the nth in [slow]`[n]` ms.
class _Codec implements ui.Codec {
  new(
    this.durations, {
    this.repetitions = -1,
    this.decode = 0,
    this.slow = const {},
  });

  final List<int> durations;
  final int repetitions;
  final int decode;
  final Map<int, int> slow;
  final index = <ui.Image, int>{};
  var _decoded = 0;

  @override
  int get frameCount => durations.length;

  @override
  int get repetitionCount => repetitions;

  @override
  Future<ui.FrameInfo> getNextFrame() async {
    final n = _decoded++;
    await Future<void>.delayed(Duration(milliseconds: slow[n] ?? decode));
    final i = n % frameCount;
    final recorder = ui.PictureRecorder();
    Canvas(recorder);
    final image = recorder.endRecording().toImageSync(1, 1);
    index[image] = i;
    return _Frame(Duration(milliseconds: durations[i]), image);
  }

  @override
  void dispose() {}
}

class _Frame implements ui.FrameInfo {
  new(this.duration, this.image);

  @override
  final Duration duration;

  @override
  final ui.Image image;
}

/// The frame durations in ms that a GIF (its graphic control extensions),
/// WebP (ANMF chunks) or APNG (fcTL chunks) declares.
List<int> _declared(Uint8List bytes) {
  final data = ByteData.sublistView(bytes);
  final out = <int>[];
  if (latin1.decode(bytes.sublist(0, 3)) == 'GIF') {
    var at = 13 + (bytes[10] & 0x80 != 0 ? 3 << (bytes[10] & 7) + 1 : 0);
    void blocks() {
      while (bytes[at] != 0) {
        at += bytes[at] + 1;
      }
      at++;
    }

    while (bytes[at] != 0x3b) {
      if (bytes[at] == 0x21) {
        if (bytes[at + 1] == 0xf9) {
          out.add(data.getUint16(at + 4, Endian.little) * 10);
        }
        at += 2;
      } else {
        final local = bytes[at + 9];
        at += 11 + (local & 0x80 != 0 ? 3 << (local & 7) + 1 : 0);
      }
      blocks();
    }
    return out;
  }
  final webp = latin1.decode(bytes.sublist(0, 4)) == 'RIFF';
  for (var at = webp ? 12 : 8; at + 8 <= bytes.length;) {
    final kind = latin1.decode(
      bytes.sublist(at + 4 * (webp ? 0 : 1), at + 4 * (webp ? 1 : 2)),
    );
    final length = webp
        ? data.getUint32(at + 4, Endian.little)
        : data.getUint32(at);
    final body = at + 8;
    if (kind == 'ANMF') {
      out.add(data.getUint32(body + 12, Endian.little) & 0xffffff);
    }
    if (kind == 'fcTL') {
      final den = data.getUint16(body + 22);
      out.add(data.getUint16(body + 20) * 1000 ~/ (den == 0 ? 100 : den));
    }
    at = webp ? body + length + length % 2 : body + length + 4;
  }
  return out;
}
