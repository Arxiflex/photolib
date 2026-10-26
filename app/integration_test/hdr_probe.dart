import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';
import 'package:photolib/features/viewer/hdr_leaf.dart';
import 'package:photolib/ui/motion.dart';

/// The HDR spike's probe (ADR-0060). Each sample opens in an [HdrLeaf] inside
/// a minimal pager, which is pinched, panned and swiped away; the probe checks
/// that the gestures reach the pager and reports frames over budget and memory
/// as `HDR {json}` lines and in the driver's response file. The samples are
/// the files in `hdr-probe/` under the app's support directory (its external
/// files directory on Android), else a generated 12 MP still. Run it with
/// `flutter drive --profile` (docs/dev/flutter.md); it is not a `_test.dart`
/// file, so the smoke test leaves it out.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('HDR leaves cross-fade in and leave gestures to the pager', (
    tester,
  ) async {
    final policy = binding.framePolicy;
    binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
    addTearDown(() => binding.framePolicy = policy);
    final support = await hdrSupport();
    final results = [
      for (final file in await _samples())
        await _probe(tester, binding, file, support),
    ];
    binding.reportData = {'hdr': results};
    for (final result in results) {
      debugPrint('HDR ${jsonEncode(result)}');
      expect(result['zoom'] as double, greaterThan(2), reason: 'pinch');
      expect(result['page_after_pan'], 0, reason: 'a zoomed pan stays');
      expect(result['page_after_swipe'], 1, reason: 'swipe at 1×');
    }
  });
}

/// A janky frame builds or rasterises for longer than a 60 Hz vsync, as in
/// DevTools.
const _budget = Duration(microseconds: 16667);
const _videos = {'.mp4', '.mov', '.m4v', '.mkv', '.webm'};

Future<List<File>> _samples() async {
  // Android's external files directory is the one `adb push` reaches.
  final base = Platform.isAndroid
      ? await getExternalStorageDirectory()
      : await getApplicationSupportDirectory();
  final dir = Directory('${base!.path}/hdr-probe');
  final files = await dir.exists()
      ? await dir.list().where((e) => e is File).cast<File>().toList()
      : <File>[];
  if (files.isNotEmpty) return files..sort((a, b) => a.path.compareTo(b.path));
  const size = Size(4032, 3024);
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  for (var i = 0; i < 8; i++) {
    canvas.drawRect(
      Rect.fromLTWH(size.width * i / 8, 0, size.width / 8, size.height),
      Paint()..color = HSVColor.fromAHSV(1, i * 45.0, 0.8, 0.9).toColor(),
    );
  }
  final image = await recorder.endRecording().toImage(
    size.width.toInt(),
    size.height.toInt(),
  );
  final png = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  final file = File('${(await getTemporaryDirectory()).path}/hdr-probe.png');
  await file.writeAsBytes(png!.buffer.asUint8List());
  return [file];
}

