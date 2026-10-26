/// The photo editor's GPU renderer: the develop adjustments of the kernel's CPU reference renderer
/// (`kernel/src/develop.rs`) as Flutter fragment shaders, for the preview.
/// Every export is the kernel's (ADR-0054); the shaders render tiles only
/// for the probe, as the GPU export that may come back as an optimization.
library;

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

/// The adjustments, each neutral at 0; `kernel/src/develop.rs` defines them.
class Develop {
  const Develop({
    this.temperature = 0,
    this.tint = 0,
    this.exposure = 0,
    this.contrast = 0,
    this.clarity = 0,
    this.saturation = 0,
    this.lut,
  });

  final double temperature, tint, exposure, contrast, clarity, saturation;
  final Lut? lut;
}

/// A 3D LUT of [size]³ sRGB-encoded RGB entries, red fastest, as 16-bit values.
class Lut {
  Lut(this.size, this.rgb16) : assert(rgb16.length == size * size * size * 3);

  final int size;
  final Uint16List rgb16;
}

/// The guide's size for an image: at most 64 cells on its long side, as the kernel computes it.
(int, int) _guideSize(int width, int height) {
  final n = math.min(64, math.max(width, height));
  int short(int s, int l) => math.max(1, (n * s + l ~/ 2) ~/ l);
  return width >= height
      ? (n, short(height, width))
      : (short(width, height), n);
}

/// An RGBA image from raw bytes.
Future<ui.Image> upload(Uint8List rgba, int width, int height) async {
  final buffer = await ui.ImmutableBuffer.fromUint8List(rgba);
  final descriptor = ui.ImageDescriptor.raw(
    buffer,
    width: width,
    height: height,
    pixelFormat: ui.PixelFormat.rgba8888,
  );
  final codec = await descriptor.instantiateCodec();
  final image = (await codec.getNextFrame()).image;
  codec.dispose();
  descriptor.dispose();
  buffer.dispose();
  return image;
}

/// The RGBA bytes of [image].
Future<Uint8List> pixels(ui.Image image) async =>
    (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!.buffer
        .asUint8List();

/// Renders with the shaders in `shaders/`. Each pass gets a shader of its own: Skwasm rasterizes `toImageSync` lazily
/// and reads a shader's uniforms then.
class ShaderRenderer {
  ShaderRenderer._(this._guide, this._blur, this._develop, this._none);

  /// Loads the shaders; [assets] is where the app bundles this package's assets (empty in its own tests).
  static Future<ShaderRenderer> load({
    String assets = 'packages/photolib_editor/',
  }) async {
    Future<ui.FragmentProgram> program(String name) =>
        ui.FragmentProgram.fromAsset('${assets}shaders/$name.frag');
    return ShaderRenderer._(
      await program('guide'),
      await program('blur'),
      await program('develop'),
      await upload(Uint8List(4), 1, 1),
    );
  }

  final ui.FragmentProgram _guide, _blur, _develop;
  final ui.Image _none;
  final _atlases = Expando<ui.Image>();

  /// The guide of a whole image from its [proxy]: the mean log2 luminance of each cell, blurred along each axis, in
  /// three passes.
  ui.Image guide(ui.Image proxy) {
    final (w, h) = _guideSize(proxy.width, proxy.height);
    var cells = _draw(_guide, [proxy.width, proxy.height, w, h], [proxy], w, h);
    for (final step in [(1, 0), (0, 1)]) {
      cells = _draw(_blur, [w, h, step.$1, step.$2], [cells], w, h);
    }
    return cells;
  }

  /// Renders [image], a whole image or the tile at ([x], [y]) of one of [fullWidth] × [fullHeight] pixels, with the
  /// [guide] of the whole image.
  Future<ui.Image> render(
    Develop develop,
    ui.Image image,
    ui.Image guide, {
    int x = 0,
    int y = 0,
    int? fullWidth,
    int? fullHeight,
  }) async {
    final lut = develop.lut;
    final atlas = lut == null ? _none : _atlases[lut] ??= await _atlas(lut);
    double gain(double v) => math.pow(2, v + develop.exposure).toDouble();
    final uniforms = [
      image.width,
      image.height,
      x,
      y,
      fullWidth ?? image.width,
      fullHeight ?? image.height,
      guide.width,
      guide.height,
      gain(0.5 * develop.temperature),
      gain(-0.5 * develop.tint),
      gain(-0.5 * develop.temperature),
      develop.contrast,
      develop.clarity,
      develop.saturation,
      lut?.size ?? 0,
    ];
    final (picture, shader) = _record(
      _develop,
      uniforms,
      [image, guide, atlas],
      image.width,
      image.height,
    );
    final out = await picture.toImage(image.width, image.height);
    picture.dispose();
    // Else the shader holds the tile's texture until the garbage collector finalizes it.
    shader.dispose();
    return out;
  }

  /// The LUT as an RGBA atlas: entry (r, g, b) at (b·n + r, g), its high bytes above its low bytes.
  Future<ui.Image> _atlas(Lut lut) {
    final n = lut.size;
    final rgba = Uint8List(n * n * 2 * n * 4);
    for (var i = 0; i < n * n * n; i++) {
      final (r, g, b) = (i % n, i ~/ n % n, i ~/ (n * n));
      final hi = (g * n * n + b * n + r) * 4;
      final lo = hi + n * n * n * 4;
      for (var c = 0; c < 3; c++) {
        rgba[hi + c] = lut.rgb16[i * 3 + c] >> 8;
        rgba[lo + c] = lut.rgb16[i * 3 + c] & 255;
      }
      rgba[hi + 3] = rgba[lo + 3] = 255;
    }
    return upload(rgba, n * n, 2 * n);
  }

  static ui.Image _draw(
    ui.FragmentProgram program,
    List<num> uniforms,
    List<ui.Image> samplers,
    int width,
    int height,
  ) {
    final (picture, _) = _record(program, uniforms, samplers, width, height);
    final image = picture.toImageSync(width, height);
    picture.dispose();
    return image;
  }

  static (ui.Picture, ui.FragmentShader) _record(
    ui.FragmentProgram program,
    List<num> uniforms,
    List<ui.Image> samplers,
    int width,
    int height,
  ) {
    final shader = program.fragmentShader();
    for (final (i, v) in uniforms.indexed) {
      shader.setFloat(i, v.toDouble());
    }
    for (final (i, image) in samplers.indexed) {
      shader.setImageSampler(i, image);
    }
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawRect(
      ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      ui.Paint()..shader = shader,
    );
    return (recorder.endRecording(), shader);
  }
}
