import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:photolib/features/library/timeline/pages.dart';
import 'package:photolib/features/library/timeline/pipeline.dart';
import 'package:photolib/features/library/timeline/providers.dart';
import 'package:photolib/features/library/timeline/thumbnails.dart';
import 'package:photolib/features/settings/settings.dart';
import 'package:photolib/features/viewer/animated.dart';
import 'package:photolib/features/viewer/slideshow.dart';
import 'package:photolib/features/viewer/video.dart';
import 'package:photolib/l10n/app_localizations.dart';
import 'package:photolib/ui/theme.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import '../../support/fake_players.dart';
import '../../support/pump_app.dart';
import '../../support/viewer.dart';

/// The slides [order] shows, from its current one, until it ends or [most].
List<int> shown(SlideOrder order, [int most = 100]) => [
  order.current,
  for (var i = 1; i < most && order.forward(); i++) order.current,
];

/// [Grey]'s images, each [delay] after it is asked for, kept to count those
/// not let go.
class Counted extends Grey {
  new([this.delay = Duration.zero]);

  final Duration delay;
  final made = <ui.Image>[];

  int get held => made.where((i) => !i.debugDisposed).length;

  @override
  Future<ui.Image> load(ThumbnailItem item, int tier, Tile tile) async {
    await Future<void>.delayed(delay);
    final image = await super.load(item, tier, tile);
    made.add(image);
    return image;
  }
}

/// [Grey]'s images, but a white one of 30 × 40 for item 1.
class _Portrait extends Grey {
  @override
  Future<ui.Image> load(ThumbnailItem item, int tier, Tile tile) {
    if (item.key != '1') return super.load(item, tier, tile);
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawColor(const Color(0xffffffff), BlendMode.src);
    return Future.value(recorder.endRecording().toImageSync(30, 40));
  }
}

/// An animated image of [frameCount] frames of 100 ms, looping, frame i an
/// image i + 1 pixels wide.
class _Animation implements ui.Codec {
  new(this.frameCount);

  @override
  final int frameCount;
  var _decoded = 0;
  bool disposed = false;

  @override
  int get repetitionCount => -1;

  @override
  Future<ui.FrameInfo> getNextFrame() async {
    final recorder = ui.PictureRecorder();
    Canvas(recorder);
    final width = _decoded++ % frameCount + 1;
    return _Frame(recorder.endRecording().toImageSync(width, 1));
  }

  @override
  void dispose() => disposed = true;
}

class _Frame implements ui.FrameInfo {
  new(this.image);

  @override
  Duration get duration => const Duration(milliseconds: 100);

  @override
  final ui.Image image;
}

/// A slideshow of [count] slides over [items] files `<n>.jpg`, or `<n>.mp4`
/// for [video]s, run as [slideshow] says, with play-over as [mixAudio] says,
/// opened over a blank page; what it returns completes with the position it
/// closes on. What it asks of the screen's sleep goes to [awake].
Future<Completer<int?>> pumpSlideshow(
  WidgetTester tester, {
  int count = 4,
  int? items,
  int start = 0,
  int Function(int slide)? at,
  Size size = const Size(800, 600),
  bool Function(int p)? video,
  Slideshow slideshow = (seconds: 5, shuffle: false, loop: false),
  bool reduced = false,
  ThumbnailPipeline? pipeline,
  List<bool>? awake,
  List<Override> overrides = const [],
  bool settle = true,
  bool mixAudio = false,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  late BuildContext launcher;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        thumbnailPipelineProvider.overrideWith(
          (ref) async => pipeline ?? Grey(),
        ),
        settingsStoreProvider.overrideWithValue(MemoryStore()),
        keepAwakeProvider.overrideWithValue(
          ({required enable}) async => awake?.add(enable),
        ),
        ...overrides,
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: appTheme(Brightness.light),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
          child: child!,
        ),
        home: Builder(
          builder: (context) {
            launcher = context;
            return const SizedBox.expand();
          },
        ),
      ),
    ),
  );
  ProviderScope.containerOf(launcher).read(settingsProvider.notifier)
    ..setSlideshow(
      seconds: slideshow.seconds,
      shuffle: slideshow.shuffle,
      loop: slideshow.loop,
    )
    ..setToggle(Toggle.mixAudio, on: mixAudio);
  await tester.pump();
  final closed = Completer<int?>();
  final shown = SlideshowPage.show(
    launcher,
    SlideshowPage(
      pages: TimelinePages(
        (first, n) async => [
          for (var p = first; p < min(items ?? count, first + n); p++)
            if (video?.call(p) ?? false)
              ThumbnailItem('$p', Uri.file('/p/$p.mp4'), video: true)
            else
              ThumbnailItem('$p', Uri.file('/p/$p.jpg')),
        ],
      ),
      count: count,
      start: start,
      at: at,
    ),
  );
  unawaited(shown.then(closed.complete));
  await tester.pump();
  if (settle) await tester.pumpAndSettle();
  return closed;
}

