// tool/single_writer_lint.dart: the store's own files import each other
// by relative paths.
// ignore_for_file: always_use_package_imports

import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'keys.dart' show KernelError, hex, objectId;
import 'vault.dart';

/// A blob does not fit in what is left of the budget.
class BudgetExceeded implements Exception {
  /// A blob of [need] bytes when only [available] are left.
  const BudgetExceeded(this.need, this.available);

  /// The bytes it takes on disk, sealed.
  final int need;

  /// The bytes the budget has left.
  final int available;

  @override
  String toString() => 'BudgetExceeded: $need bytes, $available left';
}

/// A stream ended or went on at another length than its blob was declared.
class SizeMismatch implements Exception {
  /// The stream of [key] had [seen] bytes, not [declared].
  const SizeMismatch(this.key, this.seen, this.declared);

  /// The blob.
  final String key;

  /// The bytes the stream had when it was found wrong.
  final int seen;

  /// The bytes the blob was declared to have.
  final int declared;

  @override
  String toString() => 'SizeMismatch: $key had $seen of $declared bytes';
}

// What sealing adds (docs/dev/crypto-v1.md, PLB): a header and a tag for each
// 64 KiB of plaintext, measured when the store opens rather than assumed.
class _Envelope {
  const _Envelope(this.base, this.tag);

  static const int _window = 1 << 16;

  final int base;
  final int tag;

  // The bytes of an envelope of [plain] bytes.
  int of(int plain) =>
      plain + base + tag * (max(1, (plain + _window - 1) ~/ _window) - 1);

  // The bytes of a blob of [plain] bytes cut into chunks of [chunk].
  int blob(int plain, int chunk) {
    final full = plain ~/ chunk;
    final rest = plain % chunk;
    return full * of(chunk) + (rest > 0 || full == 0 ? of(rest) : 0);
  }
}

class _Lost implements Exception {
  const _Lost();
}

class _Blob {
  _Blob(this.count, this.plain, this.chunk, this.sealed);

  final int count;
  final int plain;
  final int chunk;
  final int sealed;
}

/// What the device keeps for offline use (docs/10 §11, MOB-15): blobs of
/// bytes by key, each cut into chunks of [chunkSize] and every chunk sealed
/// as a PLB envelope under the vault's cache key (docs/21 §3), bound to its
/// name, so that nothing is at rest in the clear and a ranged read opens only
/// the chunks it needs. Names are hashes of the key. A blob is the chunks
/// `offline/<id>/<n>.<count>.<size>.<chunk>`; one with a chunk missing is the
/// remains of a crash and is swept when the store opens.
///
/// It holds at most [budget] bytes on disk: [put] reserves its blob's bytes
/// before it writes any, so puts that run together never pass it.
class OfflineStore {
  OfflineStore._(
    this._vault,
    this._files,
    this.budget,
    this.chunkSize,
    this._envelope,
    this._blobs,
    this._root,
  ) : _used = _blobs.values.fold(0, (a, b) => a + b.sealed);

  final Vault _vault;
  final StoreFiles _files;

  /// The bytes of a chunk, but the last of a blob.
  final int chunkSize;
  final _Envelope _envelope;
  final Map<String, _Blob> _blobs;
  int _used;
  int _reserved = 0;

  // The directory of its files: one store for each account.
  final String _root;

  /// Opens the store in [files], sweeping what a crash left; the vault must be
  /// unlocked.
  static Future<OfflineStore> open(
    Vault vault,
    StoreFiles files, {
    required int budget,
    int chunkSize = 1 << 20,
    String name = 'offline',
  }) async {
    final root = '$name/';
    final base = (await vault.seal('${root}probe', Uint8List(0))).length;
    final long = await vault.seal(
      '${root}probe',
      Uint8List(_Envelope._window + 1),
    );
    final envelope = _Envelope(
      base,
      long.length - _Envelope._window - 1 - base,
    );
    final found = <String, Map<int, ({int count, int plain, int chunk})>>{};
    final strays = <String>[];
    for (final file in await files.list(root)) {
      switch (_parse(file.substring(min(root.length, file.length)))) {
        case (final id, final n, final count, final plain, final chunk):
          (found[id] ??= {})[n] = (count: count, plain: plain, chunk: chunk);
        case null:
          strays.add(file);
      }
    }
    final blobs = <String, _Blob>{};
    for (final MapEntry(key: id, value: chunks) in found.entries) {
      final first = chunks.values.first;
      final whole =
          chunks.length == first.count &&
          chunks.values.every((c) => c == first) &&
          List.generate(first.count, chunks.containsKey).every((b) => b);
      if (whole) {
        blobs[id] = _Blob(
          first.count,
          first.plain,
          first.chunk,
          envelope.blob(first.plain, first.chunk),
        );
      } else {
        await files.deleteAll('$root$id/');
      }
    }
    for (final stray in strays) {
      await files.delete(stray);
    }
    return OfflineStore._(
      vault,
      files,
      budget,
      chunkSize,
      envelope,
      blobs,
      root,
    );
  }

  // `<id>/<n>.<count>.<size>.<chunk>`, as (id, n, count, size, chunk).
  static (String, int, int, int, int)? _parse(String name) {
    final parts = name.split('/');
    if (parts.length != 2 || parts[0].length != 32) return null;
    final numbers = parts[1].split('.').map(int.tryParse).toList();
    if (numbers case [
      final int n,
      final int count,
      final int plain,
      final int chunk,
    ]) {
      return (parts[0], n, count, plain, chunk);
    }
    return null;
  }

