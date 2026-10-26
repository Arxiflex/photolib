import 'dart:math';
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';
import 'package:photolib_data/photolib_data.dart' show LocalAssetData;

/// Where a photo sphere's or 360° video's picture lies on the sphere
/// (docs/10-client-app.md §4.4): an equirectangular or [cylinder]'s [crop]
/// of the full panorama, or a 3 × 2 [cube]map, in the [eye] of the frame a
/// stereo picture shows, as fractions.
@immutable
class Sphere {
  /// A sphere's picture: the whole equirectangular frame by default.
  const new({
    this.cube = false,
    this.cylinder = false,
    this.aspect = 2,
    this.crop = const Rect.fromLTWH(0, 0, 1, 1),
    this.eye = const Rect.fromLTWH(0, 0, 1, 1),
    this.heading,
  });

  /// [row]'s, from its metadata; null for a flat picture or a projection the
  /// viewer does not know.
  static Sphere? of(LocalAssetData? row) {
    if (row == null || !projections.contains(row.projection)) return null;
    final cylinder = row.projection == 'cylindrical';
    final full = row.crop?.split(',').skip(4).map(double.parse).toList();
    return Sphere(
      cube: row.projection == 'cubemap',
      cylinder: cylinder,
      aspect: switch ((cylinder, full, row.width, row.height)) {
        (false, _, _, _) => 2,
        (_, [final w, final h], _, _) => w / h,
        (_, _, final w?, final h?) when w > 0 && h > 0 => w / h,
        _ => 2,
      },
      crop: cropOf(row.crop),
      eye: eyeOf(row.stereo),
      heading: switch (row.heading) {
        final h? => h * pi / 180,
        null => null,
      },
    );
  }

  /// Where the picture of a [crop] (the replica's `left,top,width,height,
  /// full width,full height`) lies in the full panorama.
  static Rect cropOf(String? crop) =>
      switch (crop?.split(',').map(double.parse).toList()) {
        [final l, final t, final w, final h, final fw, final fh] =>
          Rect.fromLTWH(l / fw, t / fh, w / fw, h / fh),
        _ => const Rect.fromLTWH(0, 0, 1, 1),
      };

  /// The part of the frame that the left eye of a [stereo] picture sees.
  static Rect eyeOf(String? stereo) => switch (stereo) {
    'top_bottom' => const Rect.fromLTWH(0, 0, 1, 0.5),
    'left_right' => const Rect.fromLTWH(0, 0, 0.5, 1),
    'right_left' => const Rect.fromLTWH(0.5, 0, 0.5, 1),
    _ => const Rect.fromLTWH(0, 0, 1, 1),
  };

  /// The projections the viewer draws.
  static const projections = {'equirectangular', 'cubemap', 'cylindrical'};

  /// Whether the picture is a 3 × 2 cubemap, in FFmpeg v360's layout.
  final bool cube;

  /// Whether the panorama is cylindrical: down it, the tangent of the
  /// latitude, as GPano's ProjectionType says.
  final bool cylinder;

  /// The full panorama's width over its height, which a cylinder's height on
  /// the sphere follows.
  final double aspect;

  /// Where an equirectangular picture lies in the full panorama.
  final Rect crop;

  /// The part of the frame that one eye of a stereo picture sees.
  final Rect eye;

  /// The compass heading of the full panorama's middle, in radians east of
  /// north (GPano's PoseHeadingDegrees), if known.
  final double? heading;

  /// Whether the picture goes all the way round.
  bool get whole => cube || crop.width > 0.999;

  /// The longitude and latitude, in radians, of the middle of the picture.
  (double, double) get middle => cube
      ? (0, 0)
      : ((crop.center.dx - 0.5) * 2 * pi, latitude(crop.center.dy));

  /// How far down the full panorama the latitude [lat] is, as a fraction.
  double down(double lat) => cylinder
      ? 0.5 - tan(lat.clamp(-pi / 2, pi / 2)) * aspect / (2 * pi)
      : 0.5 - lat / pi;

  /// The latitude [v] down the full panorama, as a fraction.
  double latitude(double v) =>
      cylinder ? atan((0.5 - v) * 2 * pi / aspect) : (0.5 - v) * pi;

