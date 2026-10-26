// root-isolate-ok: calls that read a constant
import 'dart:ffi';
import 'dart:io';

// root-isolate-ok: calls that read a constant
import 'package:ffi/ffi.dart';

/// The device's RAM in bytes, or null where it cannot be read.
int? physicalMemory() {
  try {
    if (Platform.isWindows) return _windows();
    // _SC_PHYS_PAGES and _SC_PAGESIZE of bionic, glibc and Darwin.
    final (pages, size) = Platform.isAndroid
        ? (0x62, 0x27)
        : Platform.isLinux
        ? (85, 30)
        : (200, 29);
    final sysconf = DynamicLibrary.process()
        .lookupFunction<Long Function(Int), int Function(int)>(
          'sysconf',
          isLeaf: true,
        );
    final bytes = sysconf(pages) * sysconf(size);
    return bytes > 0 ? bytes : null;
  } on Object {
    return null;
  }
}

int? _windows() {
  // MEMORYSTATUSEX: its length first, the physical memory at byte 8.
  final status = calloc<Uint64>(8)..cast<Uint32>().value = 64;
  try {
    final get = DynamicLibrary.open('kernel32.dll')
        .lookupFunction<
          Int32 Function(Pointer<Uint64>),
          int Function(Pointer<Uint64>)
        >('GlobalMemoryStatusEx', isLeaf: true);
    return get(status) == 0 ? null : status[1];
  } finally {
    calloc.free(status);
  }
}
