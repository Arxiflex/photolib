import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:photolib_data/src/deletion.dart';
import 'package:photolib_data/src/file_system.dart' show nativePath;
import 'package:photolib_data/src/replica.dart';

/// The trash of desktopTrash.
MediaPlatform folderTrash() => switch (Platform.operatingSystem) {
  'linux' => FreedesktopTrash(),
  'windows' => RecycleBin(),
  _ => appBin,
};

String _file(LocalAssetData item) => nativePath(item.volume, item.path ?? '');

Future<void> _delete(String path) async {
  try {
    await File(path).delete();
  } on PathNotFoundException {
    // Gone already.
  }
}

/// Photolib's own bin, which deletes a file in place when it is purged.
const appBin = AppBin(_deleteFile);

Future<void> _deleteFile(LocalAssetData item) => _delete(_file(item));

/// The freedesktop.org trash (Trash specification 1.0), which Linux file
/// managers list and restore from: a file goes to the home trash when it is
/// on the home trash's file system, else to `.Trash-<uid>` at the top of its
/// own.
class FreedesktopTrash implements MediaPlatform {
  /// The trash under [dataHome] (`$XDG_DATA_HOME`), for the mounts of
  /// [mountInfo] (`/proc/self/mountinfo`) and the user [uid], which are read
  /// unless given.
  FreedesktopTrash({
    String? dataHome,
    String? mountInfo,
    int? uid,
    DateTime Function()? now,
  }) : _home = '${dataHome ?? _dataHome()}/Trash',
       _mounts = _mountPoints(
         mountInfo ?? File('/proc/self/mountinfo').readAsStringSync(),
       ),
       _uid = uid ?? _userId(),
       _now = now ?? DateTime.now;

  final String _home;
  final List<String> _mounts;
  final int _uid;
  final DateTime Function() _now;
  final _private = <String>{};

  @override
  bool get expires => false;

  @override
  bool get restores => true;

  @override
  Future<bool> asksFirst() async => false;

  /// Moves each file to the trash; a failure puts back those moved before it.
  @override
  Future<List<Binned>> trash(List<LocalAssetData> items) async {
    final bins = <String>[];
    try {
      for (final item in items) {
        bins.add(await _trash(_file(item)));
      }
    } on Object {
      for (final (i, bin) in bins.indexed) {
        await _restore(_file(items[i]), bin);
      }
      rethrow;
    }
    return [for (final bin in bins) (bin: bin, expires: null)];
  }

  @override
  Future<void> restore(List<LocalAssetData> items) async {
    for (final item in items) {
      await _restore(_file(item), item.bin ?? '');
    }
  }

  @override
  Future<void> purge(List<LocalAssetData> items) async {
    for (final bin in [for (final i in items) ?i.bin]) {
      await _delete(bin);
      await _delete(_info(bin));
    }
  }

  @override
  Future<void> favorite(
    List<LocalAssetData> items, {
    required bool value,
  }) async {}

  Future<String> _trash(String path) async {
    final top = _mountOf(path);
    final home = _mountOf(_home) == top;
    final trash = home ? _home : '$top/.Trash-$_uid';
    for (final dir in ['files', 'info']) {
      await Directory('$trash/$dir').create(recursive: true);
    }
    // Others may not list what this user deleted on a shared drive.
    if (!home && _private.add(trash)) {
      await Process.run('chmod', ['700', trash]);
    }
    final name = path.substring(path.lastIndexOf('/') + 1);
    final dot = name.lastIndexOf('.');
    final (stem, ext) = dot > 0
        ? (name.substring(0, dot), name.substring(dot))
        : (name, '');
    for (var n = 1; ; n++) {
      final kept = n == 1 ? name : '$stem.$n$ext';
      final info = File('$trash/info/$kept.trashinfo');
      try {
        await info.create(exclusive: true);
      } on FileSystemException {
        continue;
      }
      final at = _now().toIso8601String().substring(0, 19);
      final where = home ? path : path.substring(top.length + 1);
      try {
        await info.writeAsString(
          '[Trash Info]\nPath=${Uri.file(where, windows: false).path}\n'
          'DeletionDate=$at\n',
        );
        await File(path).rename('$trash/files/$kept');
      } on Object {
        await info.delete();
        rethrow;
      }
      return '$trash/files/$kept';
    }
  }

