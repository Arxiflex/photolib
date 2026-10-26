import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:photolib/features/settings/settings.dart';
import 'package:photolib/features/viewer/video.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import '../../support/fake_players.dart';
import '../../support/viewer.dart';

void main() {
  late FakePlayers players;
  setUp(() => VideoPlayerPlatform.instance = players = FakePlayers());
  const size = Size(1000, 600);
  final play = find.byKey(const ValueKey('video-play'));
  final controls = find.byKey(const ValueKey('video-controls'));
  final bar = find.byType(CloseButton);

  // Two videos, then a photo.
  Future<ValueNotifier<int>> pump(
    WidgetTester tester, {
    int at = 0,
    Settings settings = const Settings(),
  }) => pumpViewer(
    tester,
    size: size,
    count: 3,
    at: at,
    video: (p) => p < 2,
    settings: settings,
  );

  // What the app last asked a player: to play or to pause.
  String last() => players.calls.lastWhere(RegExp('^(play|pause) ').hasMatch);

  Future<TestGesture> mouse(WidgetTester tester, Offset at) async {
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: at);
    return mouse;
  }

  Future<void> click(WidgetTester tester, Offset at) async {
    await tester.tapAt(at, kind: PointerDeviceKind.mouse);
    await tester.pump(kDoubleTapTimeout);
    await tester.pump();
  }

  testWidgets('a video opens on its poster and a centred 76 dp play button, '
      'paused; a click on the picture plays and pauses it', (tester) async {
    await pump(tester);
    expect(tester.getSize(play), const Size(76, 76));
    expect(tester.getCenter(play), tester.getCenter(find.byType(VideoView)));
    expect(players.calls, isNot(contains('play 0')));
    await click(tester, const Offset(300, 200));
    expect(players.calls, contains('play 0'));
    expect(play, findsNothing);
    expect(bar, findsOneWidget, reason: 'the click plays, it hides nothing');
    await click(tester, const Offset(300, 200));
    expect(last(), 'pause 0');
    expect(play, findsOneWidget);
    await tester.tap(play);
    await tester.pump();
    expect(last(), 'play 0');
  });

  testWidgets('set to, a video plays as it opens', (tester) async {
    await pump(
      tester,
      settings: const Settings(toggles: {Toggle.autoplay: true}),
    );
    expect(players.calls, contains('play 0'));
    expect(play, findsNothing);
  });

  testWidgets('its controls sit inside the picture: play, the time, a '
      'scrubber, mute and the speeds 1×, 1.5×, 2× and 0.5×', (tester) async {
    await pump(tester);
    // 1920 × 1080 fits 938.7 × 528 in the middle of the stage, 1000 × 528
    // above the filmstrip.
    final stage = tester.getRect(find.byType(VideoView));
    final picture = Rect.fromCenter(
      center: stage.center,
      width: 528 * 16 / 9,
      height: 528,
    );
    final rect = tester.getRect(controls);
    expect(rect.left, closeTo(picture.left, 0.5));
    expect(rect.right, closeTo(picture.right, 0.5));
    expect(rect.bottom, closeTo(picture.bottom, 0.5));
    for (final control in ['Play', 'Mute', 'Playback speed']) {
      expect(
        find.descendant(of: controls, matching: find.byTooltip(control)),
        findsOneWidget,
        reason: control,
      );
    }
    expect(
      find.descendant(of: controls, matching: find.byType(Slider)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: controls, matching: find.text(' / 0:03.000')),
      findsOneWidget,
    );
    await tester.tap(find.byTooltip('Playback speed'));
    await tester.pumpAndSettle();
    expect(
      [
        for (final item in tester.widgetList<PopupMenuItem<double>>(
          find.byType(PopupMenuItem<double>),
        ))
          item.value,
      ],
      [1, 1.5, 2, 0.5],
    );
  });

  testWidgets('while it plays the controls hide 1.5 s after the mouse stops '
      'and 0.3 s after it leaves, never over a control or with a menu open, '
      'come back as it moves and stay while paused', (tester) async {
    await pump(tester);
    final pointer = await mouse(tester, const Offset(300, 200));
    await click(tester, const Offset(300, 200));
    await pointer.moveTo(const Offset(310, 200));
    await tester.pump(const Duration(milliseconds: 1400));
    expect(controls, findsOneWidget);
    await tester.pump(const Duration(milliseconds: 200));
    expect(controls, findsNothing, reason: '1.5 s after the mouse stopped');
    expect(bar, findsNothing);
    await pointer.moveTo(const Offset(320, 200));
    await tester.pump();
    expect(controls, findsOneWidget, reason: 'it moved');
    await pointer.moveTo(const Offset(500, 650));
    await tester.pump(const Duration(milliseconds: 350));
    expect(controls, findsNothing, reason: '0.3 s after it left');
    await pointer.moveTo(const Offset(320, 200));
    await tester.pump();
    await pointer.moveTo(tester.getCenter(find.byTooltip('Mute')));
    await tester.pump(const Duration(seconds: 3));
    expect(controls, findsOneWidget, reason: 'on a control');
    await pointer.moveTo(tester.getCenter(find.byTooltip('Playback speed')));
    await tester.tap(find.byTooltip('Playback speed'));
    await tester.pump();
    await pointer.moveTo(const Offset(320, 100));
    await tester.pump(const Duration(seconds: 3));
    expect(controls, findsOneWidget, reason: 'a menu is open');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(last(), 'pause 0');
    await tester.pump(const Duration(seconds: 3));
    expect(controls, findsOneWidget, reason: 'paused');
  });

  testWidgets('leaving the item gives back the chrome playback hid, not the '
      'chrome the user hid', (tester) async {
    final position = await pump(tester);
    await click(tester, const Offset(300, 200));
    await tester.pump(const Duration(seconds: 2));
    expect(bar, findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(position.value, 1);
    expect(bar, findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    await click(tester, const Offset(500, 300));
    await tester.pumpAndSettle();
    expect(bar, findsNothing, reason: 'the user hid it on the photo');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(find.byType(VideoView), findsWidgets);
    expect(bar, findsNothing);
  });
}
