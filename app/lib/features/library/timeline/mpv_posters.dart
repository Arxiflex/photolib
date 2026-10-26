// root-isolate-ok: libmpv is loaded and called only inside Isolate.run.
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

// root-isolate-ok: as dart:ffi above.
import 'package:ffi/ffi.dart';

import 'package:photolib/features/library/timeline/pipeline.dart';
import 'package:photolib/features/library/timeline/thumbnails.dart';

/// Poster frames of videos on Linux from libmpv, the stack that plays them
/// (docs/10-client-app.md §4.2 "one stack", ADR-0112): the first frame,
/// upright and with its short side at the tier but never larger, as JPEG,
/// which libmpv's image output writes on an isolate; null without [library].
/// libmpv reads only the file: no configuration, scripts or other protocol.
Future<Thumbnailer?> mpvPosters({String library = 'libmpv.so.2'}) async {
  if (!await Isolate.run(() => _opens(library))) return null;
  return Thumbnailer('mpv', (item, tier, _) async {
    if (!item.video || !item.uri.isScheme('file')) return null;
    final path = item.uri.toFilePath();
    final out = await Directory.systemTemp.createTemp('poster');
    try {
      final error = await Isolate.run(
        () => _poster(library, path, out.path, tier),
      );
      try {
        return Pixels.encoded(
          await File('${out.path}/00000001.jpg').readAsBytes(),
        );
      } on FileSystemException {
        throw NoThumbnail(video: true, cause: error ?? 'no picture');
      }
    } finally {
      // deletion-ok: the poster's temporary directory
      await out.delete(recursive: true);
    }
  });
}

bool _opens(String library) {
  try {
    DynamicLibrary.open(library);
    return true;
    // DynamicLibrary.open says a library is missing only with this error.
    // ignore: avoid_catching_errors
  } on ArgumentError {
    return false;
  }
}

typedef _Handle = Pointer<Void>;
typedef _Str = Pointer<Utf8>;

// Runs on an isolate: writes the frame into [out], else says why it did not.
String? _poster(String library, String path, String out, int tier) {
  final mpv = DynamicLibrary.open(library);
  final create = mpv.lookupFunction<_Handle Function(), _Handle Function()>(
    'mpv_create',
  );
  final option = mpv
      .lookupFunction<
        Int Function(_Handle, _Str, _Str),
        int Function(_Handle, _Str, _Str)
      >('mpv_set_option_string');
  final initialize = mpv
      .lookupFunction<Int Function(_Handle), int Function(_Handle)>(
        'mpv_initialize',
      );
  final command = mpv
      .lookupFunction<
        Int Function(_Handle, Pointer<_Str>),
        int Function(_Handle, Pointer<_Str>)
      >('mpv_command');
  // mpv_event: its id, then its data at offset 16.
  final wait = mpv
      .lookupFunction<
        Pointer<Int32> Function(_Handle, Double),
        Pointer<Int32> Function(_Handle, double)
      >('mpv_wait_event');
  final message = mpv.lookupFunction<_Str Function(Int), _Str Function(int)>(
    'mpv_error_string',
  );
  final destroy = mpv
      .lookupFunction<Void Function(_Handle), void Function(_Handle)>(
        'mpv_terminate_destroy',
      );
  final handle = create();
  try {
    return using((arena) {
      _Str text(String s) => s.toNativeUtf8(allocator: arena);
      for (final (name, value) in [
        ('config', 'no'),
        ('load-scripts', 'no'),
        ('ytdl', 'no'),
        ('demuxer-lavf-o', 'protocol_whitelist=file'),
        ('audio', 'no'),
        ('sub', 'no'),
        ('hwdec', 'no'),
        ('vd-lavc-threads', '1'),
        ('frames', '1'),
        ('vo', 'image'),
        ('vo-image-format', 'jpg'),
        ('vo-image-outdir', out),
        (
          'vf',
          'lavfi-scale=w=[if(lt(iw,ih),min(iw,$tier),-2)]'
              ':h=[if(lt(iw,ih),-2,min(ih,$tier))]',
        ),
      ]) {
        option(handle, text(name), text(value));
      }
      if (initialize(handle) < 0) return 'libmpv did not start';
      final argv = arena<_Str>(3);
      argv[0] = text('loadfile');
      argv[1] = text(path);
      argv[2] = nullptr;
      command(handle, argv);
      final end = DateTime.now().add(const Duration(seconds: 30));
      while (DateTime.now().isBefore(end)) {
        final event = wait(handle, 1);
        // MPV_EVENT_END_FILE, whose data is its reason and error.
        if (event[0] != 7) continue;
        final error = Pointer<Int32>.fromAddress(
          Pointer<IntPtr>.fromAddress(event.address + 16).value,
        )[1];
        return error < 0 ? message(error).toDartString() : null;
      }
      return 'timed out';
    });
  } finally {
    destroy(handle);
  }
}
