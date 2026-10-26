import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:photolib/core/logging.dart';
import 'package:photolib_data/photolib_data.dart' show KernelError;

/// The app's log store, in the app support directory's `logs/`.
LogStore openLogStore({LogSeal? seal}) => LogFile(
  getApplicationSupportDirectory().then((dir) => '${dir.path}/logs'),
  seal: seal,
);

/// The operating system and device, without names.
Map<String, Object?> platformInfo() => {
  'os': Platform.operatingSystem,
  'osVersion': Platform.operatingSystemVersion,
  'dartRuntime': Platform.version,
  'processors': Platform.numberOfProcessors,
  'locale': Platform.localeName,
};

/// Prints [record] where `flutter run` and the platform's log show it.
void printLog(LogRecord record) => debugPrint(record.toJson());

/// Logs errors nothing on the root isolate caught.
void watchPlatform() {
  const log = Logger('photolib.app');
  Isolate.current.addErrorListener(
    RawReceivePort((List<Object?> pair) {
      log.error(
        'uncaught isolate error',
        error: pair[0],
        stackTrace: StackTrace.fromString('${pair[1]}'),
      );
    }).sendPort,
  );
}

/// The log of a native build in [directory], as JSON lines: `photolib.log`,
/// then up to [files] − 1 older ones of at most [maxBytes] each, the oldest
/// dropped (ADR-0115). Records wait in memory until the directory is known.
/// With a [seal], as in release builds, the files are `photolib.plb` and its
/// elders, each batch a PLB envelope after its length (4 bytes, big-endian),
/// and the plaintext files of an earlier build are deleted.
class LogFile implements LogStore {
  /// The log in [directory].
  new(this.directory, {this.seal, this.maxBytes = 2 << 20, this.files = 5}) {
    directory
        .ignore(); // Without a directory, as in tests, records stay unwritten.
  }

  /// Where the files are.
  final Future<String> directory;

  /// What seals the records at rest, if anything.
  final LogSeal? seal;

  /// The size at which a file rotates.
  final int maxBytes;

  /// How many files are kept.
  final int files;

  final _waiting = <String>[];
  Future<void> _writes = Future.value();
  IOSink? _sink;
  var _size = 0;

  /// Complete once every record added so far is written.
  Future<void> get flushed => _writes;

  @override
  void add(LogRecord record) {
    _waiting.add('${record.toJson()}\n');
    if (_waiting.length > 1) return;
    // A failed write must not end the log: the next batch tries again.
    _writes = _writes.then((_) => _write()).catchError((Object _) {});
  }

  @override
  Future<List<String>> lines() async {
    await flushed;
    final dir = await directory;
    return [
      for (var i = files - 1; i >= 0; i--)
        ...?await _ifThere(switch (seal) {
          null => File(_path(dir, i)).readAsLines(),
          final seal => File(
            _path(dir, i),
          ).readAsBytes().then((bytes) => _unseal(seal, bytes)),
        }),
    ];
  }

  Future<void> _write() async {
    final batch = [..._waiting];
    _waiting.clear();
    final dir = await directory;
    var sink = _sink ??= await _start(dir);
    // Lines go in runs that fit the file, each run one envelope when sealed.
    final run = BytesBuilder(copy: false);
    for (final line in batch) {
      final bytes = utf8.encode(line);
      if ((_size > 0 || run.isNotEmpty) &&
          _size + _framed(run.length + bytes.length) > maxBytes) {
        await _append(sink, run.takeBytes());
        sink = _sink = await _rotate(sink, dir);
      }
      run.add(bytes);
    }
    await _append(sink, run.takeBytes());
    await sink.flush();
  }

  Future<IOSink> _start(String dir) async {
    await Directory(dir).create(recursive: true);
    final file = File(_path(dir, 0));
    if (seal != null) await _open(dir, file);
    _size = await _ifThere(file.length()) ?? 0;
    return file.openWrite(mode: FileMode.append);
  }

  // No plaintext at rest in a release build (ADR-0057), and no envelope cut
  // short by a crash before the next one.
  Future<void> _open(String dir, File file) async {
    for (var i = 0; i < files; i++) {
      // deletion-ok: the app's own log files
      await _ifThere(File(_path(dir, i, 'log')).delete());
    }
    final bytes = await _ifThere(file.readAsBytes());
    if (bytes == null) return;
    final whole = _envelopes(bytes).fold(0, (n, e) => n + 4 + e.length);
    if (whole == bytes.length) return;
    final cut = await file.open(mode: FileMode.append);
    await cut.truncate(whole);
    await cut.close();
  }

  Future<void> _append(IOSink sink, Uint8List run) async {
    if (run.isEmpty) return;
    var bytes = run;
    if (seal case final seal?) {
      final envelope = await seal.seal(run);
      bytes = Uint8List(4 + envelope.length)
        ..setRange(4, 4 + envelope.length, envelope);
      ByteData.sublistView(bytes).setUint32(0, envelope.length);
      assert(bytes.length == _framed(run.length), 'rotation miscounts');
    }
    sink.add(bytes);
    _size += bytes.length;
  }

  // An envelope adds its length, an 88-byte header and a 16-byte tag per
  // 64 KiB chunk (docs/dev/crypto-v1.md).
  int _framed(int n) =>
      seal == null ? n : 4 + 88 + n + 16 * max(1, (n + 0xffff) >> 16);

  Future<IOSink> _rotate(IOSink sink, String dir) async {
    await sink.close();
    for (var i = files - 1; i > 0; i--) {
      await _ifThere(File(_path(dir, i - 1)).rename(_path(dir, i)));
    }
    _size = 0;
    return File(_path(dir, 0)).openWrite();
  }

  String _path(String dir, int i, [String? extension]) {
    extension ??= seal == null ? 'log' : 'plb';
    return i == 0 ? '$dir/photolib.$extension' : '$dir/photolib.$i.$extension';
  }
}

/// What [io] gives, or null when its path is not there.
Future<T?> _ifThere<T>(Future<T> io) async {
  try {
    return await io;
  } on PathNotFoundException {
    return null;
  }
}

/// The lines of a sealed log file; an envelope sealed under keys the store
/// no longer has, as before a crypto-erase, is skipped.
Future<List<String>> _unseal(LogSeal seal, Uint8List bytes) async => [
  for (final envelope in _envelopes(bytes))
    ...await seal
        .unseal(envelope)
        .then((run) => const LineSplitter().convert(utf8.decode(run)))
        .onError<KernelError>((_, _) => const []),
];

/// The envelopes of a sealed log file, each after its length, up to the
/// first one cut short.
Iterable<Uint8List> _envelopes(Uint8List bytes) sync* {
  final view = ByteData.sublistView(bytes);
  for (var at = 0; at + 4 <= bytes.length;) {
    final end = at + 4 + view.getUint32(at);
    if (end > bytes.length) return;
    yield Uint8List.sublistView(bytes, at + 4, end);
    at = end;
  }
}
