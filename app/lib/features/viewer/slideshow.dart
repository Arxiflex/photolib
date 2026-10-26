import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:photolib/core/logging.dart';
import 'package:photolib/features/library/timeline/pages.dart';
import 'package:photolib/features/library/timeline/pipeline.dart';
import 'package:photolib/features/library/timeline/providers.dart';
import 'package:photolib/features/library/timeline/thumbnail_at.dart';
import 'package:photolib/features/library/timeline/thumbnails.dart';
import 'package:photolib/features/offline/offline.dart';
import 'package:photolib/features/servers/servers.dart';
import 'package:photolib/features/settings/settings.dart';
import 'package:photolib/features/viewer/animated.dart';
import 'package:photolib/features/viewer/video.dart';
import 'package:photolib/features/viewer/viewer_page.dart';
import 'package:photolib/l10n/app_localizations.dart';
import 'package:photolib/ui/commands.dart';
import 'package:photolib/ui/motion.dart';
import 'package:photolib/ui/theme.dart';
import 'package:photolib/ui/tokens.dart';
import 'package:video_player/video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// The order a slideshow shows [count] slides in (VIEW-21): from the start to
/// the last, or with [shuffle] the start then the others at random, each
/// once; with [loop] every slide again after that, shuffled anew when
/// shuffling, never the slide just shown first.
class SlideOrder {
  /// An order of [count] slides, one at least.
  new(
    this.count, {
    required int start,
    this.shuffle = false,
    this.loop = false,
    Random? random,
  }) : _random = random ?? Random() {
    _pass = _passFrom(start);
  }

  /// How many slides there are.
  final int count;

  /// Whether at random.
  final bool shuffle;

  /// Whether every slide again after the last.
  final bool loop;

  final Random _random;
  late Int32List _pass;
  Int32List? _upcoming;
  var _i = 0;

  /// The slide shown.
  int get current => _pass[_i];

  /// The slide [forward] moves to, or null at the end.
  int? get next {
    if (_i + 1 < _pass.length) return _pass[_i + 1];
    if (!loop) return null;
    return (_upcoming ??= _passFrom(null)).first;
  }

  /// Moves to the [next] slide; false at the end.
  bool forward() {
    if (_i + 1 < _pass.length) {
      _i++;
      return true;
    }
    if (!loop) return false;
    _pass = _upcoming ?? _passFrom(null);
    _upcoming = null;
    _i = 0;
    return true;
  }

  /// Moves back to the slide shown before in this pass; false at its start.
  bool back() {
    if (_i == 0) return false;
    _i--;
    return true;
  }

  /// A pass over the slides from [first], or over all after another pass.
  Int32List _passFrom(int? first) {
    final from = shuffle ? 0 : first ?? 0;
    final pass = Int32List(count - from);
    for (var i = 0; i < pass.length; i++) {
      pass[i] = from + i;
    }
    if (!shuffle) return pass;
    for (var i = count - 1; i > 0; i--) {
      _swap(pass, i, _random.nextInt(i + 1));
    }
    // The first slide is the one asked for, or not the one just shown.
    final head = first ?? (count > 1 && pass.first == current ? -1 : null);
    if (head == null) return pass;
    _swap(
      pass,
      0,
      head < 0 ? 1 + _random.nextInt(count - 1) : pass.indexOf(head),
    );
    return pass;
  }
}

void _swap(Int32List list, int i, int j) {
  final t = list[i];
  list[i] = list[j];
  list[j] = t;
}

/// Keeps the screen on, or lets it sleep again.
final Provider<Future<void> Function({required bool enable})>
keepAwakeProvider = Provider((ref) => WakelockPlus.toggle);

const _log = Logger('photolib.slideshow');

/// A slideshow (VIEW-21) of [count] slides from [start], slide i the item
/// [at] says of [pages]: each shows for the seconds of the settings'
/// slideshow once it has faded in over the one before (at once under reduce
/// motion), in their order or shuffled, once or looping; a video plays to its
/// end, a motion or Live Photo plays its video once, an animated image its
/// frames. The next item's image and player are ready before its turn, which
/// waits for them. Space pauses, the arrows step and Escape closes; the
/// screen stays on meanwhile.
class SlideshowPage extends ConsumerStatefulWidget {
  /// A slideshow of [count] slides of [pages].
  const new({
    required this.pages,
    required this.count,
    this.start = 0,
    this.at,
    super.key,
  });

