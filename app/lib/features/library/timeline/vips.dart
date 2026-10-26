// root-isolate-ok: libvips is loaded and called only inside Isolate.run.
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

// root-isolate-ok: as dart:ffi above.
import 'package:ffi/ffi.dart';
import 'package:photolib/features/library/timeline/embedded.dart';
import 'package:photolib/features/library/timeline/pipeline.dart';
import 'package:photolib/features/library/timeline/thumbnails.dart';
import 'package:photolib_data/photolib_data.dart' show rawExtensions;

/// The desktops' decoder of last resort (ADR-0107): libvips, loaded from the
/// system or beside the app, null when there is none. It decodes a file to
/// its tile on an isolate, as JPEG (PNG with alpha) for the disk cache:
/// HEIC, AVIF, JPEG XL and the formats Flutter knows, through an allow-list
/// of loaders, and a RAW's largest embedded JPEG turned as the RAW is, never
/// its sensor data (ADR-0247); it refuses a header over 300 MP before
/// decoding (docs/08-media-pipeline.md §8).
Future<Thumbnailer?> vipsDecoder() async {
  final library = await (_started ??= Isolate.run(_open));
  if (library == null) return null;
  return Thumbnailer('vips', (item, tier, _) async {
    if (item.video) throw const Declined('video');
    if (!item.uri.isScheme('file')) throw const Declined('no scheme');
    final path = item.uri.toFilePath();
    Uint8List? jpeg;
    if (rawExtensions.contains(path.split('.').last.toLowerCase())) {
      jpeg = await largestPreview(path);
      if (jpeg == null) throw const NoThumbnail(cause: 'a RAW without a JPEG');
    }
    final (tile, refused) = await Isolate.run(
      () => _tile(library, path, jpeg, tier),
    );
    if (tile == null) throw NoThumbnail(cause: refused ?? 'unreadable');
    return Pixels.encoded(tile);
  });
}

/// libvips as on-device ML's decoder (ADR-0278), null when there is none:
/// what [vipsPixels] takes, and its version.
Future<(String, String)?> vipsLibrary() async {
  final library = await (_started ??= Isolate.run(_open));
  if (library == null) return null;
  return (library, await Isolate.run(() => _version(library)));
}

String _version(String library) {
  final version = DynamicLibrary.open(library)
      .lookupFunction<Int Function(Int), int Function(int)>('vips_version');
  return 'vips ${version(0)}.${version(1)}.${version(2)}';
}

const _loaders = ['Jpeg', 'Png', 'Webp', 'Gif', 'Tiff', 'Heif', 'Jxl'];

Future<String?>? _started;

typedef _Str = Pointer<Utf8>;
typedef _Ptr = Pointer<Pointer>;

/// The `vips-modules` folder beside the bundled [library] (the HEIF and
/// JPEG XL loaders tools/macos/bundle_vips.py copies), null for a library
/// found by its bare name or without one.
String? vipsModuleDir(String library) {
  if (!library.contains('/')) return null;
  final modules = Directory('${File(library).parent.path}/vips-modules');
  // root-isolate-ok: called only by _open, which runs on an Isolate.run.
  return modules.existsSync() ? modules.path : null;
}

/// Sets `VIPS_MODULEDIR` to [directory] for this process, which libvips reads
/// in vips_init to find loaders it does not hold itself (Homebrew's default
/// is a path inside its own Cellar). False where there is no setenv.
bool vipsSetModuleDir(String directory) {
  if (Platform.isWindows) return false;
  return using((arena) {
    final set = DynamicLibrary.process()
        .lookupFunction<
          Int Function(_Str, _Str, Int),
          int Function(_Str, _Str, int)
        >('setenv');
    return set(
          'VIPS_MODULEDIR'.toNativeUtf8(allocator: arena),
          directory.toNativeUtf8(allocator: arena),
          1,
        ) ==
        0;
  });
}

