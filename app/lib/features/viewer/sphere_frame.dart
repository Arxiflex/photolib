import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:photolib/core/logging.dart';
import 'package:photolib/features/library/timeline/pipeline.dart';
import 'package:photolib/features/library/timeline/providers.dart';
import 'package:photolib/features/library/timeline/thumbnails.dart';
import 'package:photolib/features/viewer/deep_zoom.dart' show Regions;
import 'package:photolib/features/viewer/regions.dart';
import 'package:photolib/features/viewer/sphere.dart';
import 'package:photolib/features/viewer/sphere_player.dart'
    if (dart.library.js_interop) 'package:photolib/features/viewer/sphere_player_web.dart';
import 'package:photolib/l10n/app_localizations.dart';
import 'package:photolib/ui/adaptive.dart';
import 'package:video_player/video_player.dart';

const _log = Logger('photolib.viewer');

/// [sphere]'s picture through [view] (docs/10-client-app.md §4.4): while
/// [turning], a drag turns it, a pinch or the wheel narrows or widens the
/// lens, always within the picture; otherwise drags page past it. [levels]
/// are its levels of detail, largest first, the shader painting the one
/// [SphereView.level] picks, then [tiles] of a sharper one over it; [over]
/// covers them, as libmpv's projected video does.
class SphereFrame extends StatefulWidget {
  /// A sphere's picture, seen through [view].
  const new({
    required this.sphere,
    required this.view,
    required this.levels,
    this.tiles = const [],
    this.over,
    this.onTap,
    this.turning = false,
    super.key,
  });

  /// Whether gestures turn it, in the viewer's 360° view.
  final bool turning;

  /// Where the picture lies on the sphere.
  final Sphere sphere;

  /// Where it is seen from, which gestures move.
  final ValueNotifier<SphereView> view;

  /// The picture's levels of detail, largest first; none until it loads.
  final List<ui.Image> levels;

  /// Tiles of a sharper level, each a picture of its own part of the sphere.
  final List<(ui.Image, Sphere)> tiles;

  /// What covers the shader's picture, if anything.
  final Widget? over;

  /// What a tap does.
  final VoidCallback? onTap;

  @override
  State<SphereFrame> createState() => _SphereFrameState();
}

class _SphereFrameState extends State<SphereFrame> {
  ui.FragmentShader? _shader;
  ui.FragmentProgram? _program;
  // A shader per tile, as each pass needs its own (Skwasm reads uniforms
  // lazily).
  final _tiles = <ui.Image, ui.FragmentShader>{};
  Size _size = Size.zero;
  double? _fov;

  @override
  void initState() {
    super.initState();
    unawaited(
      sphereProgram.then((p) {
        if (mounted) {
          setState(() {
            _program = p;
            _shader = p.fragmentShader();
          });
        }
      }),
    );
  }

  @override
  void dispose() {
    _shader?.dispose();
    for (final shader in _tiles.values) {
      shader.dispose();
    }
    super.dispose();
  }

  void _move(SphereView v) => widget.view.value = v.clamp(widget.sphere, _size);

