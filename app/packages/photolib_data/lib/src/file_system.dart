import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'package:photolib_data/src/folder_indexer.dart';

/// The desktop's file system, where a folder's root is its absolute path.
const FolderFiles folderFiles = _Files();

class _Files implements FolderFiles {
  const _Files();

  @override
  Future<List<FileEntry>?> list(String root, String dir) async {
    final base = nativePath(root, dir);
    try {
      return [
        for (final e in Directory(base).listSync(followLinks: false))
          if (e is Directory || e is File)
            (
              name: relativePath(base, e.path)!,
              dir: e is Directory,
              info: () async => statFile(e.path),
            ),
      ];
    } on FileSystemException {
      return null;
    }
  }

  @override
  Future<bool?> isEmpty(String root) async {
    try {
      return await Directory(root).list().isEmpty;
    } on FileSystemException {
      return null;
    }
  }

  @override
  Future<bool> caseSensitive(String root) => isCaseSensitive(root);

  @override
  Future<FileInfo?> stat(String root, String path) async =>
      statFile(nativePath(root, path));

  @override
  Future<String> read(String root, String path) async {
    try {
      return File(nativePath(root, path)).readAsStringSync();
    } on FileSystemException {
      return '';
    }
  }
}

final _sep = Platform.pathSeparator;

String _under(String root) => root.endsWith(_sep) ? root : '$root$_sep';

/// The native path of [dir], `/`-separated under [root].
String nativePath(String root, String dir) =>
    dir.isEmpty ? root : '${_under(root)}${dir.replaceAll('/', _sep)}';

/// The `/`-separated path of [path] under [root], or null when it is not there.
String? relativePath(String root, String path) => path == root
    ? ''
    : path.startsWith(_under(root))
    ? path.substring(_under(root).length).replaceAll(_sep, '/')
    : null;

/// The [FileInfo] of [path], or null when it cannot be read. dart:io has no file ids, so this asks the OS.
FileInfo? statFile(String path) => using(
  (arena) => Platform.isWindows
      ? _windows(path, arena)
      : Platform.isMacOS
      ? _macos(path, arena)
      : _linux(path, arena),
);

// statx(2), whose struct has the same layout on every architecture.
final _statx = DynamicLibrary.process()
    .lookupFunction<
      Int32 Function(Int32, Pointer<Utf8>, Int32, Uint32, Pointer<Uint8>),
      int Function(int, Pointer<Utf8>, int, int, Pointer<Uint8>)
    >('statx');

FileInfo? _linux(String path, Arena arena) {
  final buf = arena<Uint8>(256);
  // AT_FDCWD, AT_SYMLINK_NOFOLLOW, STATX_BASIC_STATS
  if (_statx(-100, path.toNativeUtf8(allocator: arena), 0x100, 0x7ff, buf) !=
      0) {
    return null;
  }
  final b = buf.asTypedList(256).buffer.asByteData();
  return (
    size: b.getUint64(40, Endian.host),
    mtime:
        b.getInt64(112, Endian.host) * 1000 +
        b.getUint32(120, Endian.host) ~/ 1000000,
    // The device and inode.
    id:
        '${b.getUint32(136, Endian.host)}:${b.getUint32(140, Endian.host)}:'
        '${b.getUint64(32, Endian.host)}',
  );
}

// lstat(2) with 64-bit inodes, which Intel Macs export under a suffixed name.
final _lstat = () {
  final libc = DynamicLibrary.process();
  return libc.lookupFunction<
    Int32 Function(Pointer<Utf8>, Pointer<Uint8>),
    int Function(Pointer<Utf8>, Pointer<Uint8>)
  >(libc.providesSymbol(r'lstat$INODE64') ? r'lstat$INODE64' : 'lstat');
}();

FileInfo? _macos(String path, Arena arena) {
  final buf = arena<Uint8>(144);
  if (_lstat(path.toNativeUtf8(allocator: arena), buf) != 0) return null;
  final b = buf.asTypedList(144).buffer.asByteData();
  return (
    size: b.getInt64(96, Endian.host),
    mtime:
        b.getInt64(48, Endian.host) * 1000 +
        b.getInt64(56, Endian.host) ~/ 1000000,
    id: '${b.getInt32(0, Endian.host)}:${b.getUint64(8, Endian.host)}',
  );
}

final _kernel32 = DynamicLibrary.open('kernel32.dll');
final _createFile = _kernel32
    .lookupFunction<
      IntPtr Function(
        Pointer<Utf16>,
        Uint32,
        Uint32,
        Pointer<Void>,
        Uint32,
        Uint32,
        IntPtr,
      ),
      int Function(Pointer<Utf16>, int, int, Pointer<Void>, int, int, int)
    >('CreateFileW');