  /// The part [of] its picture, as fractions, as a picture of its own: a
  /// tile's.
  Sphere part(Rect of) => Sphere(
    cylinder: cylinder,
    aspect: aspect,
    crop: Rect.fromLTWH(
      crop.left + of.left * crop.width,
      crop.top + of.top * crop.height,
      of.width * crop.width,
      of.height * crop.height,
    ),
  );

  /// Where in the picture, as fractions across and down, the point at [lon]
  /// and [lat] is; null outside it.
  (double, double)? at(double lon, double lat) {
    if (!cube) {
      final x = ((lon / (2 * pi) + 0.5 - crop.left) % 1) / crop.width;
      final y = (down(lat) - crop.top) / crop.height;
      return x > 1 || y < 0 || y > 1 ? null : (x, y);
    }
    // As the shader's cube(): x right, y down, z ahead.
    final (dx, dy, dz) = (cos(lat) * sin(lon), -sin(lat), cos(lat) * cos(lon));
    final (ax, ay, az) = (dx.abs(), dy.abs(), dz.abs());
    final int face;
    final (double, double) uv;
    if (ay >= ax && ay >= az) {
      face = dy < 0 ? 2 : 3;
      uv = dy < 0 ? (-dx / dy, -dz / dy) : (dx / dy, -dz / dy);
    } else if (ax >= az) {
      face = dx > 0 ? 0 : 1;
      uv = (-dz / dx, (dx > 0 ? dy : -dy) / dx);
    } else {
      face = dz > 0 ? 4 : 5;
      uv = (dx / dz, (dz > 0 ? dy : -dy) / dz);
    }
    return (
      (face % 3 + (uv.$1 * 0.5 + 0.5).clamp(0, 1)) / 3,
      (face ~/ 3 + (uv.$2 * 0.5 + 0.5).clamp(0, 1)) / 2,
    );
  }

  /// Whether the point at [lon] and [lat] is in the picture.
  bool covers(double lon, double lat) {
    if (cube) return true;
    final u = lon / (2 * pi) + 0.5;
    final v = down(lat);
    const e = 1e-6;
    final x = (u - crop.left) % 1;
    return v >= crop.top - e &&
        v <= crop.bottom + e &&
        (whole || x <= crop.width + e || x >= 1 - e);
  }

  @override
  bool operator ==(Object other) =>
      other is Sphere &&
      other.cube == cube &&
      other.cylinder == cylinder &&
      other.aspect == aspect &&
      other.crop == crop &&
      other.eye == eye &&
      other.heading == heading;

  @override
  int get hashCode => Object.hash(cube, cylinder, aspect, crop, eye, heading);
}

/// Where a sphere is looked at: [yaw] east and [pitch] up from its middle
/// meridian and equator, in radians, through a lens of [fov] radians across
/// the viewport's short side, rectilinear or, for a [planet], stereographic,
/// or a [fisheye]'s, equidistant.
@immutable
class SphereView {
  /// Straight ahead through a 75° rectilinear lens, unless said otherwise.
  const new({
    this.yaw = 0,
    this.pitch = 0,
    this.fov = 75 * pi / 180,
    this.planet = false,
    this.fisheye = false,
  });

  /// A little planet: straight down, through the widest lens.
  const new planet() : this(pitch: -pi / 2, fov: 300 * pi / 180, planet: true);

  /// The narrowest lens.
  static const double minFov = 20 * pi / 180;

  /// Radians east of the picture's middle meridian.
  final double yaw;

  /// Radians above its equator.
  final double pitch;

  /// The lens' angle across the viewport's short side, in radians.
  final double fov;

  /// Whether the lens is stereographic, a little planet's.
  final bool planet;

  /// Whether the lens is equidistant, a fisheye's.
  final bool fisheye;

  /// The widest lens.
  double get maxFov => (planet ? 330 : (fisheye ? 200 : 120)) * pi / 180;

  /// The half-extent of the image plane over the short side.
  double get scale => planet
      ? tan(fov / 4)
      : fisheye
      ? fov / 2
      : tan(fov / 2);

