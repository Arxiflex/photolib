import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:photolib_data/photolib_data.dart'
    show KernelError, TileCache, TileCipher;

/// The disk cache of encoded thumbnails (docs/10-client-app.md §3.4, T2): a
/// file per key, a PLB envelope under the cache key (docs/21 §3) that a
/// [TileCipher] seals and opens on a worker, at most [maxBytes] on disk with
/// the index, the least recently used evicted first.
///
/// The index, `thumb_cache_index`, is a journal of checksummed records. Opening
/// keeps its valid prefix and reconciles it with the files, adopting those it
/// does not know and deleting strays; a damaged entry is dropped when read. So
/// a torn or corrupt index, a damaged, lost or foreign file costs entries,
/// never the cache.
class DiskCache implements TileCache {
  new _(this.dir, this.maxBytes, this._cipher, this._entries, this._indexBytes)
    : _entryBytes = _entries.values.fold(0, (a, b) => a + b);

  /// The directory of the entries and the index.
  final String dir;

  /// The most bytes it keeps on disk, the index included.
  final int maxBytes;
  final TileCipher _cipher;
  // File sizes, the least recently used first: maps keep insertion order.
  final Map<String, int> _entries;
  int _entryBytes;
  int _indexBytes;
  var _records = 0;
  var _temp = 0;
  var _flushing = false;
  final _pending = BytesBuilder();
  Uint8List? _rewrite;
  Future<void> _io = Future.value();
  var _busy = 0;
  Completer<void>? _idle;
  Future<void>? _closed;

  static final _key = RegExp(r'^\w[\w.-]{0,199}$');
  static const _index = 'thumb_cache_index';
  static const _removed = 0xffffffff;
  // PLT3, sealed; the plaintext PLT2 entries of earlier builds are damaged.
  static const _entryMagic = [0x50, 0x4c, 0x54, 0x33];
  static const _indexMagic = [0x50, 0x4c, 0x49, 0x31]; // PLI1

  /// The bytes on disk, the index included.
  int get bytes => _entryBytes + _indexBytes;

  /// Opens the cache in [dir], creating it, and heals what a crash, a full
  /// disk or another program left there; the reading runs on an isolate.
  static Future<DiskCache> open(
    String dir,
    TileCipher cipher, {
    int maxBytes = 1 << 30,
  }) async {
    final (entries, valid, records, healed) = await Isolate.run(
      () => _load(dir),
    );
    final cache = DiskCache._(dir, maxBytes, cipher, entries, valid)
      .._records = records;
    if (healed || records > 2 * entries.length + 1024) cache._compact();
    await cache._evict();
    return cache;
  }

  @override
  bool contains(String key) => _entries.containsKey(key);

  @override
  Future<Uint8List?> get(String key) => _run<Uint8List?>(() async {
    if (!_entries.containsKey(key)) return null;
    try {
      final data = await File('$dir/$key').readAsBytes();
      if (_starts(data, _entryMagic)) {
        final tile = await _cipher.open(
          _name(key),
          Uint8List.sublistView(data, 4),
        );
        // The store is locked: kept for after.
        if (tile == null) return null;
        if (_entries.remove(key) case final size?) {
          _entryBytes += data.length - size;
          _entries[key] = data.length;
          _log(key, data.length);
        }
        return tile;
      }
    } on FileSystemException {
      // Lost: forgotten below.
    } on KernelError {
      // Damaged, or sealed by another store: forgotten below.
    }
    await _remove(key);
    return null;
  });

  /// Keeps [payload] under [key], a file name of letters, digits, `.`, `-`
  /// and `_` that starts with a letter, digit or `_`.
  @override
  Future<void> put(String key, Uint8List payload) async {
    if (!_key.hasMatch(key) || key == _index) throw ArgumentError.value(key);
    await _run(() async {
      final envelope = await _cipher.seal(_name(key), payload);
      if (envelope == null) return;
      final data = BytesBuilder(copy: false)
        ..add(_entryMagic)
        ..add(envelope);
      if (data.length > maxBytes) return;
      final size = data.length;
      final temp = File('$dir/~${_temp++}');
      try {
        await temp.writeAsBytes(data.takeBytes());
        await temp.rename('$dir/$key');
      } on FileSystemException {
        await _delete(temp);
        return;
      }
      _entryBytes += size - (_entries.remove(key) ?? 0);
      _entries[key] = size;
      _log(key, size);
      await _evict();
    });
  }

  @override
  Future<void> remove(String key) => _run(() => _remove(key));

  /// Waits for the reads and writes under way, then writes what the index
  /// still holds in memory. A closed cache reads and writes nothing more.
  Future<void> close() => _closed ??= () async {
    if (_busy > 0) await (_idle = Completer()).future;
    _flush();
    await _io;
  }();

  // [op], unless the cache is closed; [close] waits for it.
  Future<T?> _run<T>(Future<T> Function() op) async {
    if (_closed != null) return null;
    _busy++;
    try {
      return await op();
    } finally {
      if (--_busy == 0) _idle?.complete();
    }
  }

  Future<void> _remove(String key) async {
    final size = _entries.remove(key);
    if (size == null) return;
    _entryBytes -= size;
    _log(key, _removed);
    await _delete(File('$dir/$key'));
  }

