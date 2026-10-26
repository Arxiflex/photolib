part of 'perf_test.dart';

/// Sets of eight 1080p H.264 videos of 4 s with sound, files of [dir] and a
/// folder's items: the viewer opens on the first of a set from the timeline,
/// and each, once it plays for 1 s, is swiped to the next. Cold is a set shown
/// the first time, warm the first set again, each pass over its budget swiped
/// again as [_leastJanky] does, cold over the next set. A frame from a swipe's
/// start, or the viewer's first frame, until the viewer has opened and its
/// pages rest is janky as [_late] counts it; first_frame is the median time
/// from a swipe's start to the end of the first frame with the next video's
/// player in it, the fastest of the passes.
Future<void> _videos(
  WidgetTester tester,
  IntegrationTestWidgetsFlutterBinding binding,
  Replica db,
  Directory dir,
  _Result result,
  TileCipher cipher,
) async {
  const ffmpeg = String.fromEnvironment('PERF_FFMPEG');
  await _videoFiles(db, dir, ffmpeg);
  final cache = await DiskCache.open('${dir.path}/cache', cipher);
  // Linux's posters come from the FFmpeg on PATH; here, the pinned one's.
  final pipeline = Platform.isLinux
      ? ThumbnailPipeline(
          cache: cache,
          decoders: [?await ffmpegPosters(path: ffmpeg)],
          originals: true,
        )
      : await desktopPipeline(cache);
  final thumbnails = Thumbnails(
    (item, tier, cancelled) =>
        pipeline.load(item as ThumbnailItem, tier, cancelled),
  );
  final (buckets, pages) = await libraryTimeline(db).first;
  final position = ValueNotifier(0);
  final key = GlobalKey<TimelineViewState>();
  await tester.pumpWidget(
    _app(
      pipeline,
      db,
      buckets,
      ValueNotifier(pages),
      thumbnails,
      key,
      position: position,
    ),
  );
  await binding.endOfFrame;
  final view = key.currentState!;
  if (!view.mounted) return;
  final swipes = _Swipes(tester, binding, view, pages, position);
  await swipes.until(() => view.visible.$2 >= _Swipes.count - 1);
  for (final (kind, cold) in [('cold', true), ('warm', false)]) {
    final firsts = <double>[];
    await _leastJanky(binding, result, 'video-swipe', '${kind}_janky', (
      attempt,
    ) async {
      final (drawn, first) = await swipes.pass(
        cold ? attempt * _Swipes.count : 0,
      );
      firsts.add(first);
      return drawn;
    }, share: _late);
    final first = firsts.reduce(min);
    stdout.writeln('video-swipe: $_target $kind first frame $first ms');
    result('video-swipe', '${kind}_first_frame', first);
  }
  await tester.pumpWidget(const SizedBox());
}