final _fileInformation = _kernel32
    .lookupFunction<
      Int32 Function(IntPtr, Pointer<Uint8>),
      int Function(int, Pointer<Uint8>)
    >('GetFileInformationByHandle');
final _closeHandle = _kernel32
    .lookupFunction<Int32 Function(IntPtr), int Function(int)>('CloseHandle');

FileInfo? _windows(String path, Arena arena) {
  // FILE_READ_ATTRIBUTES, any sharing, OPEN_EXISTING, FILE_FLAG_BACKUP_SEMANTICS | FILE_FLAG_OPEN_REPARSE_POINT
  final handle = _createFile(
    path.toNativeUtf16(allocator: arena),
    0x80,
    7,
    nullptr,
    3,
    0x02200000,
    0,
  );
  if (handle == -1) return null;
  try {
    final buf = arena<Uint8>(52); // BY_HANDLE_FILE_INFORMATION
    if (_fileInformation(handle, buf) == 0) return null;
    final b = buf.asTypedList(52).buffer.asByteData();
    int pair(int at) =>
        b.getUint32(at, Endian.little) << 32 |
        b.getUint32(at + 4, Endian.little);
    final written =
        b.getUint32(24, Endian.little) << 32 | b.getUint32(20, Endian.little);
    return (
      size: pair(32),
      // FILETIME counts 100 ns from 1601.
      mtime: (written - 116444736000000000) ~/ 10000,
      // The volume serial number and the 64-bit file index.
      id: '${b.getUint32(28, Endian.little)}:${pair(44)}',
    );
  } finally {
    _closeHandle(handle);
  }
}

/// Whether the volume of the folder [root] tells names apart by case (git's `core.ignorecase`, probed without
/// writing): not when the first name in it that has a case is, in the other case, the same file. With no such name,
/// as the platform's file systems do by default.
Future<bool> isCaseSensitive(String root) async {
  await for (final entry in Directory(root).list(followLinks: false)) {
    final name = relativePath(root, entry.path)!;
    final other = name.toLowerCase() == name
        ? name.toUpperCase()
        : name.toLowerCase();
    final id = statFile(entry.path)?.id;
    if (other != name && id != null) {
      return statFile(nativePath(root, other))?.id != id;
    }
  }
  return !Platform.isWindows && !Platform.isMacOS;
}

/// Whether [path] is on a network share, whose change events are unreliable (docs/10-client-app.md §8.1).
bool isNetworkShare(String path) {
  if (Platform.isWindows) {
    return path.startsWith(r'\\') ||
        path.length > 1 &&
            path[1] == ':' &&
            using(
              (arena) =>
                  _driveType(
                    '${path.substring(0, 2)}\\'.toNativeUtf16(allocator: arena),
                  ) ==
                  4, // DRIVE_REMOTE
            );
  }
  if (Platform.isMacOS) {
    return using((arena) {
      final buf = arena<Uint8>(2168); // struct statfs
      return _statfs(path.toNativeUtf8(allocator: arena), buf) == 0 &&
          buf.asTypedList(2168).buffer.asByteData().getUint32(64, Endian.host) &
                  0x1000 == // f_flags & MNT_LOCAL
              0;
    });
  }
  try {
    return networkMount(File('/proc/self/mounts').readAsStringSync(), path);
  } on FileSystemException {
    return false;
  }
}

/// Whether the file system mounted nearest above [path] in [mounts], in the format of `/proc/mounts`, is a network one.
bool networkMount(String mounts, String path) {
  var (at, type) = ('', '');
  for (final fields in mounts.split('\n').map((l) => l.split(' '))) {
    if (fields.length < 3) continue;
    final point = fields[1].replaceAllMapped(
      RegExp(r'\\([0-7]{3})'),
      (m) => String.fromCharCode(int.parse(m[1]!, radix: 8)),
    );
    if ((path == point ||
            path.startsWith(point.endsWith('/') ? point : '$point/')) &&
        point.length >= at.length) {
      (at, type) = (point, fields[2]);
    }
  }
  return RegExp(
    r'^(nfs4?|cifs|smb3?|smbfs|9p|afs|ceph|glusterfs|lustre|davfs|fuse\.(sshfs|rclone|s3fs|gvfsd-fuse))$',
  ).hasMatch(type);
}

final _statfs = () {
  final libc = DynamicLibrary.process();
  return libc.lookupFunction<
    Int32 Function(Pointer<Utf8>, Pointer<Uint8>),
    int Function(Pointer<Utf8>, Pointer<Uint8>)
  >(libc.providesSymbol(r'statfs$INODE64') ? r'statfs$INODE64' : 'statfs');
}();

final _driveType = _kernel32
    .lookupFunction<
      Uint32 Function(Pointer<Utf16>),
      int Function(Pointer<Utf16>)
    >('GetDriveTypeW');