  /// This view with [yaw], [pitch] or [fov] changed.
  SphereView copyWith({double? yaw, double? pitch, double? fov}) => SphereView(
    yaw: yaw ?? this.yaw,
    pitch: pitch ?? this.pitch,
    fov: fov ?? this.fov,
    planet: planet,
    fisheye: fisheye,
  );

  /// The longitude and latitude, in radians, that the viewport's point [p]
  /// shows, from its middle, in units of half its short side.
  (double, double) ray(Offset p) {
    final (x, y) = (p.dx * scale, p.dy * scale);
    // x right, y down, z ahead, as the shader and FFmpeg's v360 have them.
    var (dx, dy, dz) = (x, y, 1.0);
    if (planet || fisheye) {
      final r = sqrt(x * x + y * y);
      final t = planet ? 2 * atan(r) : r;
      (dx, dy, dz) = r == 0
          ? (0, 0, 1)
          : (x / r * sin(t), y / r * sin(t), cos(t));
    }
    final (cp, sp, cy, sy) = (cos(pitch), sin(pitch), cos(yaw), sin(yaw));
    (dy, dz) = (dy * cp - dz * sp, dy * sp + dz * cp);
    (dx, dz) = (dx * cy + dz * sy, dz * cy - dx * sy);
    final n = sqrt(dx * dx + dy * dy + dz * dz);
    return (atan2(dx, dz), -asin((dy / n).clamp(-1.0, 1.0)));
  }

  /// The longitudes and latitudes along the edges of a viewport of [size].
  Iterable<(double, double)> _edges(Size size) sync* {
    final short = min(size.width, size.height) / 2;
    const n = 8;
    for (var i = 0; i <= n; i++) {
      for (final (x, y) in [(i / n, 0), (i / n, 1), (0, i / n), (1, i / n)]) {
        yield ray(
          Offset(
            (x - 0.5) * size.width / short,
            (y - 0.5) * size.height / short,
          ),
        );
      }
    }
  }

  /// Whether every point of a viewport of [size] shows [sphere]'s picture.
  bool within(Sphere sphere, Size size) => [
    ray(Offset.zero),
    ..._edges(size),
  ].every((r) => sphere.covers(r.$1, r.$2));

  /// The nearest view within [sphere]'s picture on a viewport of [size]:
  /// the lens within bounds, then pitch and yaw no further from the
  /// picture's middle than it covers, so that no black ever shows. A little
  /// planet stretches a partial picture's edges instead.
  SphereView clamp(Sphere sphere, Size size) {
    var v = copyWith(fov: fov.clamp(minFov, maxFov));
    if (planet ||
        sphere.whole && !sphere.cylinder && sphere.crop.height > 0.999) {
      return v;
    }
    final (lon, lat) = sphere.middle;
    // The value from [inside] towards [asked] furthest within the picture.
    double bisect(double inside, double asked, SphereView Function(double) at) {
      if (at(asked).within(sphere, size)) return asked;
      var (from, to) = (inside, asked);
      for (var i = 0; i < 24; i++) {
        final mid = (from + to) / 2;
        if (at(mid).within(sphere, size)) {
          from = mid;
        } else {
          to = mid;
        }
      }
      return from;
    }

    final yaw = sphere.whole ? v.yaw : lon;
    v = v.copyWith(
      fov: bisect(
        minFov,
        v.fov,
        (f) => v.copyWith(yaw: yaw, pitch: lat, fov: f),
      ),
    );
    v = v.copyWith(
      pitch: bisect(lat, v.pitch, (p) => v.copyWith(yaw: yaw, pitch: p)),
    );
    if (sphere.whole) return v;
    // The yaw nearest the asked one, the way round it is nearer.
    final asked = lon + ((v.yaw - lon + pi) % (2 * pi) - pi);
    return v.copyWith(yaw: bisect(lon, asked, (y) => v.copyWith(yaw: y)));
  }