  Future<void> _restore(String path, String bin) async {
    await _moveBack(bin, path);
    await _delete(_info(bin));
  }

  /// The longest mount point [path] is under.
  String _mountOf(String path) => _mounts.firstWhere(
    (m) => m == '/' || path == m || path.startsWith('$m/'),
  );
}

/// Moves [bin] back to [path], over nothing: the empty file made first says
/// that nothing is in the way.
Future<void> _moveBack(String bin, String path) async {
  final place = File(path);
  await place.parent.create(recursive: true);
  try {
    await place.create(exclusive: true);
  } on FileSystemException catch (e) {
    throw FileSystemException('a file is in the way', path, e.osError);
  }
  try {
    await File(bin).rename(path);
  } on Object {
    await place.delete();
    rethrow;
  }
}

/// Windows' Recycle Bin, which Explorer lists and restores from: the shell
/// recycles a file as Explorer's Delete does, to `$R<id>` in the user's folder
/// of its drive's `$Recycle.Bin`, beside an `$I<id>` record of where it was,
/// by which Photolib finds it. A drive without a bin (a network share) keeps
/// its files in Photolib's own bin.
class RecycleBin implements MediaPlatform {
  /// The bin, recycling through [recycle] (the shell) and finding the bin of
  /// a path's drive with [binOf], or null when it has none.
  RecycleBin({
    Future<void> Function(String path)? recycle,
    String? Function(String path)? binOf,
  }) : _recycle = recycle ?? _shellRecycle,
       _binOf = binOf ?? _driveBin;

  final Future<void> Function(String path) _recycle;
  final String? Function(String path) _binOf;

  @override
  bool get expires => false;

  @override
  bool get restores => true;

  @override
  Future<bool> asksFirst() async => false;

  /// Recycles each file; a failure puts back those recycled before it.
  @override
  Future<List<Binned>> trash(List<LocalAssetData> items) async {
    final bins = <String?>[];
    try {
      for (final item in items) {
        final path = _file(item);
        final bin = _binOf(path);
        if (bin != null) {
          await _recycle(path);
          bins.add(
            await _recycled(bin, path) ??
                (throw FileSystemException('no record in the bin', path)),
          );
        } else {
          bins.add(null);
        }
      }
    } on Object {
      for (final (i, bin) in bins.indexed) {
        if (bin != null) await _restore(_file(items[i]), bin);
      }
      rethrow;
    }
    return [for (final bin in bins) (bin: bin, expires: null)];
  }

  @override
  Future<void> restore(List<LocalAssetData> items) async {
    for (final item in items) {
      if (item.bin case final bin?) await _restore(_file(item), bin);
    }
  }

  @override
  Future<void> purge(List<LocalAssetData> items) async {
    for (final item in items) {
      if (item.bin case final bin?) {
        await _delete(bin);
        await _delete(_record(bin));
      } else {
        await _delete(_file(item));
      }
    }
  }

  @override
  Future<void> favorite(
    List<LocalAssetData> items, {
    required bool value,
  }) async {}

  Future<void> _restore(String path, String bin) async {
    await _moveBack(bin, path);
    await _delete(_record(bin));
  }

  /// The `$R` file of the newest record in [bin] of [path], in any of its
  /// users' folders that may be listed.
  static Future<String?> _recycled(String bin, String path) async {
    String? found;
    var newest = -1;
    await for (final user in Directory(bin).list()) {
      try {
        await for (final entry in Directory(user.path).list()) {
          final name = entry.path.split(RegExp(r'[\\/]')).last;
          if (!name.startsWith(r'$I')) continue;
          final bytes = await File(entry.path).readAsBytes();
          final at = bytes.length < 24
              ? -1
              : ByteData.sublistView(bytes).getInt64(16, Endian.little);
          if (recycledFrom(bytes)?.toLowerCase() == path.toLowerCase() &&
              at > newest) {
            newest = at;
            found =
                '${entry.path.substring(0, entry.path.length - name.length)}'
                '\$R${name.substring(2)}';
          }
        }
      } on FileSystemException {
        // Another user's folder, or no folder.
      }
    }
    return found;
  }
}