// Runs on an isolate: the library, started once for the process before any
// decode, as vips_init and the block list are not safe to race.
String? _open() {
  for (final name in [
    if (Platform.isMacOS) ...[
      '${File(Platform.resolvedExecutable).parent.parent.path}/Frameworks/libvips.42.dylib',
      'libvips.42.dylib',
    ],
    if (Platform.isWindows) 'libvips-42.dll',
    if (Platform.isLinux) 'libvips.so.42',
  ]) {
    final DynamicLibrary vips;
    try {
      vips = DynamicLibrary.open(name);
      // ignore: avoid_catching_errors, as dart:ffi says a missing library so.
    } on ArgumentError {
      continue;
    }
    if (vipsModuleDir(name) case final modules?) vipsSetModuleDir(modules);
    using((arena) {
      _Str text(String s) => s.toNativeUtf8(allocator: arena);
      vips.lookupFunction<Int Function(_Str), int Function(_Str)>('vips_init')(
        text('photolib'),
      );
      for (final setting in ['vips_cache_set_max', 'vips_concurrency_set']) {
        vips.lookupFunction<Void Function(Int), void Function(int)>(setting)(
          setting.contains('cache') ? 0 : 1,
        );
      }
      final block = vips
          .lookupFunction<Void Function(_Str, Int), void Function(_Str, int)>(
            'vips_operation_block_set',
          );
      block(text('VipsForeignLoad'), 1);
      for (final loader in _loaders) {
        block(text('VipsForeignLoad$loader'), 0);
      }
    });
    return name;
  }
  return null;
}

// Runs on an isolate: the tile of the file at [path], or of [jpeg] when
// given, or why there is none.
(Uint8List?, String?) _tile(
  String library,
  String path,
  Uint8List? jpeg,
  int tier,
) => _thumbnail(library, path, tier, jpeg: jpeg, (vips, image, arena) {
  final buffer = arena<Pointer>();
  final length = arena<Size>();
  final save = vips.vips
      .lookupFunction<
        Int Function(
          Pointer,
          _Ptr,
          Pointer<Size>,
          VarArgs<(_Str, Int, Pointer)>,
        ),
        int Function(Pointer, _Ptr, Pointer<Size>, _Str, int, Pointer)
      >(
        vips.call('vips_image_hasalpha', image) != 0
            ? 'vips_pngsave_buffer'
            : 'vips_jpegsave_buffer',
      );
  // No metadata: keep is VIPS_FOREIGN_KEEP_NONE.
  if (save(image, buffer, length, vips.text('keep'), 0, nullptr) != 0) {
    throw StateError(vips.error());
  }
  final tile = Uint8List.fromList(
    buffer.value.cast<Uint8>().asTypedList(length.value),
  );
  vips.free(buffer.value);
  return tile;
});

/// Runs on an isolate: the file at [path] upright in 8-bit sRGB RGBA, its
/// short side at most [size], or null with why: on-device ML's input
/// (design 09 §2.2), from the library [vipsLibrary] gives.
({int width, int height, Uint8List rgba})? vipsPixels(
  String library,
  String path,
  int size,
) => _thumbnail(library, path, size, (vips, image, arena) {
  final out = arena<Pointer>();
  Pointer step(Pointer image, String name, List<Object> args) {
    final ok = switch (args) {
      [final int a] =>
        vips.vips.lookupFunction<
          Int Function(Pointer, _Ptr, Int, VarArgs<(Pointer,)>),
          int Function(Pointer, _Ptr, int, Pointer)
        >(name)(image, out, a, nullptr),
      [final double a] =>
        vips.vips.lookupFunction<
          Int Function(Pointer, _Ptr, Double, VarArgs<(Pointer,)>),
          int Function(Pointer, _Ptr, double, Pointer)
        >(name)(image, out, a, nullptr),
      _ => throw ArgumentError(args),
    };
    vips.unref(image);
    if (ok != 0) throw StateError(vips.error());
    return out.value;
  }

  // VIPS_INTERPRETATION_sRGB is 22, VIPS_FORMAT_UCHAR 0.
  var rgba = vips.ref(image);
  rgba = step(rgba, 'vips_colourspace', [22]);
  if (vips.call('vips_image_get_format', rgba) != 0) {
    rgba = step(rgba, 'vips_cast', [0]);
  }
  if (vips.call('vips_image_get_bands', rgba) == 3) {
    rgba = step(rgba, 'vips_bandjoin_const1', [255.0]);
  }
  try {
    final length = arena<Size>();
    final bytes = vips.vips
        .lookupFunction<
          Pointer<Uint8> Function(Pointer, Pointer<Size>),
          Pointer<Uint8> Function(Pointer, Pointer<Size>)
        >('vips_image_write_to_memory')(rgba, length);
    if (bytes == nullptr) throw StateError(vips.error());
    final pixels = Uint8List.fromList(bytes.asTypedList(length.value));
    vips.free(bytes);
    return (
      width: vips.call('vips_image_get_width', rgba),
      height: vips.call('vips_image_get_height', rgba),
      rgba: pixels,
    );
  } finally {
    vips.unref(rgba);
  }
}).$1;