  /// Of [levels] halvings of a texture [width] pixels wide, the smallest
  /// with at least one texel to each pixel at the middle of a viewport whose
  /// short side is [short] pixels: filtered, never aliased.
  int level(Sphere sphere, double short, int width, int levels) {
    final pixel = 2 * scale / short * (planet ? 2 : 1);
    final texel = sphere.cube
        ? pi / 2 / (width * sphere.eye.width / 3)
        : 2 * pi * sphere.crop.width / (width * sphere.eye.width);
    final level = (log(pixel / texel) / ln2).floor();
    return level.clamp(0, levels - 1);
  }

  /// Where in [sphere]'s picture, as fractions, the rays of a viewport of
  /// [size] meet it: within a 2 % margin, across it at 32 rays, along its
  /// edges at 128.
  Iterable<(double, double)> seen(Sphere sphere, Size size) sync* {
    final short = min(size.width, size.height) / 2;
    final (w, h) = (size.width / short, size.height / short);
    const m = 0.51;
    Iterable<(double, double)> rays() sync* {
      for (var i = 0; i <= 32; i++) {
        for (var j = 0; j <= 32; j++) {
          yield ((i / 32 - 0.5) * 2 * m, (j / 32 - 0.5) * 2 * m);
        }
      }
      for (var i = 0; i <= 128; i++) {
        final t = (i / 128 - 0.5) * 2 * m;
        yield* [(t, -m), (t, m), (-m, t), (m, t)];
      }
    }

    for (final (x, y) in rays()) {
      final (lon, lat) = ray(Offset(x * w, y * h));
      if (sphere.at(lon, lat) case final p?) yield p;
    }
  }

  /// The tiles of [sphere]'s picture, 512 pixels square at a sample size of
  /// an original of [size] pixels (design 08 §7's pyramid), that this view
  /// shows sharper on a viewport of [viewport] pixels than [width], the
  /// widest picture loaded: the sample size, a power of two, and each tile's
  /// column and row; none where that picture is fine enough, and for a
  /// little planet or a cubemap.
  (int, Set<(int, int)>)? tiles(
    Sphere sphere,
    Size viewport,
    Size size,
    int width,
  ) {
    if (planet || sphere.cube) return null;
    final across = size.width * sphere.eye.width;
    final down = size.height * sphere.eye.height;
    // The picture's pixels across that put a texel on each pixel's angle.
    final need =
        pi * sphere.crop.width * min(viewport.width, viewport.height) / scale;
    var sample = 1;
    while (across / (sample * 2) >= need) {
      sample *= 2;
    }
    if (across / sample <= width * 1.01) return null;
    final tile = 512.0 * sample;
    final (cols, rows) = ((across / tile).ceil(), (down / tile).ceil());
    return (
      sample,
      {
        for (final (x, y) in seen(sphere, viewport))
          (
            min((x * across / tile).floor(), cols - 1),
            min((y * down / tile).floor(), rows - 1),
          ),
      },
    );
  }

  /// FFmpeg's v360 filter for this view of [sphere] on a viewport of [size]
  /// pixels, as libmpv projects 360° video (ADR-0146), its yaw within the
  /// half turn either way v360 takes, which drags turn past. A cropped
  /// picture, which v360 cannot take, is padded to its full panorama, one
  /// eye of it.
  String v360(Sphere sphere, Size size) {
    final (w, h) = (size.width.round(), size.height.round());
    final short = min(w, h);
    double degrees(double r) => r * 180 / pi;
    final half = planet ? fov / 4 : fov / 2;
    String extent(int pixels) {
      final a = fisheye
          ? half * pixels / short
          : atan(tan(half) * pixels / short);
      return degrees(planet ? 4 * a : 2 * a).toStringAsFixed(3);
    }

    final (eye, crop) = (sphere.eye, sphere.crop);
    String f(double x) => x.toStringAsFixed(6);
    final cropped = !sphere.cube && crop != const Rect.fromLTWH(0, 0, 1, 1);
    final one = cropped && (eye.width < 1 || eye.height < 1)
        ? 'crop=iw*${f(eye.width)}:ih*${f(eye.height)}'
              ':iw*${f(eye.left)}:ih*${f(eye.top)},'
        : '';
    final pad = cropped
        ? '${one}pad=iw/${f(crop.width)}:ih/${f(crop.height)}'
              ':iw*${f(crop.left / crop.width)}'
              ':ih*${f(crop.top / crop.height)},'
        : '';
    final stereo = pad.isNotEmpty
        ? ''
        : eye.height < 1
        ? ':in_stereo=tb'
        : eye.width < 1
        ? ':in_stereo=sbs'
        : '';
    return '${pad}v360=input=${sphere.cube ? 'c3x2' : 'e'}'
        ':output=${planet ? 'sg' : (fisheye ? 'fisheye' : 'flat')}$stereo'
        ':interp=linear'
        ':w=$w:h=$h:h_fov=${extent(w)}:v_fov=${extent(h)}'
        ':yaw=${degrees((yaw + pi) % (2 * pi) - pi).toStringAsFixed(3)}'
        ':pitch=${degrees(pitch).toStringAsFixed(3)}';
  }

