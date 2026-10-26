import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/gestures.dart'
    show PointerDeviceKind, PointerScrollEvent;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:photolib/features/desktop/file_drag.dart';
import 'package:photolib/features/library/timeline/providers.dart';
import 'package:photolib/features/viewer/attitude.dart';
import 'package:photolib/features/viewer/deep_zoom.dart';
import 'package:photolib/features/viewer/info_panel.dart';
import 'package:photolib/features/viewer/regions.dart';
import 'package:photolib/features/viewer/sphere.dart';
import 'package:photolib/features/viewer/sphere_frame.dart';
import 'package:photolib/features/viewer/video.dart';
import 'package:photolib/features/viewer/viewer_page.dart';
import 'package:photolib/ui/commands.dart';
import 'package:photolib_data/photolib_data.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:video_player/video_player.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import '../../support/fake_players.dart';
import '../../support/pump_app.dart';
import '../../support/viewer.dart' show Grey;

/// Pumps for a second: a playing 360° video's frames never settle.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Presses [key], typing [c], then pumps a frame.
Future<void> press(WidgetTester t, LogicalKeyboardKey key, String c) =>
    t.pressKey(key, character: c).then((_) => t.pump());

/// Taps the button whose tooltip is [tip], then pumps a frame.
Future<void> tapTip(WidgetTester t, String tip) =>
    t.tap(find.byTooltip(tip)).then((_) => t.pump());