/// libvips's calls that a decode makes, in one arena.
class _Vips {
  new(this.vips, this.arena)
    : _unref = _glib(vips, 'libgobject-2.0-0.dll')
          .lookupFunction<Void Function(Pointer), void Function(Pointer)>(
            'g_object_unref',
          ),
      _ref = _glib(vips, 'libgobject-2.0-0.dll')
          .lookupFunction<Pointer Function(Pointer), Pointer Function(Pointer)>(
            'g_object_ref',
          ),
      free = _glib(vips, 'libglib-2.0-0.dll')
          .lookupFunction<Void Function(Pointer), void Function(Pointer)>(
            'g_free',
          );

  final DynamicLibrary vips;
  final Arena arena;
  final void Function(Pointer) _unref;
  final Pointer Function(Pointer) _ref;
  final void Function(Pointer) free;

  // GLib's own on Windows, where a library does not export its dependencies'.
  static DynamicLibrary _glib(DynamicLibrary vips, String dll) =>
      Platform.isWindows ? DynamicLibrary.open(dll) : vips;

  void unref(Pointer image) => _unref(image);
  Pointer ref(Pointer image) => _ref(image);

  int call(String name, Pointer image) =>
      vips.lookupFunction<Int Function(Pointer), int Function(Pointer)>(name)(
        image,
      );

  _Str text(String s) => s.toNativeUtf8(allocator: arena);

  String error() {
    final text = vips
        .lookupFunction<_Str Function(), _Str Function()>('vips_error_buffer')()
        .toDartString()
        .trim();
    vips.lookupFunction<Void Function(), void Function()>('vips_error_clear')();
    return text;
  }
}

/// [use] of the file at [path], or of [jpeg] when given, shrunk until its
/// short side is at most [tier], upright, or null with why there is none.
(T?, String?) _thumbnail<T>(
  String library,
  String path,
  int tier,
  T Function(_Vips vips, Pointer image, Arena arena) use, {
  Uint8List? jpeg,
}) => using((arena) {
  final vips = _Vips(DynamicLibrary.open(library), arena);
  final file = vips.text(path);
  final length = jpeg?.length ?? 0;
  final input = jpeg == null ? nullptr : arena<Uint8>(length);
  if (jpeg != null) input.asTypedList(length).setAll(0, jpeg);
  final header = jpeg == null
      ? vips.vips.lookupFunction<
          Pointer Function(_Str, VarArgs<(Pointer,)>),
          Pointer Function(_Str, Pointer)
        >('vips_image_new_from_file')(file, nullptr)
      : vips.vips.lookupFunction<
          Pointer Function(Pointer, Size, _Str, VarArgs<(Pointer,)>),
          Pointer Function(Pointer, int, _Str, Pointer)
        >('vips_image_new_from_buffer')(input, length, vips.text(''), nullptr);
  if (header == nullptr) return (null, vips.error());
  final (w, h) = (
    vips.call('vips_image_get_width', header),
    vips.call('vips_image_get_height', header),
  );
  vips.unref(header);
  if (w * h > 300000000) return (null, '$w × $h is over 300 MP');
  // The long side of the box whose short side is the tier: the image may
  // turn upright as it shrinks.
  final box = (max(w, h) * min(1.0, tier / min(w, h))).round();
  final out = arena<Pointer>();
  final (height, size) = (vips.text('height'), vips.text('size'));
  // VIPS_SIZE_DOWN is 2.
  final made = jpeg == null
      ? vips.vips.lookupFunction<
          Int Function(
            _Str,
            _Ptr,
            Int,
            VarArgs<(_Str, Int, _Str, Int, Pointer)>,
          ),
          int Function(_Str, _Ptr, int, _Str, int, _Str, int, Pointer)
        >('vips_thumbnail')(file, out, box, height, box, size, 2, nullptr)
      : vips.vips.lookupFunction<
          Int Function(
            Pointer,
            Size,
            _Ptr,
            Int,
            VarArgs<(_Str, Int, _Str, Int, Pointer)>,
          ),
          int Function(Pointer, int, _Ptr, int, _Str, int, _Str, int, Pointer)
        >('vips_thumbnail_buffer')(
          input,
          length,
          out,
          box,
          height,
          box,
          size,
          2,
          nullptr,
        );
  if (made != 0) throw StateError(vips.error());
  try {
    return (use(vips, out.value, arena), null);
  } finally {
    vips.unref(out.value);
  }
});