  @override
  bool operator ==(Object other) =>
      other is SphereView &&
      other.yaw == yaw &&
      other.pitch == pitch &&
      other.fov == fov &&
      other.planet == planet &&
      other.fisheye == fisheye;

  @override
  int get hashCode => Object.hash(yaw, pitch, fov, planet, fisheye);
}

/// The panorama shader, shaders/sphere.frag.
final Future<ui.FragmentProgram> sphereProgram = ui.FragmentProgram.fromAsset(
  'shaders/sphere.frag',
);

/// Players that project 360° video themselves, through the filter of the
/// [SphereProjection] above their views: libmpv's (ADR-0146).
abstract interface class ProjectingPlayers;

/// What the view of a 360° video's player below shows (ADR-0146): libmpv
/// projects through [filter], FFmpeg's v360 filter of the sphere's view, and
/// shows its pictures once it does; a browser's view hands its `<video>`
/// element to [onElement].
class SphereProjection extends InheritedWidget {
  /// Asks the player's view below for [filter] or for [onElement].
  const new({required super.child, this.filter, this.onElement, super.key});

  /// FFmpeg's v360 filter for libmpv.
  final String? filter;

  /// Takes the browser's `<video>` element.
  final ValueChanged<Object>? onElement;

  /// The nearest above [context], which it depends on.
  static SphereProjection? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SphereProjection>();

  @override
  bool updateShouldNotify(SphereProjection old) => old.filter != filter;
}

/// [image] and its halvings, each a 2 × 2 box filter of the one before,
/// down to [smallest] pixels wide: the levels of detail the shader picks
/// from, as Flutter's samplers do not mipmap (docs/10-client-app.md §4.4).
List<ui.Image> levelsOf(ui.Image image, {int smallest = 256}) {
  final levels = [image];
  while (levels.last.width >= 2 * smallest) {
    final last = levels.last;
    final (w, h) = (last.width ~/ 2, last.height ~/ 2);
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawImageRect(
      last,
      Rect.fromLTWH(0, 0, w * 2.0, h * 2.0),
      Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
      Paint()..filterQuality = FilterQuality.low,
    );
    final picture = recorder.endRecording();
    // root-isolate-ok: it records the halving for the GPU, reading nothing
    levels.add(picture.toImageSync(w, h));
    picture.dispose();
  }
  return levels;
}

/// Sets [shader]'s uniforms for [view] of [sphere] on a [viewport] in
/// pixels, from a frame of [width] × [height] pixels, the texture's or, as
/// [packing] packs them, its cells': from the first, the canvas' size,
/// unless [from] is 2, as a filter's, whose input's size the engine sets.
void sphereUniforms(
  ui.FragmentShader shader,
  Sphere sphere,
  SphereView view,
  Size viewport,
  int width,
  int height,
  int from, [
  SpherePacking? packing,
]) {
  final (crop, eye) = (sphere.crop, sphere.eye);
  var i = from;
  for (final f in [
    if (from == 0) ...[viewport.width, viewport.height],
    viewport.width,
    viewport.height,
    view.yaw,
    view.pitch,
    view.scale,
    if (view.planet) 1.0 else if (view.fisheye) 2.0 else 0.0,
    crop.left,
    crop.top,
    crop.width,
    crop.height,
    eye.left,
    eye.top,
    eye.width,
    eye.height,
    width.toDouble(),
    height.toDouble(),
    if (sphere.cube) 1.0 else if (sphere.cylinder) 2.0 else 0.0,
    sphere.aspect,
    (packing?.across ?? 0).toDouble(),
    (packing?.down ?? 0).toDouble(),
    switch (packing) {
      null => 0.0,
      SpherePacking(input: null) => 1.0,
      _ => 2.0,
    },
    ...switch (packing?.input) {
      final r? => [r.left, r.top, r.width, r.height],
      null => [0.0, 0.0, 1.0, 1.0],
    },
  ]) {
    shader.setFloat(i++, f);
  }
}