/// The `$I` record beside the `$R` file [bin].
String _record(String bin) {
  final at = bin.lastIndexOf(r'$R');
  return '${bin.substring(0, at)}\$I${bin.substring(at + 2)}';
}

/// The path an `$I` record of the Recycle Bin says its file was deleted from:
/// UTF-16 after a version (1, Windows Vista to 8.1: 260 characters at 24;
/// 2: its length at 24, then the path), a size and a time; null when it is
/// none of these.
String? recycledFrom(Uint8List bytes) {
  if (bytes.length < 28) return null;
  final data = ByteData.sublistView(bytes);
  final (start, end) = switch (data.getInt64(0, Endian.little)) {
    1 => (24, bytes.length),
    2 => (28, 28 + 2 * data.getInt32(24, Endian.little)),
    _ => (0, 0),
  };
  if (end <= start || end > bytes.length) return null;
  final units = [
    for (var i = start; i + 1 < end; i += 2) data.getUint16(i, Endian.little),
  ];
  final nul = units.indexOf(0);
  return String.fromCharCodes(nul < 0 ? units : units.sublist(0, nul));
}

/// The bin of a path's drive, `X:\$Recycle.Bin`, or null for a network
/// share or a drive without one.
String? _driveBin(String path) {
  if (!RegExp(r'^[A-Za-z]:\\').hasMatch(path)) return null;
  final bin = '${path.substring(0, 3)}\$Recycle.Bin';
  return Directory(bin).existsSync() ? bin : null;
}

/// `SHFILEOPSTRUCTW`.
final class _FileOp extends Struct {
  external Pointer<Void> window;
  @Uint32()
  external int function;
  external Pointer<Uint16> from;
  external Pointer<Uint16> to;
  @Uint16()
  external int flags;
  @Int32()
  external int aborted;
  external Pointer<Void> mappings;
  external Pointer<Uint16> title;
}

final int Function(Pointer<_FileOp>) _shFileOperation =
    DynamicLibrary.open('shell32.dll').lookupFunction<
      Int32 Function(Pointer<_FileOp>),
      int Function(Pointer<_FileOp>)
    >('SHFileOperationW');

/// Recycles [path] as Explorer's Delete does (FO_DELETE with FOF_ALLOWUNDO),
/// silently, but warning before a file the shell cannot recycle would be
/// destroyed (FOF_WANTNUKEWARNING).
Future<void> _shellRecycle(String path) => Future.sync(
  () => using((arena) {
    // Zeroed, so the path ends in the two NULs the shell wants.
    final from = arena<Uint16>(path.length + 2);
    for (var i = 0; i < path.length; i++) {
      from[i] = path.codeUnitAt(i);
    }
    final op = arena<_FileOp>();
    op.ref
      ..function = 3
      ..from = from
      ..flags = 0x4 | 0x10 | 0x40 | 0x400 | 0x4000;
    if (_shFileOperation(op) != 0 || op.ref.aborted != 0) {
      throw FileSystemException('the shell did not recycle it', path);
    }
  }),
);

String _dataHome() =>
    Platform.environment['XDG_DATA_HOME'] ??
    '${Platform.environment['HOME']}/.local/share';

int _userId() =>
    int.tryParse(
      RegExp(r'^Uid:\s+(\d+)', multiLine: true)
              .firstMatch(File('/proc/self/status').readAsStringSync())
              ?.group(1) ??
          '',
    ) ??
    0;

/// The info file of what the trash keeps at [bin], `<trash>/files/<name>`.
String _info(String bin) {
  final slash = bin.lastIndexOf('/');
  final trash = bin.substring(0, bin.lastIndexOf('/', slash - 1));
  return '$trash/info/${bin.substring(slash + 1)}.trashinfo';
}

/// The mount points of a `/proc/self/mountinfo`, longest first.
List<String> _mountPoints(String mountInfo) => [
  for (final line in mountInfo.split('\n'))
    if (line.split(' ') case [_, _, _, _, final point, ...])
      point.replaceAllMapped(
        RegExp(r'\\([0-7]{3})'),
        (m) => String.fromCharCode(int.parse(m.group(1) ?? '0', radix: 8)),
      ),
]..sort((a, b) => b.length.compareTo(a.length));