Future<Map<String, Object?>> _probe(
  WidgetTester tester,
  IntegrationTestWidgetsFlutterBinding binding,
  File file,
  HdrSupport support,
) async {
  final transform = TransformationController();
  final pages = PageController();
  final frames = <ui.FrameTiming>[];
  final rssMb = <int>[];
  Future<Map<String, Object>> phase() async {
    await tester.pump(const Duration(seconds: 1)); // the engine batches them
    rssMb.add(ProcessInfo.currentRss >> 20);
    ms(Duration Function(ui.FrameTiming) of) =>
        frames.map((f) => of(f).inMicroseconds).fold(0, max) / 1000;
    final summary = {
      'frames': frames.length,
      'janky': frames
          .where((f) => f.buildDuration > _budget || f.rasterDuration > _budget)
          .length,
      'build_ms': ms((f) => f.buildDuration),
      'raster_ms': ms((f) => f.rasterDuration),
    };
    frames.clear();
    return summary;
  }

  rssMb.add(ProcessInfo.currentRss >> 20);
  binding.addTimingsCallback(frames.addAll);
  final clock = Stopwatch()..start();
  final video = _videos.any(file.path.toLowerCase().endsWith);
  var zoomed = false;
  // The viewer's hand-off in miniature: the pager scrolls only at 1×, so a
  // zoomed pan moves the image and a swipe at 1× moves to the next item.
  await tester.pumpWidget(
    MaterialApp(
      home: StatefulBuilder(
        builder: (context, setState) => PageView(
          controller: pages,
          physics: zoomed ? const NeverScrollableScrollPhysics() : null,
          children: [
            InteractiveViewer(
              transformationController: transform,
              maxScale: 8,
              onInteractionEnd: (_) => setState(
                () => zoomed = transform.value.getMaxScaleOnAxis() > 1.01,
              ),
              child: HdrLeaf(
                uri: file.uri,
                video: video,
                force: true,
                sdr: video
                    ? const ColoredBox(color: Colors.black)
                    : Image.file(
                        file,
                        cacheWidth:
                            (MediaQuery.sizeOf(context).width *
                                    MediaQuery.devicePixelRatioOf(context))
                                .round(),
                      ),
              ),
            ),
            const ColoredBox(color: Colors.black),
          ],
        ),
      ),
    ),
  );
  int? nativeMs;
  while (support != HdrSupport.none && clock.elapsed.inSeconds < 5) {
    await tester.pump(const Duration(milliseconds: 16));
    final fade = tester.widget<AnimatedOpacity>(
      find.descendant(
        of: find.byType(HdrLeaf),
        matching: find.byType(AnimatedOpacity),
      ),
    );
    if (fade.opacity == 0) {
      await tester.pump(Motion.short);
      nativeMs = clock.elapsedMilliseconds;
      break;
    }
  }
  final open = await phase();

  final center = tester.getCenter(find.byType(HdrLeaf));
  await _pinch(tester, center, from: 60, to: 180);
  final zoom = transform.value.getMaxScaleOnAxis();
  await tester.timedDrag(
    find.byType(HdrLeaf),
    const Offset(-150, 0),
    const Duration(milliseconds: 300),
  );
  await tester.pumpAndSettle();
  final panPx = transform.value.getTranslation().x;
  final pageAfterPan = pages.page!.round();
  await _pinch(tester, center, from: 180, to: 30);
  await tester.fling(find.byType(PageView), const Offset(-400, 0), 1500);
  await tester.pumpAndSettle();
  final gestures = await phase();
  final pageAfterSwipe = pages.page!.round();

  await tester.pumpWidget(const SizedBox());
  await phase();
  binding.removeTimingsCallback(frames.addAll);
  return {
    'platform': defaultTargetPlatform.name,
    'os': Platform.operatingSystemVersion,
    'mode': kProfileMode ? 'profile' : (kDebugMode ? 'debug' : 'release'),
    'support': support.name,
    'sample': file.uri.pathSegments.last,
    'sample_kb': (await file.length()) >> 10,
    'native_ms': nativeMs,
    'open': open,
    'gestures': gestures,
    'zoom': zoom,
    'pan_px': panPx,
    'page_after_pan': pageAfterPan,
    'page_after_swipe': pageAfterSwipe,
    'rss_mb': rssMb,
  };
}

/// A vertical two-finger pinch around [center], so the pager's horizontal drag
/// never claims it.
Future<void> _pinch(
  WidgetTester tester,
  Offset center, {
  required double from,
  required double to,
}) async {
  final a = await tester.startGesture(center - Offset(0, from));
  final b = await tester.startGesture(center + Offset(0, from));
  for (var i = 1; i <= 20; i++) {
    final span = from + (to - from) * i / 20;
    await a.moveTo(center - Offset(0, span));
    await b.moveTo(center + Offset(0, span));
    await tester.pump(const Duration(milliseconds: 16));
  }
  await a.up();
  await b.up();
  await tester.pumpAndSettle();
}