void main() {
  late Replica db;
  late FakePlayers players;
  setUp(() {
    db = Replica(NativeDatabase.memory());
    VideoPlayerPlatform.instance = players = FakePlayers();
  });
  tearDown(() => db.close());

  /// Two items on May 3, [first] (`1.<ext>`) of [projection], [crop] and
  /// [facets], and a flat photo, both [width] × 2000.
  Future<void> pump(
    WidgetTester tester,
    String first, {
    String second = '2.jpg',
    String? projection = 'equirectangular',
    String? crop,
    String? facets,
    String? stereo,
    int width = 4000,
    Size size = const Size(800, 600),
    MotionSensors? sensors,
    Future<bool> Function()? permission,
    Duration? rows,
    Regions? regions,
    bool landed = true,
  }) async {
    for (final (i, name) in [first, second].indexed) {
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
              mime: Value(name.endsWith('.mp4') ? 'video/mp4' : 'image/jpeg'),
              size: 2512000,
              mtime: 0,
              takenLocal: Value('2024-05-03T1${2 - i}:00:00'),
              takenUtc: Value(
                DateTime.utc(2024, 5, 3, 12 - i).millisecondsSinceEpoch,
              ),
              width: Value(width),
              height: const Value(2000),
              extracted: const Value(1),
              projection: Value(i == 0 ? projection : null),
              crop: Value(i == 0 ? crop : null),
              facets: Value(i == 0 ? facets : null),
              stereo: Value(i == 0 ? stereo : null),
            ),
          );
    }
    await pumpApp(
      tester,
      replica: (_) => db,
      size: size,
      overrides: [
        thumbnailPipelineProvider.overrideWith(
          (ref) async => Grey(width: width ~/ 50, height: 40),
        ),
        regionsProvider.overrideWithValue((_) async => regions),
        sensorsProvider.overrideWithValue(
          sensors == null ? null : () => sensors,
        ),
        if (permission != null)
          motionPermissionProvider.overrideWithValue(permission),
        if (rows != null)
          assetRowProvider.overrideWith(
            (ref, item) => Stream.fromFuture(
              Future<void>.delayed(rows).then(
                (_) => (db.select(
                  db.localAsset,
                )..where((a) => a.id.equals(item.id!))).getSingleOrNull(),
              ),
            ),
          ),
      ],
    );
    final semantics = tester.ensureSemantics();
    await tester.pump();
    tester.semantics.tap(find.semantics.byLabel(RegExp(r'1 of 2$')));
    semantics.dispose();
    if (landed) await settle(tester);
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
  }

  // A message shown over the viewer, not under it.
  Finder said(String text) =>
      find.descendant(of: find.byType(ViewerPage), matching: find.text(text));

  SphereView view(WidgetTester tester) =>
      tester.widget<SphereFrame>(find.byType(SphereFrame)).view.value;

  // The position of the item shown, which a page turn changes.
  int title(WidgetTester tester) =>
      tester.widget<ViewerPage>(find.byType(ViewerPage)).position.value;

  testWidgets('a photo sphere opens projected and rotatable: drags turn it '
      'and the pager is locked, pinches, the wheel and the keys narrow or '
      'widen its lens, and a little planet shows it all, until left for where '
      'it was; the keys page past it', (tester) async {
    await pump(tester, '1.jpg');
    expect(find.byType(SpherePhoto), findsOneWidget);
    expect(find.byTooltip('Move to look around'), findsNothing);
    final shown = title(tester);
    expect(find.bySemanticsLabel(RegExp(r'^360° view\. ')), findsOneWidget);
    final centre = tester.getCenter(find.byType(SphereFrame));
    final finger = await tester.startGesture(centre);
    await finger.moveBy(const Offset(-40, 0));
    await tester.pump();
    final from = view(tester);
    await finger.moveBy(const Offset(-200, 100));
    await tester.pump();
    await finger.up();
    await tester.pumpAndSettle();
    expect(title(tester), shown, reason: 'the pager stays');
    // The lens' 75° over the short side: 200 px across 600 turn 25° east.
    final short = tester.getSize(find.byType(SphereFrame)).shortestSide;
    final to = view(tester);
    expect((to.yaw - from.yaw) * 180 / pi, closeTo(75 * 200 / short, 0.01));
    expect((to.pitch - from.pitch) * 180 / pi, closeTo(75 * 100 / short, 0.01));

    // Fingers 150 px apart, then 200: the lens narrows to three quarters.
    final a = await tester.startGesture(centre - const Offset(50, 0));
    final b = await tester.startGesture(centre + const Offset(50, 0));
    await a.moveBy(const Offset(-25, 0));
    await b.moveBy(const Offset(25, 0));
    await tester.pump();
    final apart = view(tester).fov;
    await a.moveBy(const Offset(-25, 0));
    await b.moveBy(const Offset(25, 0));
    await tester.pump();
    await a.up();
    await b.up();
    await tester.pumpAndSettle();
    expect(view(tester).fov / apart, closeTo(0.75, 0.001));

    // The wheel widens it to twice, the + key narrows it by 1.5.
    final pinched = view(tester).fov;
    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: centre,
        scrollDelta: const Offset(0, 400 * ln2),
      ),
    );
    await tester.pump();
    expect(view(tester).fov / pinched, closeTo(2, 0.001));
    await press(tester, LogicalKeyboardKey.equal, '+');
    expect(view(tester).fov / pinched, closeTo(2 / 1.5, 0.001));

    final before = view(tester);
    await tester.longPress(find.byKey(const ValueKey('sphere-dial')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Little planet'));
    await tester.pump();
    expect(view(tester).planet, isTrue);
    await press(tester, LogicalKeyboardKey.keyP, 'p');
    expect(view(tester), before, reason: 'left, back where it was');

    await tester.pressKey(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(find.byType(SphereFrame), findsNothing, reason: 'the flat photo');
    await tester.pressKey(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(title(tester), shown);
    await unmount(tester);
  });

  testWidgets('a sphere is built once the flight that opens it lands', (
    tester,
  ) async {
    await pump(tester, '1.jpg', landed: false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    expect(find.byType(SpherePhoto, skipOffstage: false), findsNothing);
    await settle(tester);
    expect(find.byType(SpherePhoto), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('on a phone the sphere turns as the phone does, its pitch the '
      "phone's and its yaw after drags too, its sensors stopped while the app "
      'is away or a route covers the viewer, until asked to stop or it has no '
      'gyroscope', (tester) async {
    final gyroscope = StreamController<GyroscopeEvent>.broadcast();
    final gravity = StreamController<AccelerometerEvent>.broadcast();
    final field = StreamController<MagnetometerEvent>.broadcast();
    await pump(
      tester,
      '1.jpg',
      sensors: (
        gyroscope: gyroscope.stream,
        gravity: gravity.stream,
        field: field.stream,
      ),
    );
    expect(find.byTooltip('Compass lock'), findsNothing);
    await tapTip(tester, 'Move to look around');
    // Where the slow turn, which the tap stopped, left it.
    final start = view(tester).yaw;
    final at = DateTime(2026);
    // Held upright, turned left at 1 rad/s for half a second once the
    // sensors' first five readings, which count for nothing, have passed.
    for (var ms = 0; ms <= 600; ms += 20) {
      final t = at.add(Duration(milliseconds: ms));
      gravity.add(AccelerometerEvent(0, 9.81, 0, t));
      gyroscope.add(GyroscopeEvent(0, 1, 0, t));
    }
    await tester.pump();
    expect(view(tester).yaw, closeTo(start - 0.5, 1e-9));
    expect(view(tester).pitch, closeTo(0, 1e-9));
    // A drag turns it, and the phone turns it on from there.
    final finger = await tester.startGesture(
      tester.getCenter(find.byType(SphereFrame)),
    );
    await finger.moveBy(const Offset(-40, 0));
    final dragged = view(tester).yaw;
    await finger.moveBy(const Offset(-200, 0));
    await finger.up();
    gyroscope.add(GyroscopeEvent(0, 1, 0, at.add(const Duration(seconds: 1))));
    await tester.pump();
    // 200 px of the lens' 75° over the short side, less 0.4 s at 1 rad/s.
    final short = tester.getSize(find.byType(SphereFrame)).shortestSide;
    expect(
      view(tester).yaw - dragged,
      closeTo(75 * pi / 180 * 200 / short - 0.4, 1e-9),
    );
    final turned = view(tester).yaw;
    final reading = <bool>[];
    Future<void> read([List<AppLifecycleState> states = const []]) async {
      states.forEach(tester.binding.handleAppLifecycleStateChanged);
      await tester.pumpAndSettle();
      reading.add(
        gyroscope.hasListener && gravity.hasListener && field.hasListener,
      );
    }

    await read([AppLifecycleState.inactive, AppLifecycleState.hidden]);
    await read([AppLifecycleState.inactive, AppLifecycleState.resumed]);
    final navigator = Navigator.of(tester.element(find.byType(SphereFrame)))
      ..push(MaterialPageRoute<void>(builder: (_) => const SizedBox()));
    await read();
    navigator.pop();
    await read();
    expect(reading, [false, true, false, true]);
    await tapTip(tester, 'Compass lock');
    await press(tester, LogicalKeyboardKey.keyG, 'g');
    expect(find.byTooltip('Compass lock'), findsNothing);
    gyroscope.add(GyroscopeEvent(0, 1, 0, at.add(const Duration(seconds: 2))));
    await tester.pump();
    expect(view(tester).yaw, turned, reason: 'stopped');
    // A phone without a gyroscope says so, and motion turns off.
    await press(tester, LogicalKeyboardKey.keyG, 'g');
    expect(find.byTooltip('Compass lock'), findsOneWidget);
    gyroscope.addError(PlatformException(code: 'NO_SENSOR'));
    await tester.pump();
    await tester.pump();
    expect(
      said('This device has no gyroscope to look around with'),
      findsOneWidget,
    );
    expect(find.byTooltip('Compass lock'), findsNothing);
    await unmount(tester);
  });

  testWidgets('motion asks for the sensors first, as Safari must, and says '
      'when the browser refuses them', (tester) async {
    var (asked, allow) = (0, false);
    await pump(
      tester,
      '1.jpg',
      sensors: (
        gyroscope: const Stream.empty(),
        gravity: const Stream.empty(),
        field: const Stream.empty(),
      ),
      permission: () async {
        asked++;
        return allow;
      },
    );
    await tapTip(tester, 'Move to look around');
    expect(asked, 1);
    expect(
      said('This browser did not allow access to the motion sensors'),
      findsOneWidget,
    );
    expect(find.byTooltip('Compass lock'), findsNothing);
    allow = true;
    await tapTip(tester, 'Move to look around');
    expect(asked, 2);
    expect(find.byTooltip('Compass lock'), findsOneWidget);
    await press(tester, LogicalKeyboardKey.keyG, 'g');
    expect(asked, 2, reason: 'stopping asks nothing');
    expect(find.byTooltip('Compass lock'), findsNothing);
    await unmount(tester);
  });

  testWidgets('on a phone neither swipes nor edge taps page past a sphere, '
      'which has no Previous or Next buttons', (tester) async {
    await pump(tester, '1.jpg', size: const Size(400, 800));
    final shown = title(tester);
    expect(find.byTooltip('Previous'), findsNothing);
    expect(find.byTooltip('Next'), findsNothing);
    await tester.fling(find.byType(SphereFrame), const Offset(-300, 0), 1000);
    await tester.pumpAndSettle();
    expect(title(tester), shown, reason: 'the pager is locked');
    final frame = find.byType(SphereFrame);
    await tester.tapAt(tester.getRect(frame).centerRight - const Offset(8, 0));
    await tester.pumpAndSettle();
    expect(frame, findsOneWidget, reason: 'an edge tap pages no more');
    await unmount(tester);
  });

  testWidgets('on desktops a mouse drag turns a sphere and drags no file out', (
    tester,
  ) async {
    final dragged = <Object?>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      fileDragChannel,
      (call) async =>
          call.method == 'drag' ? dragged.add(call.arguments) : null,
    );
    await pump(tester, '1.jpg');
    Future<void> drag() async {
      final mouse = await tester.startGesture(
        tester.getCenter(find.byType(SphereFrame)),
        kind: PointerDeviceKind.mouse,
      );
      await mouse.moveBy(const Offset(-200, 0));
      await mouse.up();
      await tester.pumpAndSettle();
    }

    await drag();
    final from = view(tester);
    await drag();
    expect(dragged, isEmpty);
    expect(view(tester).yaw, greaterThan(from.yaw));
    await unmount(tester);
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  testWidgets('a partial panorama never turns past its picture', (
    tester,
  ) async {
    await pump(tester, '1.jpg', crop: '0,1024,8192,2048,8192,4096');
    await tester.drag(find.byType(SphereFrame), const Offset(0, 2000));
    await tester.pumpAndSettle();
    const band = Sphere(crop: Rect.fromLTWH(0, 0.25, 1, 0.5));
    final v = view(tester);
    expect(v.pitch, greaterThan(0));
    expect(v.within(band, tester.getSize(find.byType(SphereFrame))), isTrue);
    await unmount(tester);
  });

  testWidgets('a 360° video plays projected, its controls, scrubbing and info '
      'as on a flat one, all on one player', (tester) async {
    VideoPlayerPlatform.instance = players = _Projecting();
    await pump(tester, '1.mp4');
    expect(find.byType(SphereVideo), findsOneWidget);
    // The player's view projects the shown view to the viewport's pixels.
    final viewport = tester.getSize(find.byType(SphereFrame));
    expect(
      tester.widget<SphereProjection>(find.byType(SphereProjection)).filter,
      view(tester).v360(const Sphere(), viewport),
    );
    expect(players.uris, ['file:///p/1.mp4']);
    expect(
      tester.widget<SphereFrame>(find.byType(SphereFrame)).turning,
      isTrue,
    );
    await tester.tap(find.byKey(const ValueKey('video-play')));
    await tester.pump();
    players.calls.clear();
    await tapTip(tester, 'Pause');
    final slider = find.byType(Slider);
    final drag = await tester.startGesture(tester.getCenter(slider));
    await tester.pump();
    await drag.moveBy(const Offset(40, 0));
    await drag.up();
    await settle(tester);
    await tester.tap(find.byTooltip('Mute'));
    await tester.pressKey(LogicalKeyboardKey.keyI, character: 'i');
    await settle(tester);
    expect(find.byType(InfoPanel), findsOneWidget);
    await tester.pressKey(LogicalKeyboardKey.keyI, character: 'i');
    await settle(tester);
    expect(find.byType(SphereVideo), findsOneWidget);
    expect(players.calls.first, 'pause 0');
    expect(players.calls.where((c) => c.startsWith('seek 0')), isNotEmpty);
    expect(players.calls, contains('volume 0 0.0'));
    expect(players.calls.where((c) => c.startsWith('dispose')), isEmpty);
    expect(players.uris, hasLength(1));
    await unmount(tester);
  });

  testWidgets('a 360° video whose row comes late has its player at once, '
      'but shows its poster, never the player flat, until the row says it '
      'is a sphere', (tester) async {
    await pump(tester, '1.mp4', rows: const Duration(seconds: 5));
    expect(tester.widget<VideoView>(find.byType(VideoView)).player, isNotNull);
    expect(find.byType(VideoPlayer), findsNothing);
    expect(find.byType(SphereVideo), findsNothing);
    await tester.pump(const Duration(seconds: 5));
    await settle(tester);
    expect(find.byType(SphereVideo), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('a 360° video that neither libmpv nor Impeller can project '
      'says it cannot play, over its projected poster, never flat', (
    tester,
  ) async {
    await pump(tester, '1.mp4');
    expect(ui.ImageFilter.isShaderFilterSupported, isFalse);
    expect(find.text('This video cannot play on this device'), findsOneWidget);
    expect(find.byType(SphereVideo), findsOneWidget);
    expect(find.byKey(const ValueKey('player 0')), findsNothing);
    await unmount(tester);
  });

  testWidgets('a 360° video the platform cannot decode says so over its '
      'projected poster', (tester) async {
    VideoPlayerPlatform.instance = players = FakePlayers(failing: {'1.mp4'});
    await pump(tester, '1.mp4');
    expect(find.text('This video cannot play on this device'), findsOneWidget);
    expect(find.byType(SphereVideo), findsOneWidget);
    expect(find.byType(Slider), findsNothing);
    await unmount(tester);
  });

  // docs/10 §4.4: from its metadata (PhotoKit's panoramas, GPano that is no
  // sphere), never from its shape or name (owner, photolib-design#640).
  testWidgets('a flat panorama opens as a strip the height of the viewer, '
      'which drags pan instead of turning the page, and its Previous and '
      'Next buttons turn; a photo as wide and named PANO without the '
      'metadata fits', (tester) async {
    await pump(
      tester,
      '1.jpg',
      second: 'PANO_20190101_120000.jpg',
      projection: null,
      facets: 'panorama',
      width: 12000,
    );
    final photo = find.byType(InteractiveViewer).hitTestable();
    Matrix4 shown() =>
        tester.widget<InteractiveViewer>(photo).transformationController!.value;
    // 6:1 fits 800 × 528, above the filmstrip, at 800 × 133: 3.96 times that
    // is 528 high.
    expect(tester.getSize(photo), const Size(800, 528));
    expect(shown().getMaxScaleOnAxis(), closeTo(3.96, 1e-9));
    expect(shown().getTranslation().y, closeTo(528 * (1 - 3.96) / 2, 1e-6));
    final strip = title(tester);
    final x = shown().getTranslation().x;
    await tester.drag(photo, const Offset(-200, 0));
    await settle(tester);
    expect(title(tester), strip);
    expect(shown().getTranslation().x, lessThan(x - 150));
    // A tap hides the bar alone: the photo keeps its box (docs/10 §4.6).
    await tester.tap(photo);
    await settle(tester);
    expect(find.byType(CloseButton), findsNothing);
    expect(tester.getSize(photo), const Size(800, 528));
    expect(shown().getMaxScaleOnAxis(), closeTo(3.96, 1e-9));
    await tester.tap(photo);
    await settle(tester);

    await tester.tap(find.byTooltip('Next'));
    await settle(tester);
    expect(title(tester), isNot(strip));
    expect(shown().getMaxScaleOnAxis(), 1, reason: 'no panorama');
    expect(find.byTooltip('Previous'), findsNothing);

    await tester.fling(photo, const Offset(300, 0), 1000);
    await settle(tester);
    expect(title(tester), strip);
    expect(shown().getMaxScaleOnAxis(), closeTo(3.96, 1e-9));
    await tester.drag(photo, const Offset(300, 0));
    await settle(tester);
    expect(title(tester), strip, reason: 'drags pan it again');

    // A double tap fits it, and so it stays.
    final centre = tester.getCenter(photo);
    await tester.tapAt(centre);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(centre);
    await settle(tester);
    await tester.tap(photo);
    await settle(tester);
    expect(shown().getMaxScaleOnAxis(), 1);
    await unmount(tester);
  });

  testWidgets('a panorama larger than its picture loaded decodes the 512 '
      'pixel tiles in view, at the sample a narrower lens needs, past one '
      'that fails', (tester) async {
    final regions = _Regions(const Size(16384, 8192), failFirst: true);
    await pump(tester, '1.jpg', width: 16384, regions: regions);
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await settle(tester);
    // Through 75°, the grey picture of 327 pixels needs coarse tiles.
    expect(regions.asked, isNotEmpty);
    expect(regions.asked.every((a) => a.$2 >= 4), isTrue);
    final frame = find.byType(SphereFrame);
    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: tester.getCenter(frame),
        scrollDelta: const Offset(0, -600),
      ),
    );
    await settle(tester);
    final sharp = [
      for (final (region, sample) in regions.asked)
        if (sample == 1) region,
    ];
    expect(sharp, isNotEmpty);
    expect(sharp.every((r) => r.width == 512 && r.height == 512), isTrue);
    expect(
      tester.widget<SphereFrame>(frame).tiles,
      hasLength(sharp.length),
      reason: 'only the sharpest tiles show',
    );
    await unmount(tester);
  });

  testWidgets('a cylindrical panorama opens projected, and the fisheye lens '
      'shows more of it and back', (tester) async {
    await pump(tester, '1.jpg', projection: 'cylindrical', width: 6000);
    expect(find.byType(SpherePhoto), findsOneWidget);
    final before = view(tester);
    await tester.longPress(find.byKey(const ValueKey('sphere-dial')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fisheye'));
    await tester.pump();
    // As wide as the cylinder's height allows.
    expect(view(tester).fisheye, isTrue);
    expect(view(tester).fov, greaterThan(before.fov));
    await press(tester, LogicalKeyboardKey.keyO, 'o');
    expect(view(tester), before);
    await unmount(tester);
  });

  testWidgets('a flat stereo video shows one eye, the left or the top', (
    tester,
  ) async {
    for (final (stereo, shown, frame) in [
      ('top_bottom', const Size(800, 225), const Size(800, 450)),
      ('left_right', const Size(647, 728), const Size(1294, 728)),
    ]) {
      await pump(
        tester,
        '1.mp4',
        projection: null,
        stereo: stereo,
        size: const Size(800, 800),
      );
      final player = find.byType(VideoPlayer);
      final clip = find.ancestor(of: player, matching: find.byType(ClipRect));
      expect(tester.getSize(clip.first), within(distance: 1, from: shown));
      expect(tester.getSize(player), within(distance: 1, from: frame));
      expect(tester.getTopLeft(player), tester.getTopLeft(clip.first));
      await unmount(tester);
      await db.delete(db.localAsset).go();
      // Its frame rate's query hears the delete, then closes on a timer.
      await tester.pump(Duration.zero);
    }
  });

  testWidgets('only a photo sphere or 360° video has projection commands: a '
      'flat video or photo of any shape has none in the bar, its menu, the '
      'palette or on a key', (tester) async {
    const projecting = ['Little planet', 'Fisheye', 'Move to look around'];
    final icons = {
      Icons.threesixty,
      Icons.panorama_photosphere_outlined,
      Icons.public,
      Icons.panorama_fish_eye,
      Icons.screen_rotation_alt,
      Icons.explore_outlined,
    };
    // The viewer's commands, which the bar, its menu and the palette show.
    Future<List<Command>> commands(
      String name,
      String? projection,
      int width,
    ) async {
      await pump(
        tester,
        name,
        projection: projection,
        width: width,
        sensors: (
          gyroscope: const Stream.empty(),
          gravity: const Stream.empty(),
          field: const Stream.empty(),
        ),
      );
      return tester.widget<Commands>(find.byType(Commands).last).commands;
    }

    for (final name in ['1.jpg', '1.mp4']) {
      final sphere = [
        for (final c in await commands(name, 'equirectangular', 4000)) c.label,
      ];
      expect(sphere, containsAllInOrder(projecting), reason: name);
      await unmount(tester);
      await db.delete(db.localAsset).go();
      // 2:1 as an equirectangular picture, 6:1 as a panorama, and portrait.
      for (final width in [4000, 12000, 1500]) {
        final flat = await commands(name, null, width);
        final shape = '$name $width × 2000';
        expect(
          [for (final c in flat) c.label],
          [
            for (final c in sphere)
              if (!projecting.contains(c)) ...[
                // A flat photo turns, as no sphere does.
                if (c == 'Favourite' && name.endsWith('.jpg')) 'Rotate',
                c,
              ],
          ],
          reason: shape,
        );
        expect(
          [
            for (final c in flat)
              if (icons.contains(c.icon)) c.label,
          ],
          isEmpty,
          reason: shape,
        );
        for (final key in [
          LogicalKeyboardKey.keyV,
          LogicalKeyboardKey.keyP,
          LogicalKeyboardKey.keyO,
          LogicalKeyboardKey.keyG,
        ]) {
          await tester.pressKey(key, character: key.keyLabel.toLowerCase());
          await settle(tester);
        }
        expect(find.byType(SphereVideo), findsNothing);
        expect(find.byType(SpherePhoto), findsNothing);
        await unmount(tester);
        await db.delete(db.localAsset).go();
        // A video's frame rate query hears the delete, then closes on a timer.
        await tester.pump(Duration.zero);
      }
    }
  });
}

/// A panorama's regions, each decoded grey, as asked.
class _Regions implements Regions {
  new(this.size, {this.failFirst = false});

  @override
  final Size size;

  final asked = <(Rect, int)>[];
  bool failFirst;

  @override
  Future<ui.Image> decode(Rect region, int sample) async {
    asked.add((region, sample));
    if (failFirst) {
      failFirst = false;
      throw StateError('unreadable');
    }
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawColor(const Color(0xff808080), BlendMode.src);
    return recorder.endRecording().toImageSync(
      region.width ~/ sample,
      region.height ~/ sample,
    );
  }

  @override
  void close() {}
}

/// Players that project 360° video themselves, as libmpv's do.
class _Projecting extends FakePlayers implements ProjectingPlayers;