/// The frames a second the screen shows of a twin of the corpus' 4K 360°
/// sample (compound/sphere/spherical-v2.mp4: 3,840 × 1,920 at 30 fps, H.264),
/// sphere.mp4 of $PERF_FIXTURES, which tools/perf/run.sh makes, played
/// projected full window or [flat]. The twin burns its frame number modulo 8
/// in as the grey of a block where the view looks, which x11grab reads at
/// 60 Hz for 4 s: the rate is that of the changes of number, first to last,
/// rounded, in the fastest of up to five such windows. Meanwhile the test
/// binding draws only the frames the engine asks for, as the app does, not
/// one after each.
Future<double> _sphereFps(WidgetTester tester, {required bool flat}) async {
  final clip = File('${_fixtures.path}/sphere.mp4');
  if (!clip.existsSync()) throw StateError('No ${clip.path}: see run.sh');
  final player = VideoPlayerController.file(clip);
  final view = ValueNotifier(const SphereView(pitch: -56 * pi / 180));
  var opened = false;
  unawaited(player.initialize().then((_) => opened = true));
  final binding = tester.binding as LiveTestWidgetsFlutterBinding;
  final policy = binding.framePolicy;
  try {
    await tester.pumpWidget(
      Localizations(
        locale: const Locale('en'),
        delegates: AppLocalizations.localizationsDelegates,
        child: MediaQuery(
          data: MediaQueryData.fromView(tester.view),
          child: flat
              ? Center(
                  child: AspectRatio(
                    aspectRatio: 2,
                    child: VideoPlayer(player),
                  ),
                )
              : SphereVideo(
                  player: player,
                  poster: null,
                  sphere: const Sphere(),
                  view: view,
                ),
        ),
      ),
    );
    for (var i = 0; i < 200 && !opened; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await player.play();
    await tester.pump(const Duration(seconds: 2));
    binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.benchmark;
    final size = tester.view.physicalSize;
    // The number's middle, (1,920, 1,557) of the frame, contained when flat.
    final scale = min(size.width / 3840, size.height / 1920);
    final y = flat
        ? (size.height - 1920 * scale) / 2 + 1557 * scale
        : size.height / 2;
    final at = '${size.width ~/ 2 - 4},${y.round() - 4}';
    final limit = _limit('sphere-video', flat ? 'flat' : 'fps');
    final fps = await bestOf<double>(
      5,
      (window) async {
        final r = await Process.run(
          '${const String.fromEnvironment('PERF_FFMPEG')}/ffmpeg',
          [
            ...['-nostdin', '-v', 'info', '-hide_banner', '-nostats'],
            ...['-f', 'x11grab', '-framerate', '60', '-video_size', '8x8'],
            ...['-t', '4', '-i', '${Platform.environment['DISPLAY']}+$at'],
            ...['-vf', 'format=gray,showinfo', '-f', 'null', '-'],
          ],
        );
        if (r.exitCode != 0) throw StateError('x11grab: ${r.stderr}');
        // showinfo: each grab's time and mean grey, 36 a frame.
        final changes = <double>[];
        int? last;
        for (final grab in _showinfo.allMatches(r.stderr as String)) {
          final number = (int.parse(grab[2]!) / 36).round() % 8;
          if (number != last) changes.add(double.parse(grab[1]!));
          last = number;
        }
        final rate = (changes.length - 1) / (changes.last - changes.first);
        stdout.writeln(
          'sphere-video window $window: ${rate.toStringAsFixed(1)}',
        );
        return rate;
      },
      max,
      (fps) => fps.roundToDouble() >= limit,
    );
    return fps.roundToDouble();
  } finally {
    binding.framePolicy = policy;
    await tester.pumpWidget(const SizedBox());
    view.dispose();
    await player.dispose();
  }
}

final _showinfo = RegExp(r'pts_time:([\d.]+).*?mean:\[(\d+)');

/// [_Swipes.videos] videos of 4 s, made with [ffmpeg], as files of [dir] and
/// a folder's items of [db].
Future<void> _videoFiles(Replica db, Directory dir, String ffmpeg) async {
  final made = await Process.run('$ffmpeg/ffmpeg', [
    ...'-nostdin -v error -f lavfi -i testsrc2=s=1920x1080:r=30:d=4 -f lavfi '
            '-i sine=r=48000:d=4 -c:v libopenh264 -b:v 8M -c:a aac -shortest '
            '-movflags +faststart'
        .split(' '),
    '${dir.path}/0.mp4',
  ]);
  expect(made.exitCode, 0, reason: '$ffmpeg/ffmpeg: ${made.stderr}');
  for (var i = 1; i < _Swipes.videos; i++) {
    File('${dir.path}/0.mp4').copySync('${dir.path}/$i.mp4');
  }
  await db.customStatement(
    'WITH RECURSIVE n(i) AS (SELECT 0 UNION ALL SELECT i + 1 FROM n '
    'WHERE i < ${_Swipes.videos - 1}) INSERT INTO local_asset (id, source, '
    'volume, source_id, path, mime, size, mtime, taken_local, extracted, '
    "added) SELECT randomblob(16), 'folder', ?, i, i || '.mp4', 'video/mp4', "
    "1, 0, strftime('%Y-%m-%dT%H:%M:%S', 1700000000 - i * 60, 'unixepoch'), "
    '1, 0 FROM n',
    [dir.path],
  );
}

/// Opens the viewer from [view] and swipes through its videos (see
/// [_videos]).
class _Swipes {
  new(this.tester, this.binding, this.view, this.pages, this.position)
    : navigator = Navigator.of(view.context),
      size = view.context.size!;

  /// The videos of a set.
  static const count = 8;

  /// Five sets, a cold attempt's each.
  static const int videos = 5 * count;

  final WidgetTester tester;
  final IntegrationTestWidgetsFlutterBinding binding;
  final TimelineViewState view;
  final TimelinePages pages;
  final ValueNotifier<int> position;
  final NavigatorState navigator;
  final Size size;

  Future<void> until(bool Function() done) =>
      _until(binding, done, timeout: const Duration(seconds: 20));

  VideoPlayerController? player(int i) {
    final key = ValueKey((pages[i]! as ThumbnailItem).key);
    final views = find.byKey(key).evaluate();
    return views.isEmpty ? null : (views.first.widget as VideoView).player;
  }

  /// Whether the viewer shows video [i], opened, its pages at rest.
  bool still(int i) {
    final pages = find.byType(PageView).evaluate();
    if (pages.isEmpty || position.value != i) return false;
    final pager = (pages.first.widget as PageView).controller!;
    return ModalRoute.of(pages.first)!.animation!.isCompleted &&
        !pager.position.isScrollingNotifier.value;
  }

  /// A pass from video [at] on: the frames from each start until the viewer
  /// rests, with what an idle isolate missed meanwhile, and the median time to
  /// the next video's first frame.
  Future<(_Drawn, double)> pass(int at) async {
    final windows = <(int, int)>[];
    final firsts = <double>[];
    final drawn = await _frames(() async {
      view.reveal(at);
      await binding.endOfFrame;
      await _show(
        at,
        0,
        windows,
        firsts,
        () => tester.tapAt(view.cellOf(at).center),
      );
      for (var i = 1; i < count; i++) {
        await Future<void>.delayed(const Duration(seconds: 1));
        await _show(
          at,
          i,
          windows,
          firsts,
          () => tester.flingFrom(
            size.center(Offset.zero),
            Offset(-size.width / 2, 0),
            4000,
          ),
        );
      }
    });
    navigator.pop();
    await until(() => find.byType(ViewerPage).evaluate().isEmpty);
    final shown = [
      for (final f in drawn.frames)
        if (windows.any(
          (w) =>
              f.timestampInMicroseconds(FramePhase.vsyncStart) >= w.$1 &&
              f.timestampInMicroseconds(FramePhase.vsyncStart) <= w.$2,
        ))
          f,
    ];
    expect(shown, isNotEmpty);
    firsts.sort();
    return ((frames: shown, idle: drawn.idle), firsts[firsts.length ~/ 2]);
  }

  // Starts showing video [at] + [i] with [start], adding the frames from then
  // until the viewer rests to [windows] and the time to its first frame to
  // [firsts], then waits until it plays.
  Future<void> _show(
    int at,
    int i,
    List<(int, int)> windows,
    List<double> firsts,
    Future<void> Function() start,
  ) async {
    // The viewer's first frame is its open's (budget `viewer`).
    var from = i == 0 ? null : Timeline.now;
    int? rested;
    final watch = Stopwatch()..start();
    final started = start();
    double? first;
    do {
      await binding.endOfFrame;
      if (find.byType(ViewerPage).evaluate().isNotEmpty) {
        from ??= Timeline.now;
      }
      if (player(at + i) != null) {
        first ??= watch.elapsedMicroseconds / 1000;
      }
      if (still(at + i)) rested ??= Timeline.now;
    } while ((first == null || rested == null) && watch.elapsed.inSeconds < 20);
    await started;
    windows.add((from!, rested ?? Timeline.now));
    if (i > 0) firsts.add(first ?? double.infinity);
    await until(() => player(at + i)?.value.isPlaying ?? false);
    expect(player(at + i)?.value.isPlaying, isTrue, reason: 'at $at+$i');
  }
}

/// The share of [frames] over the display's frame budget, a frame taking the
/// slower of its raster and the time from its vsync to the end of its build,
/// which counts what kept the UI thread from starting it, such as a player
/// made or disposed. On `headless` the UI thread waits for a raster thread
/// that emulates a GPU: there its build alone counts, as in [_times].
double _late(
  IntegrationTestWidgetsFlutterBinding binding,
  List<FrameTiming> frames,
) {
  if (_target == 'headless') return _janky(binding, frames);
  final display = binding.platformDispatcher.views.first.display;
  final budget = 1e6 / max(60, display.refreshRate);
  bool late(FrameTiming f) =>
      f.timestampInMicroseconds(FramePhase.buildFinish) -
              f.timestampInMicroseconds(FramePhase.vsyncStart) >
          budget ||
      f.rasterDuration.inMicroseconds > budget;
  return lateShare(frames, late);
}