/// What of a sphere's frame the shader filter (Android, iOS, macOS) holds
/// in its input, the viewport's pixels: the part in view as one rectangle,
/// [input], or, where that holds it at a lower scale, the cells in view,
/// each in a slot: near a pole every longitude is in view, and a cubemap's
/// faces in view are not side by side. The picture, one eye's, has 8 rows of
/// cells: a cubemap's 12 across, an equirectangular one's fewer towards the
/// poles, where its pixels are narrower on the sphere. Slot 0 holds the
/// whole picture, for anything between the rays cast.
@immutable
class SpherePacking {
  const new _(this.cols, this.slots, this.across, this.down, [this.input]);

  /// [view] of [sphere] on a [viewport] of pixels, of a [frame] of pixels.
  factory of(Sphere sphere, SphereView view, Size viewport, Size frame) {
    final crop = sphere.crop;
    final cols = [
      for (var r = 0; r < 8; r++)
        if (sphere.cube)
          12
        else
          (16 * crop.width * _widest(sphere, r)).round().clamp(1, 16),
    ];
    final held = <int>{
      for (final (x, y) in view.seen(sphere, viewport))
        if (min((y * 8).floor(), 7) case final int row)
          row * 16 + min((x * cols[row]).floor(), cols[row] - 1),
    };
    final cells = held.toList()..sort();
    final n = cells.length + 1;
    final cell = Size(
      frame.width * sphere.eye.width / cols.reduce(max),
      frame.height * sphere.eye.height / 8,
    );
    var (best, across) = (0.0, 1);
    for (var a = 1; a <= n; a++) {
      final scale = min(
        viewport.width / a / cell.width,
        viewport.height / (n / a).ceil() / cell.height,
      );
      if (scale > best) (best, across) = (scale, a);
    }
    if (_part(sphere, view, viewport) case final input?
        when min(
              viewport.width / input.width / frame.width,
              viewport.height / input.height / frame.height,
            ) >=
            best) {
      return SpherePacking._(cols, const {}, 1, 1, input);
    }
    return SpherePacking._(
      cols,
      {for (final (i, c) in cells.indexed) c: i + 1},
      across,
      (n / across).ceil(),
    );
  }

  /// The part of [sphere]'s frame, as fractions, that [view] shows on a
  /// [viewport], a degree wider each way: its left anywhere round the eye,
  /// its width up to the eye's; none for a little planet or a cubemap.
  static Rect? _part(Sphere sphere, SphereView view, Size viewport) {
    if (view.planet || sphere.cube) return null;
    var (west, east, south, north) = (pi, -pi, pi / 2, -pi / 2);
    for (final (lon, lat) in view._edges(viewport)) {
      final along = (lon - view.yaw + pi) % (2 * pi) - pi;
      (west, east) = (min(west, along), max(east, along));
      (south, north) = (min(south, lat), max(north, lat));
    }
    // A pole in view: all the way round, to the pole.
    final reach =
        view.scale * viewport.height / min(viewport.width, viewport.height);
    final (cp, sp) = (cos(view.pitch), sin(view.pitch));
    if (sp > 0 && cp <= reach * sp) (west, east, north) = (-pi, pi, pi / 2);
    if (sp < 0 && cp <= -reach * sp) (west, east, south) = (-pi, pi, -pi / 2);
    const margin = pi / 180;
    final (crop, eye) = (sphere.crop, sphere.eye);
    final double width = min(
      1,
      (east - west + 2 * margin) / (2 * pi) / crop.width,
    );
    final left = width >= 1
        ? 0
        : ((view.yaw + west - margin) / (2 * pi) + 0.5 - crop.left) %
              1 /
              crop.width;
    final double top = max(
      0,
      (sphere.down(north + margin) - crop.top) / crop.height,
    );
    final double bottom = min(
      1,
      (sphere.down(south - margin) - crop.top) / crop.height,
    );
    return Rect.fromLTWH(
      eye.left + left * eye.width,
      eye.top + top * eye.height,
      width * eye.width,
      (bottom - top) * eye.height,
    );
  }

