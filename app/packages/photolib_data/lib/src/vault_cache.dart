import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:photolib_data/src/vault.dart';

/// The disk tier of thumbnails (docs/10-client-app.md §3.4, T2): encoded tiles by key.
abstract interface class TileCache {
  /// Whether a tile is under [key], unread.
  bool contains(String key);

  /// The tile under [key], or null.
  Future<Uint8List?> get(String key);

  Future<void> put(String key, Uint8List tile);

  Future<void> remove(String key);
}

/// Thumbnails' disk tier where there are no files for one, in browsers (ADR-0116): each tile a PLB envelope in
/// [Vault]'s store under the cache key, at most [maxBytes] of them, the least recently used evicted first. Their keys
/// and sizes are an object too, written a second after a change: a lost list loses tiles, never the cache.
class VaultCache implements TileCache {
  VaultCache._(this._vault, this.maxBytes, this._sizes)
    : _bytes = _sizes.values.fold(0, (a, b) => a + b);

  static Future<VaultCache> open(Vault vault, {int maxBytes = 64 << 20}) async {
    final sizes = <String, int>{};
    try {
      for (final entry in jsonDecode(utf8.decode((await vault.read(_list))!))) {
        if (entry case [String key, int size]) sizes[key] = size;
      }
    } on Object {
      // None yet, or lost.
    }
    return VaultCache._(vault, maxBytes, sizes);
  }

  final Vault _vault;
  final int maxBytes;
  // Sizes, the least recently used first: maps keep insertion order.
  final Map<String, int> _sizes;
  int _bytes;
  Timer? _save;

  static const _list = 'thumbnails';

  @override
  bool contains(String key) => _sizes.containsKey(key);

  @override
  Future<Uint8List?> get(String key) async {
    if (!_sizes.containsKey(key)) return null;
    try {
      if (await _vault.read('$_list/$key') case final tile?) {
        _sizes[key] = _sizes.remove(key)!;
        return tile;
      }
    } on Object {
      // Damaged, or the store is locked.
    }
    return null;
  }

  @override
  Future<void> put(String key, Uint8List tile) async {
    try {
      await _vault.write('$_list/$key', tile);
    } on Object {
      return;
    }
    _bytes += tile.length - (_sizes.remove(key) ?? 0);
    _sizes[key] = tile.length;
    while (_bytes > maxBytes && _sizes.isNotEmpty) {
      await remove(_sizes.keys.first);
    }
    _changed();
  }

  @override
  Future<void> remove(String key) async {
    final size = _sizes.remove(key);
    if (size == null) return;
    _bytes -= size;
    _changed();
    try {
      await _vault.delete('$_list/$key');
    } on Object {
      // Left for the store's erase.
    }
  }

  /// Writes the list now if it changed.
  Future<void> close() async {
    if (_save?.isActive ?? false) {
      _save!.cancel();
      await _write();
    }
  }

  void _changed() => _save ??= Timer(const Duration(seconds: 1), _write);

  Future<void> _write() async {
    _save = null;
    try {
      await _vault.write(
        _list,
        utf8.encode(
          jsonEncode([
            for (final e in _sizes.entries) [e.key, e.value],
          ]),
        ),
      );
    } on Object {
      // Written with the next change.
    }
  }
}