  /// The most bytes it keeps on disk. Lowering it below [used] frees nothing:
  /// the caller drops blobs ([retain], [remove]) until it fits, and nothing is
  /// added meanwhile.
  int budget;

  /// The bytes the blobs take on disk, sealed.
  int get used => _used;

  /// The bytes of the blobs being written, taken from the budget already.
  int get reserved => _reserved;

  /// What is left of the budget for a new blob.
  int get available => max(0, budget - _used - _reserved);

  /// How many blobs it holds.
  int get length => _blobs.length;

  /// Whether the blob [key] is held, whole.
  bool has(String key) => _blobs.containsKey(_id(key));

  /// The size of the blob [key] as it was given, or null.
  int? sizeOf(String key) => _blobs[_id(key)]?.plain;

  /// The bytes [size] plain bytes take on disk.
  int sealedSize(int size) => _envelope.blob(size, chunkSize);

  static String _id(String key) => hex(objectId(key));

  String _chunk(String id, int n, _Blob b) =>
      '$_root$id/$n.${b.count}.${b.plain}.${b.chunk}';

  /// Keeps [bytes] as the blob [key].
  Future<void> putBytes(String key, Uint8List bytes) =>
      put(key, Stream.value(bytes), size: bytes.length);

  /// Keeps the [size] bytes of [body] as the blob [key], replacing any. Throws
  /// [BudgetExceeded], before it writes anything, when the blob's sealed bytes
  /// are more than what [available] says, and [SizeMismatch] when [body] ends
  /// or goes on at another length, leaving no trace of the blob.
  Future<void> put(
    String key,
    Stream<List<int>> body, {
    required int size,
  }) async {
    final id = _id(key);
    if (_blobs.containsKey(id)) await remove(key);
    final count = max(1, (size + chunkSize - 1) ~/ chunkSize);
    final need = sealedSize(size);
    if (need > available) throw BudgetExceeded(need, available);
    _reserved += need;
    final blob = _Blob(count, size, chunkSize, need);
    var written = 0;
    var held = need;
    var n = 0;
    final pending = BytesBuilder(copy: false);
    Future<void> flush(Uint8List piece) async {
      final envelope = await _vault.seal(_chunk(id, n, blob), piece);
      await _files.write(_chunk(id, n, blob), envelope);
      n++;
      written += envelope.length;
      _used += envelope.length;
      _reserved -= envelope.length;
      held -= envelope.length;
    }

    try {
      var seen = 0;
      await for (final piece in body) {
        seen += piece.length;
        if (seen > size) throw SizeMismatch(key, seen, size);
        pending.add(piece);
        while (pending.length >= chunkSize) {
          final all = pending.takeBytes();
          await flush(Uint8List.sublistView(all, 0, chunkSize));
          pending.add(Uint8List.sublistView(all, chunkSize));
        }
      }
      if (seen != size) throw SizeMismatch(key, seen, size);
      if (n < count) await flush(pending.takeBytes());
      _reserved -= held;
      _blobs[id] = _Blob(count, size, chunkSize, written);
    } on Object {
      _used -= written;
      _reserved -= held;
      await _files.deleteAll('$_root$id/');
      rethrow;
    }
  }

  /// The bytes of the blob [key] from [start] to [end] (the end by default),
  /// or null when it is not held, the vault is locked or a chunk is damaged,
  /// which drops the blob.
  Future<Uint8List?> read(String key, {int start = 0, int? end}) async {
    final id = _id(key);
    final blob = _blobs[id];
    if (blob == null) return null;
    final stop = min(end ?? blob.plain, blob.plain);
    if (start >= stop) return Uint8List(0);
    final out = BytesBuilder(copy: false);
    try {
      for (var n = start ~/ blob.chunk; n <= (stop - 1) ~/ blob.chunk; n++) {
        final name = _chunk(id, n, blob);
        final envelope = await _files.read(name);
        if (envelope == null) throw const _Lost();
        final plain = await _vault.unseal(name, envelope);
        final from = n * blob.chunk;
        out.add(
          Uint8List.sublistView(
            plain,
            max(0, start - from),
            min(plain.length, stop - from),
          ),
        );
      }
      // The vault locks with a StateError, and the blob stays.
      // ignore: avoid_catching_errors
    } on StateError {
      return null;
    } on KernelError {
      await _drop(id);
      return null;
    } on _Lost {
      await _drop(id);
      return null;
    }
    return out.takeBytes();
  }

  /// Drops the blob [key] and returns the bytes it freed.
  Future<int> remove(String key) => _drop(_id(key));

  Future<int> _drop(String id) async {
    final blob = _blobs.remove(id);
    if (blob == null) return 0;
    _used -= blob.sealed;
    await _files.deleteAll('$_root$id/');
    return blob.sealed;
  }

  /// Drops every blob but those of [keys] and returns the bytes it freed.
  Future<int> retain(Set<String> keys) async {
    final keep = {for (final k in keys) _id(k)};
    var freed = 0;
    for (final id in [..._blobs.keys]) {
      if (!keep.contains(id)) freed += await _drop(id);
    }
    return freed;
  }

  /// Drops everything.
  Future<void> clear() async {
    _blobs.clear();
    _used = 0;
    await _files.deleteAll(_root);
  }
}
