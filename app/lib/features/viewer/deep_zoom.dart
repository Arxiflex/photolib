import 'dart:math';
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';

/// The sample size of tiles shown at [pixels] device pixels per image pixel:
/// the largest power of two at most 1 / [pixels], so a tile is never coarser
/// than the screen.
int sampleFor(double pixels) {
  var sample = 1;
  while (sample * 2 * pixels <= 1) {
    sample *= 2;
  }
  return sample;
}

/// What [DeepZoom] decodes of an image of [image] pixels, fitted into
/// [viewport] (logical pixels at [dpr]) and seen through [transform]: the
/// sample size and, row by row, the regions in image pixels of the tiles on
/// screen, squares of half the viewport's short side in device pixels
/// (docs/10 §4.1). None while the screen-size image, [base] pixels wide, is
/// as sharp as the screen.
({int sample, List<Rect> tiles}) tilesOnScreen(
  Size image,
  Size viewport,
  double dpr,
  Matrix4 transform,
  double base,
) {
  final fitted = Alignment.center.inscribe(
    applyBoxFit(BoxFit.contain, image, viewport).destination,
    Offset.zero & viewport,
  );
  final scale = fitted.width / image.width;
  final pixels = scale * transform.getMaxScaleOnAxis() * dpr;
  final sample = sampleFor(pixels);
  if (image.width * pixels <= base) return (sample: sample, tiles: const []);
  final seen = MatrixUtils.inverseTransformRect(
    transform,
    Offset.zero & viewport,
  ).shift(-fitted.topLeft);
  final visible = Rect.fromLTRB(
    seen.left / scale,
    seen.top / scale,
    seen.right / scale,
    seen.bottom / scale,
  ).intersect(Offset.zero & image);
  final side = (viewport.shortestSide * dpr / 2).ceilToDouble() * sample;
  return (
    sample: sample,
    tiles: [
      if (!visible.isEmpty)
        for (
          var y = (visible.top / side).floor() * side;
          y < visible.bottom;
          y += side
        )
          for (
            var x = (visible.left / side).floor() * side;
            x < visible.right;
            x += side
          )
            Rect.fromLTRB(
              x,
              y,
              min(x + side, image.width),
              min(y + side, image.height),
            ),
    ],
  );
}

/// An image whose regions decode on their own (docs/10 §4.1): its size in
/// pixels as shown, orientation applied, and a region of it at 1 / sample of
/// its resolution.
abstract interface class Regions {
  Size get size;
  Future<ui.Image> decode(Rect region, int sample);
  void close();
}

/// An image of [size] pixels fitted into its box and seen through
/// [controller]: the screen-size [base] image and, once zoomed past it, the
/// tiles of [tilesOnScreen], which [regions] decodes two at a time, nearest
/// the centre first. A tile stays while on screen at the current sample size;
/// one of another size only until the tiles over it arrive, so the screen is
/// never blank and memory stays within two screens of tiles.
class DeepZoom extends StatefulWidget {
  const DeepZoom({
    super.key,
    required this.size,
    required this.base,
    required this.controller,
    this.regions,
  });

  final Size size;
  final ui.Image? base;
  final TransformationController controller;
  final Regions? regions;

  @override
  State<DeepZoom> createState() => _DeepZoomState();
}

typedef _Tile = (int sample, Rect region);

class _DeepZoomState extends State<DeepZoom> {
  final _tiles = <_Tile, ui.Image>{};
  final _loading = <_Tile>{}, _failed = <_Tile>{};
  var _wanted = <_Tile>{};

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_update);
  }

  @override
  void didUpdateWidget(DeepZoom old) {
    super.didUpdateWidget(old);
    old.controller.removeListener(_update);
    widget.controller.addListener(_update);
    if (old.regions != widget.regions) _drop(_tiles.keys.toList());
  }

  @override
  void dispose() {
    widget.controller.removeListener(_update);
    _drop(_tiles.keys.toList());
    super.dispose();
  }

  void _drop(List<_Tile> tiles) {
    for (final tile in tiles) {
      _tiles.remove(tile)!.dispose();
    }
  }

  void _update() {
    final regions = widget.regions;
    final box = context.findRenderObject() as RenderBox?;
    if (regions == null || box == null || !box.hasSize) return;
    final (:sample, :tiles) = tilesOnScreen(
      widget.size,
      box.size,
      View.of(context).devicePixelRatio,
      widget.controller.value,
      widget.base?.width.toDouble() ?? 0,
    );
    final centre = tiles.isEmpty
        ? Offset.zero
        : Rect.fromPoints(tiles.first.topLeft, tiles.last.bottomRight).center;
    double away(Rect r) => (r.center - centre).distanceSquared;
    _wanted = {
      for (final t
          in tiles.toList()..sort((a, b) => away(a).compareTo(away(b))))
        (sample, t),
    };
    final stale = [
      for (final tile in _tiles.keys)
        if (tile.$1 == sample
            ? !_wanted.contains(tile)
            : !_wanted.any(
                (w) => w.$2.overlaps(tile.$2) && !_tiles.containsKey(w),
              ))
          tile,
    ];
    if (stale.isNotEmpty) setState(() => _drop(stale));
    for (final tile in _wanted) {
      if (_loading.length >= 2) break;
      if (_tiles.containsKey(tile) ||
          _failed.contains(tile) ||
          !_loading.add(tile)) {
        continue;
      }
      regions
          .decode(tile.$2, tile.$1)
          .then(
            (image) {
              _loading.remove(tile);
              if (!mounted ||
                  widget.regions != regions ||
                  !_wanted.contains(tile)) {
                image.dispose();
              } else {
                setState(() => _tiles[tile] = image);
              }
              if (mounted) _update();
            },
            onError: (Object _) {
              _loading.remove(tile);
              _failed.add(tile);
              if (mounted) _update();
            },
          );
    }
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _update();
    });
    return SizedBox.expand(
      child: CustomPaint(
        painter: _Painter(
          widget.size,
          widget.base,
          // Coarse first, under the finer.
          _tiles.entries.toList()..sort((a, b) => b.key.$1.compareTo(a.key.$1)),
        ),
      ),
    );
  }
}

class _Painter extends CustomPainter {
  _Painter(this.image, this.base, this.tiles);

  final Size image;
  final ui.Image? base;
  final List<MapEntry<_Tile, ui.Image>> tiles;

  @override
  void paint(Canvas canvas, Size size) {
    final fitted = Alignment.center.inscribe(
      applyBoxFit(BoxFit.contain, image, size).destination,
      Offset.zero & size,
    );
    final scale = fitted.width / image.width;
    final paint = Paint()..filterQuality = FilterQuality.medium;
    void draw(ui.Image picture, Rect to) => canvas.drawImageRect(
      picture,
      Offset.zero & Size(picture.width.toDouble(), picture.height.toDouble()),
      to,
      paint,
    );
    if (base case final base?) draw(base, fitted);
    for (final MapEntry(key: (_, region), value: tile) in tiles) {
      draw(
        tile,
        Rect.fromLTRB(
          fitted.left + region.left * scale,
          fitted.top + region.top * scale,
          fitted.left + region.right * scale,
          fitted.top + region.bottom * scale,
        ),
      );
    }
  }

  @override
  bool shouldRepaint(_Painter old) => true;
}