  void _drag(ScaleUpdateDetails d) {
    final v = widget.view.value;
    final perPixel = v.fov / min(_size.width, _size.height);
    _move(
      v.copyWith(
        yaw: v.yaw - d.focalPointDelta.dx * perPixel,
        pitch: v.pitch + d.focalPointDelta.dy * perPixel,
        fov: (_fov ?? v.fov) / d.scale,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Semantics(
    label: widget.turning ? AppLocalizations.of(context).viewerSphere : null,
    child: Listener(
      onPointerSignal: (e) {
        if (e is PointerScrollEvent && widget.turning) {
          final v = widget.view.value;
          _move(v.copyWith(fov: v.fov * exp(e.scrollDelta.dy / 400)));
        }
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        // Faces front again.
        onDoubleTap: widget.turning
            ? () => widget.view.value = const SphereView()
            : null,
        onScaleStart: widget.turning
            ? (_) => _fov = widget.view.value.fov
            : null,
        onScaleUpdate: widget.turning ? _drag : null,
        onScaleEnd: widget.turning ? (_) => _fov = null : null,
        child: LayoutBuilder(
          builder: (context, box) {
            _size = box.biggest;
            return ValueListenableBuilder(
              valueListenable: widget.view,
              builder: (context, asked, _) => _paint(context, asked),
            );
          },
        ),
      ),
    ),
  );

  Widget _paint(BuildContext context, SphereView asked) {
    final view = asked.clamp(widget.sphere, _size);
    if (view != asked) {
      // A new viewport, or a sphere seen for the first time.
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => widget.view.value = view,
      );
    }
    final (shader, levels) = (_shader, widget.levels);
    final short =
        min(_size.width, _size.height) * MediaQuery.devicePixelRatioOf(context);
    return Stack(
      fit: StackFit.expand,
      children: [
        if (shader != null && levels.isNotEmpty)
          CustomPaint(
            painter: SpherePainter(
              shader,
              levels[view.level(
                widget.sphere,
                short,
                levels.first.width,
                levels.length,
              )],
              widget.sphere,
              view,
            ),
          ),
        if (_program case final program?)
          for (final (image, part) in widget.tiles)
            CustomPaint(
              painter: SpherePainter(
                _tiles[image] ??= program.fragmentShader(),
                image,
                part,
                view,
              ),
            ),
        ?widget.over,
      ],
    );
  }

  @override
  void didUpdateWidget(SphereFrame old) {
    super.didUpdateWidget(old);
    final shown = {for (final (image, _) in widget.tiles) image};
    _tiles.removeWhere((image, shader) {
      if (shown.contains(image)) return false;
      shader.dispose();
      return true;
    });
  }
}

/// A photo sphere: [base], the viewer's screen-size image, until its picture
/// at up to 8,192 pixels across (4,096 on phones) and that picture's levels
/// of detail have loaded; where a view needs more of a larger original, the
/// 512-pixel tiles in view at the sample it needs (design 08 §7), which the
/// item's regions decode one at a time.
class SpherePhoto extends ConsumerStatefulWidget {
  /// The photo sphere [item].
  const new({
    required this.item,
    required this.base,
    required this.sphere,
    required this.view,
    this.onTap,
    this.turning = false,
    super.key,
  });

  /// The photo.
  final ThumbnailItem item;

  /// Its screen-size image, if any yet.
  final ui.Image? base;

  /// Where its picture lies on the sphere.
  final Sphere sphere;

  /// Where it is seen from.
  final ValueNotifier<SphereView> view;

  /// What a tap does.
  final VoidCallback? onTap;

  /// Whether gestures turn it.
  final bool turning;

  @override
  ConsumerState<SpherePhoto> createState() => _SpherePhotoState();
}

class _SpherePhotoState extends ConsumerState<SpherePhoto> {
  var _levels = <ui.Image>[];
  Regions? _regions;
  Size _viewport = Size.zero;
  // The tiles decoded, by sample, column and row, and the one decoding.
  final _tiles = <(int, int, int), ui.Image>{};
  (int, int, int)? _decoding;
  (int, Set<(int, int)>)? _wanted;

  @override
  void initState() {
    super.initState();
    widget.view.addListener(_want);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_levels.isNotEmpty) return;
    final tier =
        WindowSize.of(MediaQuery.sizeOf(context).width) == WindowSize.compact
        ? 2048
        : 4096;
    unawaited(
      ref
          .read(thumbnailPipelineProvider.future)
          .then((pipeline) => pipeline.load(widget.item, tier, Tile()))
          .then(
            (image) async {
              if (!mounted) return image.dispose();
              setState(() => _levels = levelsOf(image));
              final regions = await ref.read(regionsProvider)(widget.item);
              if (!mounted) return regions?.close();
              _regions = regions;
              _want();
            },
            onError: (Object e) => _log.warning(
              'no sphere picture',
              fields: {'file': '${widget.item}', 'tier': tier},
              error: e,
            ),
          ),
    );
  }

  @override
  void dispose() {
    widget.view.removeListener(_want);
    _regions?.close();
    for (final image in [..._levels, ..._tiles.values]) {
      image.dispose();
    }
    super.dispose();
  }

  /// Decodes the next tile the view wants, and lets go of the others.
  void _want() {
    final regions = _regions;
    if (regions == null || _levels.isEmpty || _viewport.isEmpty) return;
    final wanted = _wanted = widget.view.value
        .clamp(widget.sphere, _viewport)
        .tiles(widget.sphere, _viewport, regions.size, _levels.first.width);
    _tiles.removeWhere((key, image) {
      final (sample, col, row) = key;
      if (wanted != null &&
          sample == wanted.$1 &&
          wanted.$2.contains((col, row))) {
        return false;
      }
      image.dispose();
      return true;
    });
    if (wanted == null || _decoding != null) return setState(() {});
    final (sample, cells) = wanted;
    final next = cells.where((c) => !_tiles.containsKey((sample, c.$1, c.$2)));
    if (next.isEmpty) return setState(() {});
    final (col, row) = next.first;
    final key = _decoding = (sample, col, row);
    final (eye, size) = (widget.sphere.eye, regions.size);
    final part = _tileIn(size, sample, col, row);
    Offset at(Offset f) => Offset(
      (eye.left + f.dx * eye.width) * size.width,
      (eye.top + f.dy * eye.height) * size.height,
    );
    final region = Rect.fromPoints(at(part.topLeft), at(part.bottomRight));
    unawaited(
      regions
          .decode(region, sample)
          .then(
            (image) {
              if (!mounted) return image.dispose();
              _decoding = null;
              _tiles[key] = image;
              _want();
            },
            onError: (Object e) {
              // Another view asks again.
              _decoding = null;
              _log.warning(
                'no sphere tile',
                fields: {'file': '${widget.item}'},
                error: e,
              );
            },
          ),
    );
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final viewport = box.biggest * MediaQuery.devicePixelRatioOf(context);
      if (viewport != _viewport) {
        _viewport = viewport;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _want();
        });
      }
      final (sphere, size) = (widget.sphere, _regions?.size);
      return SphereFrame(
        sphere: sphere,
        view: widget.view,
        levels: _levels.isNotEmpty ? _levels : [?widget.base],
        tiles: [
          if ((_wanted, size) case ((final sample, _), final size?))
            for (final MapEntry(key: (s, col, row), value: image)
                in _tiles.entries)
              if (s == sample)
                (image, sphere.part(_tileIn(size, sample, col, row))),
        ],
        onTap: widget.onTap,
        turning: widget.turning,
      );
    },
  );

  /// Tile [col], [row] at [sample] of an original of [size], as fractions of
  /// the sphere's picture.
  Rect _tileIn(Size size, int sample, int col, int row) {
    final eye = widget.sphere.eye;
    final (w, h) = (size.width * eye.width, size.height * eye.height);
    final tile = 512.0 * sample;
    return Rect.fromLTRB(
      col * tile / w,
      row * tile / h,
      min((col + 1) * tile / w, 1),
      min((row + 1) * tile / h, 1),
    );
  }
}