  /// The cosine of the latitude of the edge of [sphere]'s picture's [row]
  /// nearer the equator, or 1 when it holds the equator.
  static double _widest(Sphere sphere, int row) {
    final crop = sphere.crop;
    double lat(int edge) => sphere.latitude(crop.top + edge / 8 * crop.height);
    final (a, b) = (lat(row), lat(row + 1));
    return a * b <= 0 ? 1 : cos(min(a.abs(), b.abs()));
  }

  /// Each row's cells across.
  final List<int> cols;

  /// The slot of each cell held, by row × 16 + column.
  final Map<int, int> slots;

  /// The slots across.
  final int across;

  /// The slots down.
  final int down;

  /// The part of the frame held in the whole viewport, as fractions,
  /// followed round the sphere by the eye's next copy; none when cells are.
  final Rect? input;

  /// The part of the frame each slot holds, and the slot, as fractions of
  /// the frame and of the viewport: slot 0 the whole of [eye], then the
  /// cells held; or [input] and the eye's next copy in the whole viewport.
  Iterable<(Rect, Rect)> regions(Rect eye) sync* {
    if (input case final input?) {
      const all = Rect.fromLTWH(0, 0, 1, 1);
      yield (input, all);
      yield (input.translate(-eye.width, 0), all);
      return;
    }
    Rect slot(int i) => Rect.fromLTWH(
      i % across / across,
      i ~/ across / down,
      1 / across,
      1 / down,
    );
    yield (eye, slot(0));
    for (final MapEntry(key: c, value: i) in slots.entries) {
      final (row, col) = (c ~/ 16, c % 16);
      final cols = this.cols[row];
      yield (
        Rect.fromLTWH(
          eye.left + col / cols * eye.width,
          eye.top + row / 8 * eye.height,
          eye.width / cols,
          eye.height / 8,
        ),
        slot(i),
      );
    }
  }

  /// The shader's map of the cells, uCells: each cell's slot in red, its
  /// row's cells in green.
  ui.Image cells() {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    for (var row = 0; row < 8; row++) {
      for (var col = 0; col < 16; col++) {
        canvas.drawRect(
          Rect.fromLTWH(col.toDouble(), row.toDouble(), 1, 1),
          Paint()
            ..isAntiAlias = false
            ..color = Color.fromARGB(
              255,
              slots[row * 16 + col] ?? 0,
              cols[row],
              0,
            ),
        );
      }
    }
    final picture = recorder.endRecording();
    // root-isolate-ok: it records 128 pixels for the GPU, reading nothing
    final image = picture.toImageSync(16, 8);
    picture.dispose();
    return image;
  }
}

/// Paints [image], [sphere]'s picture, as [view] shows it through the
/// panorama shader (shaders/sphere.frag).
class SpherePainter extends CustomPainter {
  /// Paints [image] through [shader], the panorama shader's.
  new(this.shader, this.image, this.sphere, this.view);

  /// A shader of shaders/sphere.frag.
  final ui.FragmentShader shader;

  /// The picture, or one of its levels of detail.
  final ui.Image image;

  /// Where the picture lies on the sphere.
  final Sphere sphere;

  /// Where it is seen from.
  final SphereView view;

  @override
  void paint(Canvas canvas, Size size) {
    sphereUniforms(shader, sphere, view, size, image.width, image.height, 0);
    // uCells, which a whole frame leaves unread.
    shader
      ..setImageSampler(0, image)
      ..setImageSampler(1, image);
    canvas.drawRect(Offset.zero & size, Paint()..shader = shader);
  }

  @override
  bool shouldRepaint(SpherePainter old) =>
      old.image != image || old.sphere != sphere || old.view != view;
}
