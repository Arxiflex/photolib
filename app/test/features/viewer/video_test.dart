import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/gestures.dart'
    show PointerDeviceKind, kLongPressTimeout;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:photolib/features/library/timeline/pipeline.dart';
import 'package:photolib/features/library/timeline/providers.dart';
import 'package:photolib/features/settings/settings.dart';
import 'package:photolib/features/viewer/regions.dart';
import 'package:photolib/features/viewer/video.dart';
import 'package:photolib/l10n/app_localizations.dart';
import 'package:photolib_data/photolib_data.dart';
import 'package:video_player/video_player.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import '../../support/fake_players.dart';
import '../../support/pump_app.dart';
import '../../support/viewer.dart';

const videos = ['1.mp4', '2.mp4', '3.jpg', '4.mp4'];

void main() {
  late Replica db;
  late FakePlayers players;
  setUp(() {
    db = Replica(NativeDatabase.memory());
    VideoPlayerPlatform.instance = players = FakePlayers();
  });
  tearDown(() => db.close());

  // Four items of [names] in [volume], newest first: 1 and 2 on May 3, then 3
  // and 4; the first one's motion video where [motion] says.
  Future<void> pump(
    WidgetTester tester, {
    List<String> names = const ['1.jpg', '2.jpg', '3.jpg', '4.jpg'],
    String volume = '/p',
    (int, int)? motion,
    double? frameRate,
    Directory? cache,
    Settings? settings,
    String source = 'folder',
    Uint8List? asset,
  }) async {
    for (final (i, taken) in [
      '2024-05-03T12:00:00',
      '2024-05-03T11:00:00',
      '2024-05-01T12:00:00',
      '2024-04-30T12:00:00',
    ].indexed) {
      await db
          .into(db.localAsset)
          .insert(
            LocalAssetCompanion.insert(
              id: Uint8List(16)..[15] = i + 1,
              source: source,
              volume: Value(volume),
              sourceId: '${i + 1}',
              path: Value(names[i]),
              name: Value(names[i]),
              mime: Value(
                names[i].endsWith('.mp4') ? 'video/mp4' : 'image/jpeg',
              ),
              motionOffset: Value(i == 0 ? motion?.$1 : null),
              motionLength: Value(i == 0 ? motion?.$2 : null),
              frameRate: Value(frameRate),
              assetId: Value(i == 0 ? asset : null),
              size: 2512000,
              mtime: 0,
              takenLocal: Value(taken),
              takenUtc: Value(
                DateTime.parse('${taken}Z').millisecondsSinceEpoch,
              ),
              width: const Value(4000),
              height: const Value(3000),
              extracted: const Value(1),
            ),
          );
    }
    // Videos play as they open, unless a test says otherwise.
    final played = Settings(
      toggles: {Toggle.autoplay: true, ...?settings?.toggles},
    );
    await pumpApp(
      tester,
      replica: (_) => db,
      settings: MemoryStore(jsonEncode(played.toJson())),
      overrides: [
        thumbnailPipelineProvider.overrideWith((ref) async => Grey()),
        regionsProvider.overrideWithValue((_) async => null),
        if (cache != null) cacheDirectoryProvider.overrideWith((_) => cache),
      ],
    );
  }

  /// Opens the [n]th item of May 3 from the timeline.
  Future<void> open(WidgetTester tester, int n) async {
    final semantics = tester.ensureSemantics();
    await tester.pump();
    tester.semantics.tap(find.semantics.byLabel(RegExp('${n + 1} of 2\$')));
    await tester.pumpAndSettle();
    semantics.dispose();
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
  }

  // What the app asked of the players, but what each is set to at first.
  List<String> asked() => [
    for (final c in players.calls)
      if (!RegExp(r'^(loop|volume|speed) \d+ (false|1\.0)$').hasMatch(c)) c,
  ];

  testWidgets('the viewer opens on the poster, then makes the shown '
      "video's player, plays it and readies its neighbour's", (tester) async {
    await pump(tester, names: videos);
    final semantics = tester.ensureSemantics();
    await tester.pump();
    tester.semantics.tap(find.semantics.byLabel(RegExp(r'1 of 2$')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(players.uris, isEmpty, reason: 'the viewer is still opening');
    expect(
      find.descendant(
        of: find.byType(VideoView),
        matching: find.byType(RawImage),
      ),
      findsWidgets,
    );
    await tester.pumpAndSettle();
    semantics.dispose();
    expect(players.uris, ['file:///p/1.mp4', 'file:///p/2.mp4']);
    expect(asked(), contains('play 0'));
    expect(asked(), isNot(contains('play 1')));
    expect(find.byKey(const ValueKey('player 0')), findsOneWidget);
    await unmount(tester);
    // Closing a player's events takes real time.
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    expect(players.calls, containsAll(['dispose 0', 'dispose 1']));
  });

  testWidgets('a swipe makes, plays, pauses, rewinds and disposes no '
      'player until the pages rest', (tester) async {
    await pump(tester, names: ['1.mp4', '2.mp4', '3.mp4', '4.mp4']);
    await open(tester, 0);
    expect(players.uris, ['file:///p/1.mp4', 'file:///p/2.mp4']);

    Future<void> swipe() async {
      players.calls.clear();
      final drag = await tester.startGesture(
        tester.getCenter(find.byType(PageView)),
      );
      for (var i = 0; i < 6; i++) {
        await drag.moveBy(const Offset(-50, 0));
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(players.calls, isEmpty, reason: 'while dragged');
      await drag.up();
      await tester.pump(const Duration(milliseconds: 16));
      expect(players.calls, isEmpty, reason: 'while it settles');
      await tester.pumpAndSettle();
    }

    await swipe();
    // The next plays before the one left is rewound, which takes longer.
    expect(asked(), containsAllInOrder(['pause 0', 'play 1', 'seek 0 0']));
    expect(players.uris.last, 'file:///p/3.mp4');
    expect(find.byKey(const ValueKey('player 1')), findsOneWidget);
    await swipe();
    expect(asked(), containsAllInOrder(['play 2', 'dispose 0']));
    expect(players.uris.last, 'file:///p/4.mp4');
    await unmount(tester);
  });

  testWidgets('a swipe to a photo pauses and rewinds the video', (
    tester,
  ) async {
    await pump(tester, names: videos);
    await open(tester, 1);
    players.calls.clear();
    await tester.fling(find.byType(PageView), const Offset(-300, 0), 1000);
    await tester.pumpAndSettle();
    expect(asked(), containsAllInOrder(['pause 0', 'seek 0 0']));
    expect(players.uris, hasLength(3), reason: 'a photo needs no player');
    await unmount(tester);
  });

  Future<void> swipe(WidgetTester tester, double dx) async {
    await tester.fling(find.byType(PageView), Offset(dx, 0), 1000);
    await tester.pumpAndSettle();
  }

  testWidgets('set to resume, a video comes back where it was left, even '
      'once its player is gone', (tester) async {
    await pump(
      tester,
      names: ['1.mp4', '2.mp4', '3.mp4', '4.mp4'],
      settings: const Settings(toggles: {Toggle.resume: true}),
    );
    await open(tester, 0);
    await tester.pressKey(LogicalKeyboardKey.period, character: '.');
    players.calls.clear();
    await swipe(tester, -300);
    expect(asked(), contains('pause 0'));
    expect(asked(), isNot(contains('seek 0 0')), reason: 'not rewound');
    await swipe(tester, -300);
    expect(asked(), contains('dispose 0'));
    players.calls.clear();
    await swipe(tester, 300);
    await swipe(tester, 300);
    final again = players.uris.lastIndexOf('file:///p/1.mp4');
    expect(again, greaterThan(0), reason: 'a new player');
    expect(asked(), containsAllInOrder(['seek $again 33', 'play $again']));
    await unmount(tester);
  });

  testWidgets(
    'a video with sound pauses other audio and a silent one plays over it, '
    'as every one does when set; videos loop as set',
    (tester) async {
      // Android's player takes audio focus as it was made, so a silent one is
      // made again; iOS's audio session is the app's, set as each plays.
      final android = defaultTargetPlatform == TargetPlatform.android;
      for (final set in [false, true]) {
        VideoPlayerPlatform.instance = players = FakePlayers(silent: {'2.mp4'});
        await pump(
          tester,
          names: videos,
          settings: set
              ? const Settings(
                  toggles: {Toggle.loop: true, Toggle.mixAudio: true},
                )
              : null,
        );
        await open(tester, 0);
        final again = android && !set;
        expect(players.uris, [
          for (final n in [1, 2, if (again) 2]) 'file:///p/$n.mp4',
        ]);
        expect(
          players.mixes,
          android ? [set, set, if (again) true] : [null, null],
        );
        expect(
          players.calls,
          containsAllInOrder(['loop 0 $set', 'mix $set', 'play 0']),
        );
        players.calls.clear();
        await swipe(tester, -300);
        expect(
          players.calls,
          containsAllInOrder(['mix true', 'play ${again ? 2 : 1}']),
        );
        await unmount(tester);
        await db.delete(db.localAsset).go();
        // A video's frame rate query hears the delete, then closes on a timer.
        await tester.pump(Duration.zero);
      }
    },
    variant: const TargetPlatformVariant({
      TargetPlatform.android,
      TargetPlatform.iOS,
    }),
  );

  testWidgets('a video that ends goes on to the next item, when set', (
    tester,
  ) async {
    for (final next in [false, true]) {
      VideoPlayerPlatform.instance = players = FakePlayers();
      await pump(
        tester,
        names: ['1.mp4', '2.mp4', '3.mp4', '4.mp4'],
        settings: Settings(toggles: {Toggle.autoNext: next}),
      );
      await open(tester, 0);
      players.complete(0);
      await tester.pumpAndSettle();
      expect(asked().contains('play 1'), next);
      await unmount(tester);
      await db.delete(db.localAsset).go();
      // A video's frame rate query hears the delete, then closes on a timer.
      await tester.pump(Duration.zero);
    }
  });

  testWidgets('its controls set the speed, pause and mute, and the keys step '
      'a frame with the position to the millisecond', (tester) async {
    await pump(tester, names: videos);
    await open(tester, 0);
    players.calls.clear();
    // A player takes a speed while it plays.
    await tester.tap(find.byTooltip('Playback speed'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('0.5×'));
    await tester.pumpAndSettle();
    // Playing, the controls hide 1.5 s after the mouse moved.
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(100, 100));
    await mouse.moveTo(const Offset(110, 100));
    await tester.pump();
    await tester.tap(find.byTooltip('Pause'));
    await tester.pump();
    // In the controls and in the middle of the picture.
    expect(find.byTooltip('Play'), findsNWidgets(2));
    await tester.pressKey(LogicalKeyboardKey.period, character: '.');
    await tester.pressKey(LogicalKeyboardKey.period, character: '.');
    await tester.pump(const Duration(milliseconds: 200));
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('video-position'))).data,
      '0:00.066',
    );
    await tester.pressKey(LogicalKeyboardKey.comma, character: ',');
    await tester.tap(find.byTooltip('Mute'));
    await tester.pump();
    expect(
      players.calls,
      containsAllInOrder([
        'speed 0 0.5',
        'pause 0',
        'seek 0 33',
        'seek 0 66',
        'seek 0 33',
        'volume 0 0.0',
      ]),
    );
    expect(find.byTooltip('Unmute'), findsOneWidget);
    await unmount(tester);
  });

  /// Opens the first video, whose captions are in [dir], once they are read.
  Future<void> openCaptioned(WidgetTester tester, Directory dir) async {
    await pump(tester, names: videos, volume: dir.path);
    await open(tester, 0);
    // Reading the captions takes real time.
    for (
      var i = 0;
      i < 100 && find.byTooltip('Captions').evaluate().isEmpty;
      i++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();
  }

  testWidgets('a video shows the captions beside it, .srt or .vtt, as it '
      'plays, until they are turned off', (tester) async {
    final dir = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('captions-'),
    ))!;
    addTearDown(() => dir.delete(recursive: true));
    await tester.runAsync(() async {
      await File('${dir.path}/1.srt').writeAsString(
        '1\n00:00:01,000 --> 00:00:02,000\nSeen from the <i>tower</i>\n',
      );
      await File('${dir.path}/2.VTT')
          .writeAsString('WEBVTT\n\n00:00.500 --> 00:01.000\nThe second\n');
    });
    await openCaptioned(tester, dir);
    final view = tester.widget<VideoView>(find.byType(VideoView));
    await view.player!.seekTo(const Duration(milliseconds: 1500));
    await tester.pump();
    expect(find.text('Seen from the tower'), findsOneWidget);
    await tester.tap(find.byTooltip('Captions'));
    await tester.pump();
    expect(find.text('Seen from the tower'), findsNothing);
    await tester.tap(find.byTooltip('Captions'));
    await tester.pump();
    expect(find.text('Seen from the tower'), findsOneWidget);
    await unmount(tester);
    final vtt = await tester.runAsync(
      () => captionsOf(
        ThumbnailItem('2', Uri.file('${dir.path}/2.mp4'), video: true),
      ),
    );
    expect(
      [for (final c in vtt!.captions) (c.start, c.text)],
      [(const Duration(milliseconds: 500), 'The second')],
    );
  });

  testWidgets("a video's controls and captions leave as the viewer shrinks "
      'back into its cell, as the rest of its chrome does', (tester) async {
    final dir = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('captions-'),
    ))!;
    addTearDown(() => dir.delete(recursive: true));
    await tester.runAsync(
      () => File('${dir.path}/1.srt')
          .writeAsString('1\n00:00:00,000 --> 00:00:09,000\nFrom the tower\n'),
    );
    await openCaptioned(tester, dir);
    expect(find.text('From the tower'), findsOneWidget);
    expect(find.byTooltip('Pause'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(find.text('From the tower'), findsNothing);
    expect(find.byTooltip('Pause'), findsNothing);
    // Nothing overflows the shrinking page.
    await tester.pumpAndSettle();
    await unmount(tester);
  });

  testWidgets('a video without captions has no button for them', (
    tester,
  ) async {
    await pump(tester, names: videos);
    await open(tester, 0);
    expect(find.byTooltip('Pause'), findsOneWidget);
    expect(find.byTooltip('Captions'), findsNothing);
    await unmount(tester);
  });

  testWidgets("a frame step is one frame at the file's own rate", (
    tester,
  ) async {
    await pump(tester, names: videos, frameRate: 25);
    await open(tester, 0);
    players.calls.clear();
    await tester.pressKey(LogicalKeyboardKey.period, character: '.');
    await tester.pressKey(LogicalKeyboardKey.period, character: '.');
    await tester.pump(const Duration(milliseconds: 200));
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('video-position'))).data,
      '0:00.080',
    );
    await tester.pressKey(LogicalKeyboardKey.comma, character: ',');
    expect(
      asked(),
      containsAllInOrder(['seek 0 40', 'seek 0 80', 'seek 0 40']),
    );
    await unmount(tester);
  });

  testWidgets('a video whose file says no frame rate steps at the rate its '
      'server asset says', (tester) async {
    final asset = Uint8List(16)..[0] = 7;
    await db
        .into(db.asset)
        .insert(
          AssetCompanion.insert(
            id: asset,
            libraryId: Uint8List(16),
            ownerId: Uint8List(16),
            originalFilename: '1.mp4',
            source: 'upload',
            mediaKind: 'video',
            createdAt: 0,
            fps: const Value(25),
          ),
        );
    await pump(tester, names: videos, asset: asset);
    await open(tester, 0);
    players.calls.clear();
    await tester.pressKey(LogicalKeyboardKey.period, character: '.');
    await tester.pump();
    expect(asked(), contains('seek 0 40'));
    await unmount(tester);
  });

  testWidgets('a PhotoKit video steps at the rate AVAsset says, which its row '
      'then keeps', (tester) async {
    final methods = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('org.photolib/viewer'),
      (call) async {
        methods.add('${call.method} ${call.arguments}');
        return switch (call.method) {
          'video' => '/p/1.mov',
          'frameRate' => 59.94,
          _ => null,
        };
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('org.photolib/viewer'),
        null,
      ),
    );
    await pump(tester, names: videos, source: 'photokit');
    await open(tester, 0);
    players.calls.clear();
    await tester.pressKey(LogicalKeyboardKey.period, character: '.');
    await tester.pump();
    expect(asked(), contains('seek 0 16'));
    final row = await (db.select(
      db.localAsset,
    )..where((a) => a.sourceId.equals('1'))).getSingle();
    expect(row.frameRate, 59.94);
    expect(methods.where((m) => m == 'frameRate [ph:1]'), hasLength(1));
    await unmount(tester);
  });

  testWidgets('seeking shows each frame under the thumb, then plays on', (
    tester,
  ) async {
    await pump(tester, names: videos);
    await open(tester, 0);
    players.calls.clear();
    final slider = find.byType(Slider);
    final gesture = await tester.startGesture(tester.getCenter(slider));
    await tester.pump();
    await gesture.moveBy(const Offset(40, 0));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    final seeks = [
      for (final c in asked())
        if (c.startsWith('seek')) c,
    ];
    expect(asked().first, 'pause 0');
    expect(seeks.length, greaterThanOrEqualTo(2));
    expect(asked().last, 'play 0');
    await unmount(tester);
  });

  testWidgets('the keyboard plays, pauses, steps frames and mutes', (
    tester,
  ) async {
    await pump(tester, names: videos);
    await open(tester, 0);
    players.calls.clear();
    await tester.pressKey(LogicalKeyboardKey.space);
    await tester.pressKey(LogicalKeyboardKey.period, character: '.');
    await tester.pressKey(LogicalKeyboardKey.comma, character: ',');
    await tester.pressKey(LogicalKeyboardKey.keyM, character: 'm');
    expect(asked(), containsAllInOrder(['pause 0', 'seek 0 33', 'seek 0 0']));
    expect(players.calls, contains('volume 0 0.0'));
    await unmount(tester);
  });

  testWidgets('a video the platform cannot play says so', (tester) async {
    VideoPlayerPlatform.instance = players = FakePlayers(failing: {'1.mp4'});
    await pump(tester, names: videos);
    await open(tester, 0);
    expect(find.text('This video cannot play on this device'), findsOneWidget);
    expect(find.byType(Slider), findsNothing);
    await unmount(tester);
  });

  testWidgets('a video that fails once it opened says so at once', (
    tester,
  ) async {
    await pump(tester, names: videos);
    await open(tester, 0);
    expect(find.byType(Slider), findsOneWidget);
    players.fail(0);
    await tester.pumpAndSettle();
    expect(find.text('This video cannot play on this device'), findsOneWidget);
    expect(find.byType(Slider), findsNothing);
    await unmount(tester);
  });

  testWidgets('a motion photo plays its video, read where extraction found '
      'it, while pressed and from its button', (tester) async {
    final dir = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('motion-'),
    ))!;
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/1.jpg');
    await tester.runAsync(
      () => file.writeAsBytes(List.generate(100, (i) => i)),
    );
    await pump(
      tester,
      volume: dir.path,
      motion: (90, 6),
      cache: Directory('${dir.path}/cache'),
    );
    await open(tester, 0);
    await tester.pumpUntil(() => players.uris.isNotEmpty);
    await tester.pumpAndSettle();
    final clip = File(Uri.parse(players.uris.single).toFilePath());
    expect(clip.parent.path, '${dir.path}/cache/motion');
    expect(await tester.runAsync(clip.readAsBytes), [90, 91, 92, 93, 94, 95]);

    players.calls.clear();
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(PageView)),
    );
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
    await tester.pump();
    // Its sound pauses other audio, which iOS sets as it plays.
    expect(asked(), containsAllInOrder(['seek 0 0', 'mix false', 'play 0']));
    expect(find.byKey(const ValueKey('player 0')), findsOneWidget);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(asked().last, 'pause 0');
    expect(find.byKey(const ValueKey('player 0')), findsNothing);

    await tester.tap(find.byTooltip('Play motion'));
    await tester.pump();
    expect(asked().last, 'play 0');
    await unmount(tester);
  });

  test('the motion clips kept are the newest, up to a size', () async {
    final dir = await Directory.systemTemp.createTemp('clips-');
    addTearDown(() => dir.delete(recursive: true));
    for (final (name, age) in [('a', 3), ('b', 1), ('c', 2)]) {
      await (File('${dir.path}/$name')..writeAsBytesSync(List.filled(10, 0)))
          .setLastModified(DateTime(2026, 1, 1, 0, 0, -age));
    }
    await keepNewest(dir, 25);
    expect(dir.listSync().map((f) => f.uri.pathSegments.last).toSet(), {
      'b',
      'c',
    });
  });

  test('positions show to the millisecond', () {
    expect(clock(Duration.zero), '0:00.000');
    expect(clock(const Duration(minutes: 1, milliseconds: 5)), '1:00.005');
    expect(
      clock(
        const Duration(hours: 1, minutes: 2, seconds: 3, milliseconds: 456),
      ),
      '1:02:03.456',
    );
  });

  testWidgets('the seek bar never moves as the position advances: the '
      'position in tabular figures, as wide as the duration', (tester) async {
    // 1:59:59.999, and positions as their digits roll over.
    const end = 7199999;
    const positions = [1, 111, 9999, 10000, 599999, 600000, 3600000, end];
    VideoPlayerPlatform.instance = FakePlayers(
      duration: const Duration(milliseconds: end),
    );
    final player = VideoPlayerController.file(File('/p/1.mp4'));
    await player.initialize();
    final label = find.byKey(const ValueKey('video-position'));
    for (final width in [360.0, 1000.0, 1920.0]) {
      tester.view.physicalSize = Size(width, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: Material(
            child: VideoView(
              poster: null,
              player: player,
              failed: false,
              controls: true,
              onTap: () {},
            ),
          ),
        ),
      );
      final size = tester.getSize(label);
      final bar = tester.getRect(find.byType(Slider));
      for (final ms in positions) {
        final at = Duration(milliseconds: ms);
        await player.seekTo(at);
        await tester.pump();
        expect(tester.widget<Text>(label).data, clock(at));
        expect(tester.getSize(label), size, reason: '${clock(at)}, $width');
        expect(tester.getRect(find.byType(Slider)), bar, reason: clock(at));
      }
      expect(
        tester.widget<Text>(label).style?.fontFeatures,
        contains(const FontFeature.tabularFigures()),
      );
    }
    await player.dispose();
  });

  testWidgets('a photo without a motion video has no button for one', (
    tester,
  ) async {
    await pump(tester);
    await open(tester, 0);
    expect(find.byTooltip('Play motion'), findsNothing);
    expect(players.uris, isEmpty);
    await unmount(tester);
  });
}
