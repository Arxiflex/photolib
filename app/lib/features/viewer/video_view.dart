import 'dart:async';
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';
import 'package:photolib/features/viewer/sphere.dart';
import 'package:photolib/features/viewer/sphere_frame.dart';
import 'package:photolib/features/viewer/video.dart';
import 'package:photolib/l10n/app_localizations.dart';
import 'package:photolib/l10n/formats.dart';
import 'package:photolib/ui/motion.dart';
import 'package:video_player/video_player.dart';

/// A video in the viewer (VIEW-13, VIEW-14, VIEW-42): its [poster] until its
/// [player] has a first frame, then the player, a play button in the middle
/// while it does not play; its [controls], inside the picture, play and
/// pause, seek showing each frame as the thumb moves, mute and set the
/// speed, and say when the pointer is [onControls] or a menu [onMenu]. A tap
/// anywhere plays or pauses it. A video the platform cannot play, [failed],
/// says so over its poster. A 360° video, of a [sphere], is projected through
/// [view], which gestures move while [turning], its controls the same; while
/// it is [pending], only its poster shows. A player in a platform view shows
/// only while [shown], under its poster until it has played a frame.
class VideoView extends StatefulWidget {
  /// A video's view.
  const new({
    required this.poster,
    required this.player,
    required this.failed,
    required this.controls,
    required this.onTap,
    this.onPlay,
    this.frameRate,
    this.captions,
    this.eye = const Rect.fromLTWH(0, 0, 1, 1),
    this.sphere,
    this.view,
    this.turning = false,
    this.pending = false,
    this.shown = true,
    this.onControls,
    this.onMenu,
    super.key,
  });

  /// Hears the pointer come onto the controls and leave them.
  final ValueChanged<bool>? onControls;

  /// Hears a menu of the controls open and close.
  final ValueChanged<bool>? onMenu;

  /// The frame shown until [player] has one.
  final ui.Image? poster;

  /// The video's player, once it has a first frame.
  final VideoPlayerController? player;

  /// Whether the video could not open or play.
  final bool failed;

  /// Whether the controls show.
  final bool controls;

  /// What a tap on the video does.
  final VoidCallback onTap;

  /// Plays or pauses it, from its buttons; [onTap] unless given.
  final VoidCallback? onPlay;

  /// The video's frames a second, which a frame step moves by.
  final double? frameRate;

  /// Its captions, if any.
  final ClosedCaptionFile? captions;

  /// The part of a flat video's frame that shows: one eye of a stereo one.
  final Rect eye;

  /// Where a 360° video's picture lies on the sphere.
  final Sphere? sphere;

  /// Where a 360° video is seen from.
  final ValueNotifier<SphereView>? view;

  /// Whether gestures turn a 360° video.
  final bool turning;

  /// Whether what says if it is a 360° video is still to come: until then
  /// its player's picture, which might be flat, never shows.
  final bool pending;

  /// Whether it is the item shown.
  final bool shown;

  @override
  State<VideoView> createState() => _VideoViewState();
}

class _VideoViewState extends State<VideoView> {
  // While seeking: where the thumb is, and whether to play on release.
  Duration? _scrub;
  var _resume = false;
  var _captions = true;
  // Whether a platform view's player has played a frame.
  var _drawn = false;