  Future<void> _evict() async {
    while (bytes > maxBytes && _entries.isNotEmpty) {
      await _remove(_entries.keys.first);
    }
    if (bytes > maxBytes) _compact();
  }

  void _log(String key, int size) {
    final record = _record(key, size);
    _pending.add(record);
    _indexBytes += record.length;
    if (++_records > 2 * _entries.length + 1024) _compact();
    _flush();
  }

  // Replaces the journal with one record per entry. Records logged later are
  // appended to the new journal by the same write.
  void _compact() {
    final data = BytesBuilder(copy: false)..add(_indexMagic);
    for (final MapEntry(:key, :value) in _entries.entries) {
      data.add(_record(key, value));
    }
    final rewrite = _rewrite = data.takeBytes();
    _pending.clear();
    _indexBytes = rewrite.length;
    _records = _entries.length;
    _flush();
  }

  void _flush() {
    if (_flushing) return;
    _flushing = true;
    _io = _io.then((_) async {
      _flushing = false;
      final rewrite = _rewrite;
      final records = _pending.takeBytes();
      _rewrite = null;
      final index = File('$dir/$_index');
      try {
        if (rewrite != null) {
          await File('$dir/~index').writeAsBytes(rewrite);
          await File('$dir/~index').rename(index.path);
        }
        if (records.isNotEmpty) {
          await index.writeAsBytes(records, mode: FileMode.append);
        }
      } on FileSystemException {
        // The next open heals the index.
      }
    });
  }

  static Future<void> _delete(File file) async {
    try {
      // deletion-ok: a tile of the app's own cache
      await file.delete();
    } on FileSystemException {
      // Gone already, or the next open deletes it.
    }
  }

  // The vault object name a tile's key is bound to, as in browsers.
  static String _name(String key) => 'thumbnails/$key';

  static bool _starts(Uint8List data, List<int> magic) =>
      data.length >= 4 &&
      Iterable<int>.generate(4).every((i) => data[i] == magic[i]);

  // Key length, key, size and the FNV-1a of those.
  static Uint8List _record(String key, int size) {
    final body = [key.length, ...key.codeUnits, ..._uint32(size)];
    return Uint8List.fromList([...body, ..._uint32(_fnv(body))]);
  }

  static Uint8List _uint32(int v) =>
      (ByteData(4)..setUint32(0, v, Endian.little)).buffer.asUint8List();

  static int _fnv(List<int> data) {
    var h = 0x811c9dc5;
    for (final b in data) {
      h = ((h ^ b) * 0x01000193) & 0xffffffff;
    }
    return h;
  }

  /// The entries, the length of the index's valid prefix, its records, and
  /// whether anything had to be healed.
  static Future<(Map<String, int>, int, int, bool)> _load(String dir) async {
    await Directory(dir).create(recursive: true);
    final index = File('$dir/$_index');
    // root-isolate-ok: it runs on an isolate of its own.
    final data = index.existsSync() ? index.readAsBytesSync() : Uint8List(0);
    final entries = <String, int>{};
    var valid = 0;
    var records = 0;
    if (_starts(data, _indexMagic)) {
      final view = ByteData.sublistView(data);
      for (var at = 4; at < data.length; records++) {
        final end = at + data[at] + 9;
        if (data[at] == 0 || end > data.length) break;
        final key = String.fromCharCodes(data, at + 1, end - 8);
        final size = view.getUint32(end - 8, Endian.little);
        if (view.getUint32(end - 4, Endian.little) !=
                _fnv(Uint8List.sublistView(data, at, end - 4)) ||
            !_key.hasMatch(key)) {
          break;
        }
        entries.remove(key);
        if (size != _removed) entries[key] = size;
        at = valid = end;
      }
      if (valid == 0) valid = 4;
    }
    var healed = valid != data.length || data.isEmpty;

    final files = <String, File>{};
    await for (final entry in Directory(dir).list()) {
      final name = entry.uri.pathSegments.lastWhere((s) => s.isNotEmpty);
      if (name == _index) continue;
      if (entry is File && _key.hasMatch(name)) {
        files[name] = entry;
      } else {
        try {
          // deletion-ok: what is no tile in the cache's own directory
          await entry.delete(recursive: true);
        } on FileSystemException {
          // Gone already, as another writer's temporary file it renamed.
        }
        healed = true;
      }
    }
    entries.removeWhere((key, _) {
      final lost = !files.containsKey(key);
      healed |= lost;
      return lost;
    });
    // Files the index does not know, oldest first, as the least recently used.
    final strays =
        [
            for (final MapEntry(:key, :value) in files.entries)
              // root-isolate-ok: as above.
              if (!entries.containsKey(key)) (key, value.statSync()),
          ].where((s) => s.$2.type != FileSystemEntityType.notFound).toList()
          ..sort((a, b) => a.$2.modified.compareTo(b.$2.modified));
    healed |= strays.isNotEmpty;
    return (
      Map.fromEntries([
        for (final (key, stat) in strays) MapEntry(key, stat.size),
        ...entries.entries,
      ]),
      valid,
      records,
      healed,
    );
  }
}
