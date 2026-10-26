// tool/single_writer_lint.dart: the store's own files import each other
// by relative paths.
// ignore_for_file: always_use_package_imports

import 'package:drift/drift.dart';

import 'offline_store.dart';
import 'replica.dart';
import 'sync.dart' show uuidBytes;

/// A file of the server that the offline store holds.
class OfflineFile {
  OfflineFile._(this._store, this.key, this.hash);

  final OfflineStore _store;

  /// Its key in the store.
  final String key;

  /// The hash of its content in hex, which its ETag is.
  final String hash;

  /// Its size in bytes.
  int get size => _store.sizeOf(key) ?? 0;

  /// Its bytes from [start] to [end]: exactly what the server serves, so a
  /// private library's stay ciphertext until the viewer opens them in memory.
  Future<Uint8List?> read({int start = 0, int? end}) =>
      _store.read(key, start: start, end: end);
}

/// The server's media as the offline store has them: `media/<asset>/<role>`
/// with the same answers as the server's, so that the thumbnail pipeline and
/// the players need no other path to show a pinned item with no network.
class OfflineMedia {
  /// Reads [store]; the replica [db] knows which file is the current one.
  OfflineMedia(this.db, this.store);

  /// The replica that says which file of an asset is the current one.
  final Replica db;

  /// Where the files are held.
  final OfflineStore store;

  /// The key of a file by its asset, role and the hash of its content, all in
  /// hex.
  static String keyOf(String asset, String role, String hash) =>
      '$asset.$role.${hash.length > 16 ? hash.substring(0, 16) : hash}';

  // The asset and role of `media/<asset>/<role>`, or null.
  static (Uint8List, String)? _parse(Uri uri) {
    final segments = uri.pathSegments;
    if (segments.length != 3 || segments[0] != 'media') return null;
    final Uint8List asset;
    try {
      asset = uuidBytes(segments[1]);
    } on Object {
      return null;
    }
    return asset.length == 16 ? (asset, segments[2]) : null;
  }

  /// What the replica says of the file `media/<asset>/<role>`: the hash of
  /// its content in hex, its size and type; null when the server has none.
  Future<({String hash, int size, String mime})?> describe(String path) async {
    final (asset, role) = _parse(Uri.parse(path)) ?? (null, null);
    if (asset == null || role == null) return null;
    final row = await db
        .customSelect(
          'SELECT content_hash, size, mime FROM asset_file WHERE asset_id = ?1 '
          "AND role = ?2 AND state = 'present' AND content_hash IS NOT NULL "
          'LIMIT 1',
          variables: [Variable(asset), Variable(role)],
          readsFrom: {db.assetFile},
        )
        .getSingleOrNull();
    if (row == null) return null;
    return (
      hash: _hex(row.read<Uint8List>('content_hash')),
      size: row.read<int>('size'),
      mime: row.read<String>('mime'),
    );
  }

  /// The file `media/<asset>/<role>`, with `?h=<hash>` for one version, else
  /// the replica's current one; null when the store does not hold it.
  Future<OfflineFile?> open(String path) async {
    final uri = Uri.parse(path);
    final (asset, role) = _parse(uri) ?? (null, null);
    if (asset == null || role == null) return null;
    final hash = uri.queryParameters['h'] ?? (await describe(path))?.hash;
    if (hash == null) return null;
    final key = keyOf(_hex(asset), role, hash);
    return store.has(key) ? OfflineFile._(store, key, hash) : null;
  }

  /// What the server would answer to `GET <path>` with [headers], from the
  /// store: 200 with the bytes and the ETag, 304 for a matching
  /// `if-none-match`; null when the store does not hold the file.
  Future<({int status, String? etag, Uint8List bytes})?> fetch(
    String path,
    Map<String, String> headers,
  ) async {
    final file = await open(path);
    if (file == null) return null;
    final etag = '"${file.hash}"';
    if (headers['if-none-match'] == etag) {
      return (status: 304, etag: etag, bytes: Uint8List(0));
    }
    final bytes = await file.read();
    return bytes == null ? null : (status: 200, etag: etag, bytes: bytes);
  }
}

String _hex(List<int> bytes) =>
    [for (final b in bytes) b.toRadixString(16).padLeft(2, '0')].join();