  @override
  void didUpdateWidget(VideoView old) {
    super.didUpdateWidget(old);
    if (widget.player != old.player) _drawn = false;
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final (player, poster) = (widget.player, widget.poster);
    final native = player?.viewType == VideoViewType.platformView;
    final still = poster == null
        ? null
        : _eye(
            poster.width / poster.height,
            RawImage(image: poster, fit: BoxFit.fill),
          );
    return Stack(
      fit: StackFit.expand,
      children: [
        if ((widget.sphere, widget.view) case (final sphere?, final view?))
          SphereVideo(
            player: player,
            poster: poster,
            sphere: sphere,
            view: view,
            onTap: widget.onTap,
            turning: widget.turning,
          )
        else
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onTap,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (!native) ?still,
                if (player != null &&
                    !widget.pending &&
                    (!native || widget.shown))
                  _eye(player.value.aspectRatio, VideoPlayer(player)),
                if ((player, still) case (final player?, final still?)
                    when native)
                  ValueListenableBuilder(
                    valueListenable: player,
                    builder: (context, v, still) => AnimatedOpacity(
                      opacity: (_drawn |= v.position > Duration.zero) ? 0 : 1,
                      duration: Motion.of(context, Motion.short),
                      child: still,
                    ),
                    child: still,
                  ),
              ],
            ),
          ),
        if (widget.failed)
          Center(
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(strings.viewerCannotPlay),
              ),
            ),
          )
        else ...[
          if (player != null)
            ValueListenableBuilder(
              valueListenable: player,
              builder: (context, v, _) => v.isPlaying
                  ? const SizedBox.shrink()
                  : _play(strings, widget.onPlay ?? widget.onTap),
            )
          else if (!widget.pending)
            _play(strings, widget.onPlay ?? widget.onTap),
          if (player != null) _foot(strings, player),
        ],
      ],
    );
  }

  /// The captions and the controls at the foot of [player]'s picture.
  Widget _foot(AppLocalizations strings, VideoPlayerController player) =>
      LayoutBuilder(
        builder: (context, box) => Stack(
          children: [
            Positioned.fromRect(
              rect: widget.sphere != null
                  ? Offset.zero & box.biggest
                  : _picture(player.value.aspectRatio, box.biggest),
              child: Align(
                alignment: AlignmentDirectional.bottomCenter,
                child: ValueListenableBuilder(
                  valueListenable: player,
                  builder: (context, v, _) => Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_captions)
                        if (widget.captions?.captions
                                .where((c) => c.start <= v.position)
                                .where((c) => v.position <= c.end)
                                .firstOrNull
                            case final caption?)
                          _caption(context, caption.text),
                      if (widget.controls)
                        _controls(context, strings, player, v),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      );

  /// Where a picture of [aspectRatio], one eye of it, shows in [box].
  Rect _picture(double aspectRatio, Size box) {
    final eye = widget.eye;
    final fitted = applyBoxFit(
      BoxFit.contain,
      Size(aspectRatio * eye.width / eye.height, 1),
      box,
    ).destination;
    return Alignment.center.inscribe(fitted, Offset.zero & box);
  }

  /// The 76 dp button in the middle that plays the video, [onTap].
  Widget _play(AppLocalizations strings, VoidCallback onTap) => Center(
    child: IconButton.filled(
      key: const ValueKey('video-play'),
      tooltip: strings.viewerPlay,
      iconSize: 44,
      style: IconButton.styleFrom(
        fixedSize: const Size.square(76),
        backgroundColor: Colors.black54,
        foregroundColor: Colors.white,
      ),
      onPressed: onTap,
      icon: const Icon(Icons.play_arrow),
    ),
  );

  /// A caption's [text], its markup left out, on a scrim.
  Widget _caption(BuildContext context, String text) => Padding(
    padding: const EdgeInsets.all(16),
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.scrim.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Text(
          text.replaceAll(RegExp('<[^>]*>'), ''),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleLarge
              ?.copyWith(color: Colors.white),
        ),
      ),
    ),
  );

  /// The eye of a [frame] of [aspectRatio] that shows, as large as fits.
  Widget _eye(double aspectRatio, Widget frame) {
    final eye = widget.eye;
    return Center(
      child: AspectRatio(
        aspectRatio: aspectRatio * eye.width / eye.height,
        child: ClipRect(
          child: LayoutBuilder(
            builder: (context, box) {
              final w = box.maxWidth / eye.width;
              final h = box.maxHeight / eye.height;
              return Stack(
                children: [
                  // i18n-ok: the frame lies as its picture does
                  Positioned(
                    left: -eye.left * w,
                    top: -eye.top * h,
                    width: w,
                    height: h,
                    child: frame,
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _controls(
    BuildContext context,
    AppLocalizations strings,
    VideoPlayerController player,
    VideoPlayerValue v,
  ) {
    final scrim = Theme.of(context).colorScheme.scrim;
    return MouseRegion(
      key: const ValueKey('video-controls'),
      onEnter: (_) => widget.onControls?.call(true),
      onExit: (_) => widget.onControls?.call(false),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [scrim.withValues(alpha: 0), scrim.withValues(alpha: 0.6)],
          ),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _seekBar(strings, player, v),
              _buttons(strings, player, v),
            ],
          ),
        ),
      ),
    );
  }

  Widget _seekBar(
    AppLocalizations strings,
    VideoPlayerController player,
    VideoPlayerValue v,
  ) {
    final at = _scrub ?? v.position;
    final end = v.duration.inMilliseconds.toDouble();
    return Slider(
      label: strings.viewerSeek,
      semanticFormatterCallback: (ms) =>
          clock(Duration(milliseconds: ms.round())),
      max: end,
      value: at.inMilliseconds.clamp(0, end).toDouble(),
      onChangeStart: (_) {
        _resume = v.isPlaying;
        unawaited(player.pause());
      },
      onChanged: (ms) {
        final to = Duration(milliseconds: ms.round());
        setState(() => _scrub = to);
        unawaited(player.seekTo(to));
      },
      onChangeEnd: (ms) async {
        await player.seekTo(Duration(milliseconds: ms.round()));
        if (_resume) await player.play();
        if (mounted) setState(() => _scrub = null);
      },
    );
  }

  /// Play or pause, the time, mute, captions and the speed.
  Widget _buttons(
    AppLocalizations strings,
    VideoPlayerController player,
    VideoPlayerValue v,
  ) {
    final formats = Formats(strings);
    const figures = TextStyle(fontFeatures: [FontFeature.tabularFigures()]);
    final duration = Text(clock(v.duration), style: figures);
    return Row(
      children: [
        IconButton(
          icon: Icon(v.isPlaying ? Icons.pause : Icons.play_arrow),
          tooltip: v.isPlaying ? strings.viewerPause : strings.viewerPlay,
          onPressed: widget.onPlay ?? widget.onTap,
        ),
        // As wide as the duration, the most the position reaches, so that
        // nothing after it moves; smaller where the picture is narrow.
        Expanded(
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                children: [
                  Stack(
                    children: [
                      Opacity(opacity: 0, child: duration),
                      Positioned.fill(
                        child: Text(
                          clock(_scrub ?? v.position),
                          key: const ValueKey('video-position'),
                          style: figures,
                          textAlign: TextAlign.end,
                          softWrap: false,
                        ),
                      ),
                    ],
                  ),
                  Text(' / ${clock(v.duration)}', style: figures),
                ],
              ),
            ),
          ),
        ),
        IconButton(
          icon: Icon(v.volume > 0 ? Icons.volume_up : Icons.volume_off),
          tooltip: v.volume > 0 ? strings.viewerMute : strings.viewerUnmute,
          onPressed: player.mute,
        ),
        if (widget.captions != null)
          IconButton(
            icon: const Icon(Icons.closed_caption_off_outlined),
            selectedIcon: const Icon(Icons.closed_caption),
            isSelected: _captions,
            tooltip: strings.viewerCaptions,
            onPressed: () => setState(() => _captions = !_captions),
          ),
        PopupMenuButton<double>(
          icon: const Icon(Icons.speed),
          tooltip: strings.viewerSpeed,
          initialValue: v.playbackSpeed,
          onOpened: () => widget.onMenu?.call(true),
          onCanceled: () => widget.onMenu?.call(false),
          onSelected: (speed) {
            widget.onMenu?.call(false);
            unawaited(player.setPlaybackSpeed(speed));
          },
          itemBuilder: (context) => [
            for (final s in const [1.0, 1.5, 2.0, 0.5])
              PopupMenuItem(value: s, child: Text('${formats.number(s)}×')),
          ],
        ),
      ],
    );
  }
}