/// A 360° video, projected wherever it plays (ADR-0146): [poster] through
/// the shader until [player] has frames, then libmpv's own projection on
/// Linux and Windows, the shader filtering the player's texture on Android,
/// iOS and macOS, or its `<video>` element's frames on the web.
class SphereVideo extends StatelessWidget {
  /// A 360° video played by [player].
  const new({
    required this.player,
    required this.poster,
    required this.sphere,
    required this.view,
    this.onTap,
    this.turning = false,
    super.key,
  });

  /// Its player, once it has a first frame.
  final VideoPlayerController? player;

  /// Its poster frame, if any yet.
  final ui.Image? poster;

  /// Where its picture lies on the sphere.
  final Sphere sphere;

  /// Where it is seen from.
  final ValueNotifier<SphereView> view;

  /// What a tap does.
  final VoidCallback? onTap;

  /// Whether gestures turn it.
  final bool turning;

  @override
  Widget build(BuildContext context) {
    SphereFrame frame(ui.Image? image, Widget? over) => SphereFrame(
      sphere: sphere,
      view: view,
      levels: [?(image ?? poster)],
      over: over,
      onTap: onTap,
      turning: turning,
    );
    final player = this.player;
    if (player == null) return frame(null, null);
    return sphereVideo(player, sphere, view, frame);
  }
}
