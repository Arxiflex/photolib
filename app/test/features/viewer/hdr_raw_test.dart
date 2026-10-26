import 'dart:ui' as ui;

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:photolib/features/library/timeline/pipeline.dart';
import 'package:photolib/features/library/timeline/providers.dart';
import 'package:photolib/features/library/timeline/thumbnails.dart';
import 'package:photolib/features/viewer/deep_zoom.dart';
import 'package:photolib/features/viewer/hdr_leaf.dart';
import 'package:photolib/features/viewer/regions.dart';
import 'package:photolib/features/viewer/viewer_page.dart';
import 'package:photolib/ui/motion.dart';
import 'package:photolib_data/photolib_data.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import '../../support/fake_players.dart';
import '../../support/pump_app.dart';
import '../hdr_leaf_test.dart' show Call, creates, creationParams, fakeNative;

const ios = TargetPlatformVariant({TargetPlatform.iOS});

void main() {
  late Replica db;
  late FakePlayers players;
  final cores = Thumbnails.processors;
  setUp(() {
    db = Replica(NativeDatabase.memory());
    VideoPlayerPlatform.instance = players = FakePlayers();
    // The library's thumbnails decode cores - 1 at once: a RAW's decode of two
    // seconds must not hold the only slot of a two-core machine, so the tests
    // run on one of five.
    Thumbnails.processors = () => 5;
  });
  tearDown(() {
    Thumbnails.processors = cores;
    return db.close();
  });

  /// The library of [files], newest first, as `name` or `name:hdr`, the
  /// [spheres] among them equirectangular, its images from [pipeline], opened
  /// on the first.
  Future<void> open(
    WidgetTester tester,
    List<String> files, {
    Set<String> spheres = const {},
    ThumbnailPipeline? pipeline,
  }) async {
    for (final (i, file) in files.indexed) {
      final [name, ...facets] = file.split(':');
      await db
          .into(db.localAsset)
          .insert(
            LocalAssetCompanion.insert(
              id: Uint8List(16)..[15] = i + 1,
              source: 'folder',
              volume: const Value('/p'),
              sourceId: '${i + 1}',
              path: Value(name),
              name: Value(name),
              size: 2512000,
              mtime: 0,
              takenLocal: Value('2024-05-03T1${5 - i}:00:00'),
              takenUtc: Value(
                DateTime.utc(2024, 5, 3, 15 - i).millisecondsSinceEpoch,
              ),
              extracted: const Value(1),
              facets: Value(facets.join(',')),
              projection: Value(
                spheres.contains(name) ? 'equirectangular' : null,
              ),
            ),
          );
    }
    await pumpApp(
      tester,
      replica: (_) => db,
      size: const Size(800, 600),
      overrides: [
        thumbnailPipelineProvider.overrideWith(
          (ref) async => pipeline ?? _Grey(),
        ),
        regionsProvider.overrideWithValue((_) async => null),
      ],
    );
    final semantics = tester.ensureSemantics();
    tester.semantics.tap(
      find.semantics.byLabel('May 3, 2024, 1 of ${files.length}'),
    );
    await tester.pump();
    semantics.dispose();
  }

  // Past the dwell, and the frame that builds the view.
  Future<void> dwell(WidgetTester tester) async {
    await tester.pump(HdrLeaf.prewarm);
    await tester.pump();
  }

  Future<void> next(WidgetTester tester) async {
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    await tester.pump(Motion.medium);
    await dwell(tester);
  }

  Iterable<String?> uris(List<Call> calls) => [
    for (final create in creates(calls))
      creationParams(create)['uri'] as String?,
  ];

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
  }

  testWidgets('an HDR photo shows in its native leaf once the viewer has '
      'grown to the screen and the dwell has passed, never its neighbours; '
      'a page turn drops it', (tester) async {
    final calls = fakeNative(tester, support: 'hdr');
    await open(tester, ['1.jpg:hdr', '2.jpg:hdr', '3.jpg']);
    // No platform view during the flight from the grid.
    while (find.byType(ViewerPage).evaluate().isEmpty ||
        !ModalRoute.of(tester.element(find.byType(ViewerPage)))!
            .animation!
            .isCompleted) {
      expect(creates(calls), isEmpty);
      await tester.pump(const Duration(milliseconds: 16));
    }
    await tester.pump(HdrLeaf.prewarm - const Duration(milliseconds: 10));
    expect(creates(calls), isEmpty);
    await tester.pump(const Duration(milliseconds: 10));
    await tester.pump();
    expect(uris(calls), ['file:///p/1.jpg']);

    await next(tester);
    expect(uris(calls), ['file:///p/1.jpg', 'file:///p/2.jpg']);
    expect(calls.where((c) => c.call.method == 'dispose'), hasLength(1));
    await next(tester);
    expect(uris(calls), hasLength(2), reason: '3.jpg is SDR');
    expect(calls.where((c) => c.call.method == 'dispose'), hasLength(2));
    await unmount(tester);
  }, variant: ios);

  testWidgets('the HDR toggle shows HDR items in SDR, the next ones too, '
      'until turned back', (tester) async {
    final calls = fakeNative(tester, support: 'hdr');
    await open(tester, ['1.jpg:hdr', '2.jpg:hdr']);
    await tester.pump(Motion.medium * 2);
    await dwell(tester);
    expect(uris(calls), ['file:///p/1.jpg']);

    await tester.tap(find.byTooltip('Show in SDR'));
    await tester.pump();
    await dwell(tester);
    expect(calls.last.call.method, 'dispose');
    await next(tester);
    expect(uris(calls), hasLength(1));
    await tester.tap(find.byTooltip('Show in HDR'));
    await tester.pump();
    await dwell(tester);
    expect(uris(calls), ['file:///p/1.jpg', 'file:///p/2.jpg']);
    await unmount(tester);
  }, variant: ios);

  testWidgets('without native HDR leaves, HDR items show in SDR, with no '
      'toggle', (tester) async {
    final calls = fakeNative(tester, support: 'hdr');
    await open(tester, ['1.jpg:hdr']);
    await tester.pump(Motion.medium * 2);
    await dwell(tester);
    expect(creates(calls), isEmpty);
    expect(find.byTooltip('Show in SDR'), findsNothing);
    await unmount(tester);
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  testWidgets('a RAW shows its largest embedded preview at once, until a '
      'larger decode of it comes', (tester) async {
    await open(tester, ['1.nef', '2.nef'], pipeline: _Raw());
    List<Size?> shown() => [
      for (final e in find.byType(DeepZoom, skipOffstage: false).evaluate())
        switch ((e.widget as DeepZoom).base) {
          final image? => Size(image.width * 1.0, image.height * 1.0),
          null => null,
        },
    ];
    for (var i = 0; i < 60 && shown().nonNulls.length < 2; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(shown(), [const Size(400, 300), const Size(400, 300)]);
    await tester.pump(const Duration(seconds: 3));
    expect(shown(), [const Size(400, 300), const Size(800, 600)]);
    await unmount(tester);
  });

  testWidgets('an HDR video plays in a platform view where the screen has '
      'headroom and HDR is on, SDR ones and the rest in a texture', (
    tester,
  ) async {
    for (final support in ['hdr', 'sdr']) {
      fakeNative(tester, support: support);
      VideoPlayerPlatform.instance = players = FakePlayers();
      await db.delete(db.localAsset).go();
      await open(tester, ['1.mp4:hdr', '2.mp4']);
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(players.viewTypes, [
        if (support == 'hdr')
          VideoViewType.platformView
        else
          VideoViewType.textureView,
        VideoViewType.textureView,
      ], reason: support);
      if (support == 'hdr') {
        await tester.tap(find.byTooltip('Show in SDR'));
        for (var i = 0; i < 10; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(players.viewTypes.last, VideoViewType.textureView);
        expect(players.calls, contains('dispose 0'));
      }
      await unmount(tester);
    }
  }, variant: ios);

  testWidgets('an HDR 360° video is projected from a texture, with no HDR '
      'toggle', (tester) async {
    fakeNative(tester, support: 'hdr');
    await open(tester, ['1.mp4:hdr'], spheres: {'1.mp4'});
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(players.viewTypes, [VideoViewType.textureView]);
    expect(find.byTooltip('Show in SDR'), findsNothing);
    await unmount(tester);
  }, variant: ios);
}

ui.Image _grey(int width, int height) {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawColor(const Color(0xff808080), BlendMode.src);
  return recorder.endRecording().toImageSync(width, height);
}

class _Grey extends ThumbnailPipeline {
  @override
  Future<ui.Image> load(ThumbnailItem item, int tier, Tile tile) async =>
      _grey(40, 30);
}

/// RAWs whose embedded previews are 400 × 300 and whose decodes take two
/// seconds: 1.nef's to 40 × 30, smaller, and 2.nef's to 800 × 600, as a
/// platform's RAW decoder does.
class _Raw extends ThumbnailPipeline {
  @override
  Future<ui.Image> load(ThumbnailItem item, int tier, Tile tile) =>
      Future.delayed(
        const Duration(seconds: 2),
        () => '$item'.endsWith('2.nef') ? _grey(800, 600) : _grey(40, 30),
      );

  @override
  Future<ui.Image?> preview(ThumbnailItem item, int tier) async =>
      _grey(400, 300);
}