  /// The items.
  final TimelinePages pages;

  /// How many slides there are.
  final int count;

  /// The slide shown first.
  final int start;

  /// The position in [pages] of a slide's item; the slide's own by default.
  final int Function(int slide)? at;

  /// Shows [page] over everything; the future completes with the position
  /// of the item it closes on.
  static Future<int?> show(BuildContext context, SlideshowPage page) =>
      Navigator.of(
        context,
        rootNavigator: true,
      ).push(MaterialPageRoute(builder: (_) => page));

  @override
  ConsumerState<SlideshowPage> createState() => _SlideshowState();
}

class _SlideshowState extends ConsumerState<SlideshowPage>
    with SingleTickerProviderStateMixin {
  static const _fadeTime = Duration(milliseconds: 600);
  late SlideOrder _order = _orderFrom(widget.start);
  // The images of the item fading out, the one shown and the next.
  final _images = <int, ui.Image>{};
  final _failed = <int, Object>{};
  final _loading = <int>{};
  // A slideshow plays each video as it shows.
  late final _players = VideoPlayers()
    ..autoplay = true
    ..mixAudio = ref.read(settingsProvider).isOn(Toggle.mixAudio);
  late final AnimationController _fade = AnimationController(vsync: this)
    ..addStatusListener(_faded);
  late final Future<void> Function({required bool enable}) _keepAwake = ref
      .read(keepAwakeProvider);
  int? _out;
  Timer? _timer;
  Timer? _hide;
  VideoPlayerController? _watched;
  // Whether the item shown has begun to fade in, and its time is up.
  var _entered = false;
  var _due = false;
  var _paused = false;
  var _closed = false;
  var _controls = true;
  // The key of the player paused, which plays on when the slideshow does.
  String? _held;

  Slideshow get _settings => ref.read(settingsProvider).slideshow;

  SlideOrder _orderFrom(int start) => SlideOrder(
    widget.count,
    start: start,
    shuffle: _settings.shuffle,
    loop: _settings.loop,
  );

  int _positionOf(int slide) => widget.at?.call(slide) ?? slide;

  int get _at => _positionOf(_order.current);

  int? get _next => switch (_order.next) {
    final n? => _positionOf(n),
    null => null,
  };

  ThumbnailItem? _item(int p) => widget.pages[p] as ThumbnailItem?;

  bool _ready(int p) => _images.containsKey(p) || _failed.containsKey(p);

  @override
  void initState() {
    super.initState();
    widget.pages.addListener(_load);
    _players.addListener(_watch);
    _awake(on: true);
    _poke();
    _log.info(
      'slideshow',
      fields: {
        'slides': widget.count,
        'seconds': _settings.seconds,
        'shuffle': _settings.shuffle,
        'loop': _settings.loop,
      },
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _load();
  }

  @override
  void dispose() {
    widget.pages.removeListener(_load);
    _timer?.cancel();
    _hide?.cancel();
    _watched?.removeListener(_ended);
    _players.dispose();
    _fade.dispose();
    for (final image in _images.values) {
      image.dispose();
    }
    _awake(on: false);
    super.dispose();
  }

  void _awake({required bool on}) => unawaited(
    _keepAwake(
      enable: on,
    ).catchError((Object e) => _log.warning('the screen may sleep', error: e)),
  );

  /// Keeps the images of the items fading out, shown and next, loading
  /// those it has not.
  void _load() {
    final keep = {?_out, _at, ?_next};
    for (final p in [..._images.keys]) {
      if (!keep.contains(p)) _images.remove(p)?.dispose();
    }
    _failed.removeWhere((p, _) => !keep.contains(p));
    final tier = screenTier(context);
    for (final p in keep) {
      final item = _item(p);
      if (item == null || _ready(p) || !_loading.add(p)) continue;
      unawaited(
        ref
            .read(thumbnailPipelineProvider.future)
            .then((pipeline) => pipeline.load(item, tier, Tile()))
            .then(
              (image) {
                _loading.remove(p);
                if (!mounted || !{?_out, _at, ?_next}.contains(p)) {
                  return image.dispose();
                }
                setState(() => _images[p] = image);
                _landed(p);
              },
              onError: (Object error) {
                _log.warning(
                  'no slide image',
                  fields: {'file': '$item'},
                  error: error,
                );
                _loading.remove(p);
                if (!mounted) return;
                setState(() => _failed[p] = error);
                _landed(p);
              },
            ),
      );
    }
  }

  void _landed(int p) {
    if (p == _at && !_entered) {
      _enter();
    } else if (p == _next && _due && !_paused) {
      _advance();
    }
  }

  /// Fades the item shown in, now that its image is here.
  void _enter() {
    _entered = true;
    _fade
      ..duration = Motion.of(context, _fadeTime)
      ..forward(from: 0);
    _watch();
  }

  /// Once the item shown has faded in, drops the one before and starts its
  /// time.
  void _faded(AnimationStatus status) {
    _players.still = !status.isAnimating;
    if (!status.isCompleted) return;
    if (_out != null) {
      setState(() => _out = null);
      _load();
    }
    _start();
  }

  /// Times the item shown once it has faded in, unless it is a video, which
  /// plays to its end.
  void _start() {
    _timer?.cancel();
    if (_paused || !_entered || !_fade.isCompleted) return;
    final item = _item(_at);
    if (item != null && item.video && !_players.failed(item.key)) return;
    _timer = Timer(Duration(seconds: _settings.seconds), () {
      _due = true;
      _advance();
    });
  }

  /// Watches the player of the video shown for its end.
  void _watch() {
    if (!mounted) return;
    setState(() {});
    final item = _item(_at);
    final player = item != null && item.video ? _players[item.key] : null;
    if (player != _watched) {
      _watched?.removeListener(_ended);
      _watched = player?..addListener(_ended);
    }
    if (item != null && item.video && _players.failed(item.key)) _start();
  }

  void _ended() {
    if (_paused || _due || !(_watched?.value.isCompleted ?? false)) return;
    _due = true;
    _advance();
  }

  /// Shows the next item once its image is here, or closes after the last.
  void _advance() {
    final next = _next;
    if (next == null) return _close();
    if (_ready(next)) _move(forward: true);
  }

  void _move({required bool forward}) {
    final from = _at;
    if (!(forward ? _order.forward() : _order.back())) return;
    _timer?.cancel();
    setState(() {
      if (_entered) _out = from;
      _entered = _due = false;
      _fade.value = 0;
    });
    _load();
    if (_ready(_at)) _enter();
  }

  void _step({required bool forward}) {
    _poke();
    _move(forward: forward);
  }

  void _pause() {
    _poke();
    final key = _playing;
    final player = key == null ? null : _players[key];
    setState(() => _paused = !_paused);
    if (_paused) {
      _held = player == null ? null : key;
      _timer?.cancel();
      unawaited(player?.pause());
    } else if (_due) {
      _advance();
    } else {
      if (player != null && !player.value.isCompleted) {
        unawaited(player.play());
      }
      _start();
    }
  }

  void _close() {
    if (_closed) return;
    _closed = true;
    Navigator.of(context).pop(_at);
  }

  /// Shows the controls for a while; paused, until it plays again.
  void _poke() {
    _hide?.cancel();
    _hide = Timer(const Duration(seconds: 3), () {
      if (mounted && !_paused) setState(() => _controls = false);
    });
    if (!_controls) setState(() => _controls = true);
  }

  /// The key of the player that plays the item shown: its video, or its
  /// motion photo's unless motion is reduced.
  String? get _playing {
    final item = _item(_at);
    if (item == null) return null;
    if (item.video) return item.key;
    if (Motion.reduced(context)) return null;
    return ref.read(motionClipProvider(item)).value == null
        ? null
        : 'motion ${item.key}';
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(settingsProvider.select((s) => s.slideshow), (before, now) {
      if (before?.shuffle != now.shuffle || before?.loop != now.loop) {
        _order = _orderFrom(_order.current);
        _load();
      }
      _start();
    });
    final item = _item(_at);
    final clip = item == null || item.video || Motion.reduced(context)
        ? null
        : ref.watch(motionClipProvider(item)).value;
    final playing = _playing;
    _players.want({
      for (final p in {_at, ?_next})
        if (_item(p) case final v? when v.video)
          v.key: (options) => videoOf(
            v,
            options,
            server: ref.read(serverVideoUrlProvider),
            link: ref.read(sessionProvider),
          ),
      if ((item, clip) case (final item?, final clip?))
        'motion ${item.key}': (options) async =>
            VideoPlayerController.file(clip, videoPlayerOptions: options),
    }, _paused && playing != _held ? null : playing);
    final commands = _commands(AppLocalizations.of(context));
    return Theme(
      data: appTheme(
        Brightness.dark,
        highContrast: MediaQuery.highContrastOf(context),
      ),
      child: PopScope<int>(
        canPop: false,
        onPopInvokedWithResult: (popped, _) => popped ? null : _close(),
        child: Commands(
          commands: commands,
          child: Material(
            color: Colors.black,
            child: MouseRegion(
              onHover: (_) => _poke(),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _tap,
                // Under the slideshow's theme.
                child: Builder(
                  builder: (context) => Stack(
                    fit: StackFit.expand,
                    children: [
                      if (_out case final out?) _slide(out),
                      FadeTransition(opacity: _fade, child: _slide(_at)),
                      if (_controls) ..._chrome(context, commands),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _tap() {
    if (_controls && !_paused) {
      _hide?.cancel();
      setState(() => _controls = false);
    } else {
      _poke();
    }
  }

  List<Command> _commands(AppLocalizations strings) {
    // i18n-ok: the arrow keys follow the reading direction
    final rtl = Directionality.of(context) == TextDirection.rtl;
    // The first three are the buttons below too.
    return [
      Command(
        strings.viewerPrevious,
        () => _step(forward: false),
        shortcut: SingleActivator(
          rtl ? LogicalKeyboardKey.arrowRight : LogicalKeyboardKey.arrowLeft,
        ),
        icon: Icons.skip_previous,
      ),
      Command(
        _paused ? strings.viewerPlay : strings.viewerPause,
        _pause,
        shortcut: const SingleActivator(LogicalKeyboardKey.space),
        icon: _paused ? Icons.play_arrow : Icons.pause,
      ),
      Command(
        strings.viewerNext,
        () => _step(forward: true),
        shortcut: SingleActivator(
          rtl ? LogicalKeyboardKey.arrowLeft : LogicalKeyboardKey.arrowRight,
        ),
        icon: Icons.skip_next,
      ),
      Command(
        MaterialLocalizations.of(context).closeButtonLabel,
        _close,
        shortcut: const SingleActivator(LogicalKeyboardKey.escape),
      ),
    ];
  }

  /// The item at [p]: its image fitted, a video's player over its poster,
  /// a motion photo's while it plays.
  Widget _slide(int p) {
    final item = _item(p);
    final (image, failure) = (_images[p], _failed[p]);
    final player = switch (item) {
      ThumbnailItem(video: true, :final key) => _players[key],
      final ThumbnailItem item when p == _at => _players['motion ${item.key}'],
      _ => null,
    };
    // Opaque, so that the item before fades out where this has no picture.
    return ColoredBox(
      key: ValueKey('slide $p'),
      color: Colors.black,
      child: switch (item) {
        ThumbnailItem(video: true, :final key) => VideoView(
          poster: image,
          player: player,
          failed: _players.failed(key),
          controls: false,
          onTap: _tap,
        ),
        _ => Stack(
          fit: StackFit.expand,
          children: [
            if ((item, image) case (final item?, final image?) when p == _at)
              TickerMode(
                enabled: !_paused,
                child: _Animated(key: ValueKey(item.key), item, image),
              )
            else if (image != null)
              RawImage(image: image, fit: BoxFit.contain)
            else if (failure != null)
              Center(child: FailureMark(failure, size: 64)),
            if (player != null)
              ValueListenableBuilder(
                valueListenable: player,
                builder: (context, v, _) => v.isPlaying
                    ? Center(
                        child: AspectRatio(
                          aspectRatio: v.aspectRatio,
                          child: VideoPlayer(player),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
          ],
        ),
      },
    );
  }

  /// The close button, the item's place and the options above, and the
  /// buttons of the first three [commands] below.
  List<Widget> _chrome(BuildContext context, List<Command> commands) {
    final strings = AppLocalizations.of(context);
    final scrim = Theme.of(context).colorScheme.scrim.withValues(alpha: 0.4);
    return [
      Align(
        alignment: Alignment.topCenter,
        child: ColoredBox(
          color: scrim,
          child: SafeArea(
            bottom: false,
            child: Row(
              children: [
                CloseButton(onPressed: _close),
                Expanded(
                  child: Text(
                    strings.viewerItem(_order.current + 1, widget.count),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.tune),
                  tooltip: strings.slideshowOptions,
                  onPressed: () => _options(context),
                ),
              ],
            ),
          ),
        ),
      ),
      Align(
        alignment: Alignment.bottomCenter,
        child: ColoredBox(
          color: scrim,
          child: SafeArea(
            top: false,
            minimum: EdgeInsets.all(AppTokens.of(context).sm),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              spacing: AppTokens.of(context).sm,
              children: [
                for (final c in commands.take(3))
                  IconButton.filledTonal(
                    icon: Icon(c.icon),
                    tooltip: c.label,
                    onPressed: c.run,
                  ),
              ],
            ),
          ),
        ),
      ),
    ];
  }

  /// The options, in the theme of [context].
  Future<void> _options(BuildContext context) async {
    _hide?.cancel();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _Options(),
    );
    if (mounted) _poke();
  }
}

/// [image], or once [item] opens as an animated image (FMT-13), its frames,
/// which stand still while tickers are off.
class _Animated extends ConsumerStatefulWidget {
  const new(this.item, this.image, {super.key});

  final ThumbnailItem item;
  final ui.Image image;

  @override
  ConsumerState<_Animated> createState() => _AnimatedState();
}

class _AnimatedState extends ConsumerState<_Animated>
    with SingleTickerProviderStateMixin {
  Frames? _frames;
  ui.Image? _frame;

  @override
  void initState() {
    super.initState();
    unawaited(
      ref.read(animationProvider)(widget.item).then(
        (codec) {
          if (codec == null) return;
          if (!mounted) return codec.dispose();
          _frames = Frames(
            codec,
            this,
            (frame) => setState(() {
              _frame?.dispose();
              _frame = frame;
            }),
          );
        },
        onError: (Object error) => _log.warning(
          'no animation',
          fields: {'file': '${widget.item}'},
          error: error,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _frames?.dispose();
    _frame?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      RawImage(image: _frame ?? widget.image, fit: BoxFit.contain);
}

/// The interval, in any number of seconds, shuffle and repeat.
class _Options extends ConsumerWidget {
  const new();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AppLocalizations.of(context);
    final slideshow = ref.watch(settingsProvider).slideshow;
    final settings = ref.read(settingsProvider.notifier);
    final md = AppTokens.of(context).md;
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom + md,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: md),
            child: TextFormField(
              initialValue: '${slideshow.seconds}',
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(5),
              ],
              decoration: InputDecoration(labelText: strings.slideshowSeconds),
              onChanged: (text) {
                if (int.tryParse(text) case final seconds? when seconds > 0) {
                  settings.setSlideshow(seconds: seconds);
                }
              },
            ),
          ),
          SwitchListTile(
            title: Text(strings.slideshowShuffle),
            value: slideshow.shuffle,
            onChanged: (on) => settings.setSlideshow(shuffle: on),
          ),
          SwitchListTile(
            title: Text(strings.slideshowLoop),
            value: slideshow.loop,
            onChanged: (on) => settings.setSlideshow(loop: on),
          ),
        ],
      ),
    );
  }
}