Finder slide(int p) => find.byKey(ValueKey('slide $p'));

/// The positions of the items on screen, the one shown last.
List<int> onScreen(WidgetTester tester) => [
  for (final w in tester.widgetList(
    find.byWidgetPredicate(
      (w) => '${w.key}'.startsWith("[<'slide "),
      skipOffstage: false,
    ),
  ))
    int.parse(RegExp(r'\d+').firstMatch('${w.key}')![0]!),
];

/// How opaque the item at [p] is.
double opacity(WidgetTester tester, int p) => tester
    .widget<FadeTransition>(
      find.ancestor(of: slide(p), matching: find.byType(FadeTransition)).first,
    )
    .opacity
    .value;

void main() {
  late FakePlayers players;
  setUp(() => VideoPlayerPlatform.instance = players = FakePlayers());

  group('SlideOrder', () {
    test('in order, from the start to the last', () {
      expect(shown(SlideOrder(5, start: 2)), [2, 3, 4]);
    });

    test('looping, starts over at the first', () {
      expect(shown(SlideOrder(3, start: 1, loop: true), 7), [
        1,
        2,
        0,
        1,
        2,
        0,
        1,
      ]);
    });

    test('shuffled, starts at the start and shows every slide once', () {
      for (var seed = 0; seed < 50; seed++) {
        final slides = shown(SlideOrder(9, start: 4, shuffle: true));
        expect(slides.first, 4);
        expect(slides..sort(), List.generate(9, (s) => s));
      }
      final orders = {
        for (var seed = 0; seed < 20; seed++)
          shown(SlideOrder(9, start: 4, shuffle: true, random: Random(seed)))
              .join(','),
      };
      expect(orders.length, greaterThan(15), reason: 'random, not fixed');
    });

    test('shuffled and looping, each pass shows every slide once, anew, '
        'never the last one shown twice in a row', () {
      for (var seed = 0; seed < 200; seed++) {
        final order = SlideOrder(
          4,
          start: 0,
          shuffle: true,
          loop: true,
          random: Random(seed),
        );
        final slides = shown(order, 40);
        for (var pass = 0; pass < 10; pass++) {
          expect(slides.sublist(pass * 4, pass * 4 + 4)..sort(), [0, 1, 2, 3]);
        }
        for (var i = 1; i < slides.length; i++) {
          expect(slides[i], isNot(slides[i - 1]), reason: 'seed $seed');
        }
      }
    });

    test('a single slide loops on itself', () {
      expect(shown(SlideOrder(1, start: 0, shuffle: true, loop: true), 3), [
        0,
        0,
        0,
      ]);
      expect(shown(SlideOrder(1, start: 0)), [0]);
    });

    test('next is where forward moves, and back returns within a pass', () {
      final order = SlideOrder(5, start: 0, shuffle: true, loop: true);
      final seen = [order.current];
      for (var i = 0; i < 12; i++) {
        final next = order.next;
        expect(order.forward(), isTrue);
        expect(order.current, next);
        seen.add(order.current);
      }
      // 12 forward of 5 a pass: the third pass's third slide.
      expect(order.back(), isTrue);
      expect(order.current, seen[11]);
      expect(order.back(), isTrue);
      expect(order.current, seen[10]);
      expect(order.back(), isFalse, reason: 'the start of a pass');
      expect(order.current, seen[10]);
      final first = SlideOrder(3, start: 1);
      expect(first.back(), isFalse);
      expect(first.current, 1);
    });
  });

  group('SlideshowPage', () {
    testWidgets('shows each item for the interval, fades into the next, '
        'keeps the screen on and closes after the last', (tester) async {
      final awake = <bool>[];
      final closed = await pumpSlideshow(tester, count: 3, awake: awake);
      expect(onScreen(tester), [0]);
      expect(awake, [true]);
      await tester.pump(const Duration(seconds: 4));
      expect(onScreen(tester), [0]);
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(milliseconds: 300));
      expect(onScreen(tester), [0, 1], reason: 'the first under the next');
      expect(opacity(tester, 1), inExclusiveRange(0, 1));
      await tester.pumpAndSettle();
      expect(onScreen(tester), [1]);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(onScreen(tester), [2]);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(find.byType(SlideshowPage), findsNothing);
      expect(await closed.future, 2);
      expect(awake, [true, false]);
    });

    testWidgets('where the next item has no picture, the one before fades '
        'out as it fades in', (tester) async {
      await pumpSlideshow(tester, count: 2, pipeline: _Portrait());
      await tester.pump(const Duration(seconds: 5));
      await tester.pump(const Duration(milliseconds: 300));
      final image = await captureImage(
        tester.element(find.byType(SlideshowPage)),
      );
      final bytes = (await tester.runAsync(image.toByteData))!;
      // The first's grey, 40 × 30 across 800 × 600, beside the second's
      // white of 30 × 40 in the middle.
      final red = bytes.getUint8((300 * 800 + 20) * 4);
      expect(red, inExclusiveRange(10, 118), reason: 'grey 128 fading');
      image.dispose();
    });

    testWidgets('under reduce motion, the next item shows at once', (
      tester,
    ) async {
      await pumpSlideshow(tester, reduced: true);
      await tester.pump(const Duration(seconds: 5));
      await tester.pump();
      expect(onScreen(tester), [1]);
      expect(opacity(tester, 1), 1);
    });

    testWidgets('looping, starts over after the last item', (tester) async {
      await pumpSlideshow(
        tester,
        count: 3,
        slideshow: (seconds: 2, shuffle: false, loop: true),
      );
      final seen = [...onScreen(tester)];
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(seconds: 2));
        await tester.pumpAndSettle();
        seen.addAll(onScreen(tester));
      }
      expect(seen, [0, 1, 2, 0, 1, 2]);
    });

    testWidgets('shuffled, shows every item once in a random order', (
      tester,
    ) async {
      final closed = await pumpSlideshow(
        tester,
        count: 20,
        slideshow: (seconds: 1, shuffle: true, loop: false),
      );
      final seen = [...onScreen(tester)];
      for (var i = 0; !closed.isCompleted && i < 40; i++) {
        await tester.pump(const Duration(seconds: 1));
        await tester.pumpAndSettle();
        if (!closed.isCompleted) seen.addAll(onScreen(tester));
      }
      expect(seen.first, 0);
      expect([...seen]..sort(), List.generate(20, (p) => p));
      expect(seen, isNot(List.generate(20, (p) => p)));
    });

    testWidgets('the slides of a selection are its items', (tester) async {
      final closed = await pumpSlideshow(
        tester,
        count: 2,
        items: 10,
        at: (slide) => [5, 9][slide],
        slideshow: (seconds: 1, shuffle: false, loop: false),
      );
      expect(onScreen(tester), [5]);
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(onScreen(tester), [9]);
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(await closed.future, 9);
    });

    testWidgets('the interval is any number of seconds, kept in the '
        'settings, and shuffle and repeat are switched in the options', (
      tester,
    ) async {
      await pumpSlideshow(tester, count: 3);
      await tester.tap(find.byTooltip('Slideshow options'));
      await tester.pumpAndSettle();
      expect(
        Theme.of(tester.element(find.text('Shuffle'))).brightness,
        Brightness.dark,
        reason: "the slideshow's",
      );
      await tester.enterText(find.byType(TextField), '17');
      await tester.pump(const Duration(seconds: 16));
      expect(onScreen(tester), [0], reason: 'timed anew');
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(milliseconds: 300));
      expect(onScreen(tester), [0, 1]);
      await tester.tap(find.text('Repeat'));
      await tester.pumpAndSettle();
      final settings = ProviderScope.containerOf(
        tester.element(find.byType(SlideshowPage)),
      ).read(settingsProvider).slideshow;
      expect(settings, (seconds: 17, shuffle: false, loop: true));
      await tester.tapAt(const Offset(400, 20));
      await tester.pumpAndSettle();
      for (final p in [2, 0]) {
        await tester.pump(const Duration(seconds: 17));
        await tester.pumpAndSettle();
        expect(onScreen(tester), [p]);
      }
    });

    testWidgets('Space pauses and plays, the arrows step and Escape closes', (
      tester,
    ) async {
      final closed = await pumpSlideshow(tester);
      await tester.pressKey(LogicalKeyboardKey.space);
      expect(find.byTooltip('Play'), findsOneWidget);
      await tester.pump(const Duration(seconds: 30));
      await tester.pumpAndSettle();
      expect(onScreen(tester), [0]);
      await tester.pressKey(LogicalKeyboardKey.arrowRight);
      expect(onScreen(tester), [1]);
      await tester.pressKey(LogicalKeyboardKey.arrowRight);
      await tester.pressKey(LogicalKeyboardKey.arrowLeft);
      expect(onScreen(tester), [1]);
      await tester.pressKey(LogicalKeyboardKey.space);
      expect(find.byTooltip('Pause'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(onScreen(tester), [2]);
      await tester.pressKey(LogicalKeyboardKey.escape);
      expect(await closed.future, 2);
    });

    testWidgets('a video, its player made before its turn, plays to its '
        'end and pauses with the slideshow, then the next item shows', (
      tester,
    ) async {
      await pumpSlideshow(tester, count: 3, video: (p) => p == 1);
      expect(players.uris, ['file:///p/1.mp4'], reason: 'made ahead');
      expect(players.calls, isNot(contains('play 0')));
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(onScreen(tester), [1]);
      expect(players.calls, contains('play 0'));
      expect(find.byKey(const ValueKey('player 0')), findsOneWidget);
      await tester.pump(const Duration(seconds: 60));
      await tester.pumpAndSettle();
      expect(onScreen(tester), [1], reason: 'a video plays to its end');
      players.calls.clear();
      await tester.pressKey(LogicalKeyboardKey.space);
      await tester.pressKey(LogicalKeyboardKey.space);
      expect(players.calls.where((c) => !c.startsWith('speed')), [
        'pause 0',
        'play 0',
      ], reason: 'no rewind');
      players.complete(0);
      await tester.pumpAndSettle();
      expect(onScreen(tester), [2]);
    });

    for (final mix in [false, true]) {
      testWidgets('a video with sound plays over other audio only when set '
          'to (${mix ? 'set' : 'not set'})', (tester) async {
        await pumpSlideshow(
          tester,
          count: 2,
          video: (p) => p == 1,
          mixAudio: mix,
        );
        expect(players.mixes, [mix]);
      });
    }

    testWidgets('paused before its video can play, the slideshow keeps it '
        'still, and what it steps to too, until Space', (tester) async {
      await pumpSlideshow(
        tester,
        count: 3,
        video: (p) => p != 1,
        settle: false,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(players.uris, ['file:///p/0.mp4']);
      expect(players.calls.where((c) => c.startsWith('play')), isEmpty);
      await tester.pressKey(LogicalKeyboardKey.arrowRight);
      await tester.pressKey(LogicalKeyboardKey.arrowRight);
      expect(onScreen(tester), [2]);
      expect(players.calls.where((c) => c.startsWith('play')), isEmpty);
      await tester.pressKey(LogicalKeyboardKey.space);
      expect(players.calls, contains('play 1'));
    });

    testWidgets('a video that cannot play says so for the interval', (
      tester,
    ) async {
      VideoPlayerPlatform.instance = players = FakePlayers(failing: {'1.mp4'});
      await pumpSlideshow(tester, count: 3, video: (p) => p == 1);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(
        find.text('This video cannot play on this device'),
        findsOneWidget,
      );
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(onScreen(tester), [2]);
    });

    for (final reduced in [false, true]) {
      testWidgets('a motion photo plays its video once shown'
          '${reduced ? ', not under reduce motion' : ''}', (tester) async {
        await pumpSlideshow(
          tester,
          reduced: reduced,
          overrides: [
            motionClipProvider.overrideWith(
              (ref, item) async => File('/c/${item.key}.mp4'),
            ),
          ],
        );
        await tester.pumpAndSettle();
        expect(players.uris, reduced ? isEmpty : ['file:///c/0.mp4']);
        expect(players.calls, reduced ? isEmpty : contains('play 0'));
      });

      testWidgets('an animated image plays while shown and stands still '
          'while paused${reduced ? ', under reduce motion too' : ''}; one '
          'that fails to open shows its picture', (tester) async {
        final animation = _Animation(3);
        await pumpSlideshow(
          tester,
          reduced: reduced,
          settle: false,
          overrides: [
            animationProvider.overrideWithValue(
              (item) async => item.key == '0'
                  ? animation
                  : throw const FormatException('damaged'),
            ),
          ],
        );
        int width([int p = 0]) => tester
            .widget<RawImage>(
              find.descendant(of: slide(p), matching: find.byType(RawImage)),
            )
            .image!
            .width;
        final widths = <int>{};
        await tester.pump();
        for (var i = 0; i < 8; i++) {
          await tester.pump(const Duration(milliseconds: 100));
          widths.add(width());
        }
        expect(widths, containsAll([1, 2, 3]));
        await tester.pressKey(LogicalKeyboardKey.space);
        final still = width();
        await tester.pump(const Duration(seconds: 1));
        expect(width(), still);
        await tester.pressKey(LogicalKeyboardKey.arrowRight);
        expect(onScreen(tester), [1]);
        expect(animation.disposed, isTrue);
        expect(width(1), 40, reason: "Grey's");
      });
    }

    for (final size in const [
      Size(1280, 800),
      Size(800, 1280),
      Size(844, 390),
      Size(390, 844),
    ]) {
      testWidgets('fits the item and its controls on a screen of $size', (
        tester,
      ) async {
        await pumpSlideshow(tester, size: size);
        final image = tester.getRect(
          find.descendant(of: slide(0), matching: find.byType(RawImage)),
        );
        expect(image, Offset.zero & size);
        for (final control in [
          'Previous',
          'Pause',
          'Next',
          'Slideshow options',
          'Close',
        ]) {
          final rect = tester.getRect(find.byTooltip(control));
          expect((Offset.zero & size).intersect(rect), rect, reason: control);
        }
        await tester.tap(find.byTooltip('Next'));
        await tester.pumpAndSettle();
        expect(onScreen(tester), [1]);
      });
    }

    testWidgets('1,000 mixed items: each shows for its interval, never '
        'without its image, three images at most held, all let go at the '
        'end', (tester) async {
      final images = Counted(const Duration(milliseconds: 300));
      final closed = await pumpSlideshow(
        tester,
        count: 1000,
        video: (p) => p % 10 == 3,
        pipeline: images,
        slideshow: (seconds: 1, shuffle: false, loop: false),
      );
      const step = Duration(milliseconds: 100);
      var (now, shown, since, most) = (Duration.zero, 0, Duration.zero, 0);
      final longest = <String, Duration>{};
      while (!closed.isCompleted && now < const Duration(minutes: 30)) {
        await tester.pump(step);
        now += step;
        most = max(most, images.held);
        final screen = onScreen(tester);
        for (final p in screen) {
          expect(
            find.descendant(of: slide(p), matching: find.byType(RawImage)),
            findsOneWidget,
            reason: 'item $p at $now',
          );
        }
        if (screen.isNotEmpty && screen.last != shown) {
          final kind = shown % 10 == 3 ? 'video' : 'photo';
          if (now - since > (longest[kind] ?? Duration.zero)) {
            longest[kind] = now - since;
          }
          (shown, since) = (screen.last, now);
        }
        // A video plays 2 s.
        if (shown % 10 == 3 && now - since == const Duration(seconds: 2)) {
          players.complete(players.uris.lastIndexOf('file:///p/$shown.mp4'));
        }
      }
      expect(shown, 999);
      // A photo's 1 s from its fade's end, the fade's 600 ms from the frame
      // after the step, and a video until its end: never the 300 ms an
      // image takes, which came before its turn.
      expect(longest, {
        'photo': const Duration(milliseconds: 1000 + 600 + 100),
        'video': const Duration(milliseconds: 2000 + 100),
      });
      expect(most, lessThanOrEqualTo(3));
      await tester.pumpAndSettle();
      expect(images.made.where((i) => !i.debugDisposed), isEmpty);
    });
  });

  testWidgets('the viewer plays its items from the one shown, pausing its '
      'video meanwhile, and shows the last one it played after', (
    tester,
  ) async {
    final position = await pumpViewer(
      tester,
      size: const Size(800, 600),
      at: 1,
      video: (p) => p == 1,
      settings: const Settings(toggles: {Toggle.autoplay: true}),
    );
    expect(players.calls, contains('play 0'));
    await tester.pressKey(LogicalKeyboardKey.keyS, character: 's');
    expect(onScreen(tester), [1]);
    expect(players.calls, containsAllInOrder(['pause 0', 'play 1']));
    // video_player sets a player's speed after each play.
    expect(
      players.calls.where((c) => !c.startsWith('speed')).last,
      'play 1',
      reason: "the slideshow's own",
    );
    await tester.pressKey(LogicalKeyboardKey.arrowRight);
    await tester.pressKey(LogicalKeyboardKey.arrowRight);
    await tester.pressKey(LogicalKeyboardKey.escape);
    expect(find.byType(SlideshowPage), findsNothing);
    expect(position.value, 3);
    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Slideshow'));
    await tester.pumpAndSettle();
    expect(onScreen(tester), [3]);
  });
}
