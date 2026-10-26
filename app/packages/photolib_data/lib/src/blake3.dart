import 'dart:typed_data';

/// BLAKE3-256 of [bytes].
Uint8List blake3(List<int> bytes) => (Blake3()..add(bytes)).close();

const _iv = [
  0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, //
  0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19,
];
// Domain flags.
const _chunkStart = 1;
const _chunkEnd = 2;
const _parent = 4;
const _root = 8;

const _blockLength = 64;
const _blocksPerChunk = 16;

/// The message words each of the seven rounds reads, in order: each round's
/// are the last one's permuted.
final Uint8List _schedule = () {
  const permutation = [2, 6, 3, 10, 7, 0, 4, 13, 1, 11, 12, 5, 9, 14, 15, 8];
  final schedule = Uint8List(7 * 16);
  for (var i = 0; i < 16; i++) {
    schedule[i] = i;
  }
  for (var r = 1; r < 7; r++) {
    for (var i = 0; i < 16; i++) {
      schedule[r * 16 + i] = schedule[(r - 1) * 16 + permutation[i]];
    }
  }
  return schedule;
}();

/// BLAKE3 (the hash, unkeyed, 32 bytes), as files are hashed for backup and
/// deduplication (docs/05-sync-and-offline.md §6): fed in pieces of any size,
/// in constant memory but for one chaining value per level of the chunk tree.
class Blake3 {
  final _stack = <Uint32List>[];
  final _block = Uint8List(_blockLength);
  late final _blockData = ByteData.sublistView(_block);
  final _words = Uint32List(16);
  final _out = Uint32List(16);
  final _cv = Uint32List.fromList(_iv);
  var _chunk = 0;
  var _blocks = 0;
  var _filled = 0;

  /// Feeds [bytes] on.
  void add(List<int> bytes) {
    for (var at = 0; at < bytes.length;) {
      if (_filled == _blockLength) {
        if (_blocks == _blocksPerChunk - 1) {
          _endChunk();
        } else {
          _compress(_cv, _load(), _chunk, _blockLength, _startFlag, _cv);
          _blocks++;
          _filled = 0;
        }
      }
      final take = _blockLength - _filled < bytes.length - at
          ? _blockLength - _filled
          : bytes.length - at;
      _block.setRange(_filled, _filled + take, bytes, at);
      _filled += take;
      at += take;
    }
  }

  /// The hash of what was fed.
  Uint8List close() {
    final cv = Uint32List.fromList(_cv);
    final words = Uint32List.fromList(_load());
    var (counter, length, flags) = (_chunk, _filled, _startFlag | _chunkEnd);
    for (final left in _stack.reversed) {
      _compress(cv, words, counter, length, flags, _out);
      words
        ..setRange(8, 16, _out)
        ..setRange(0, 8, left);
      cv.setAll(0, _iv);
      (counter, length, flags) = (0, _blockLength, _parent);
    }
    _compress(cv, words, counter, length, flags | _root, _out);
    final hash = ByteData(32);
    for (var i = 0; i < 8; i++) {
      hash.setUint32(i * 4, _out[i], Endian.little);
    }
    return hash.buffer.asUint8List();
  }

  int get _startFlag => _blocks == 0 ? _chunkStart : 0;

  Uint32List _load() {
    _block.fillRange(_filled, _blockLength, 0);
    for (var i = 0; i < 16; i++) {
      _words[i] = _blockData.getUint32(i * 4, Endian.little);
    }
    return _words;
  }

  /// Ends the full chunk, merging the chaining values of complete subtrees.
  void _endChunk() {
    final flags = _startFlag | _chunkEnd;
    final cv = Uint32List(8);
    _compress(_cv, _load(), _chunk, _blockLength, flags, cv);
    _chunk++;
    for (var n = _chunk; n & 1 == 0; n >>= 1) {
      _words
        ..setRange(0, 8, _stack.removeLast())
        ..setRange(8, 16, cv);
      _cv.setAll(0, _iv);
      _compress(_cv, _words, 0, _blockLength, _parent, cv);
    }
    _stack.add(cv);
    _cv.setAll(0, _iv);
    _blocks = _filled = 0;
  }
}

/// The working state of [_compress].
final _v = Uint32List(16);

/// The compression function into [out]: its 8 or 16 words, the first 8 the
/// next chaining value.
void _compress(
  Uint32List cv,
  Uint32List m,
  int counter,
  int length,
  int flags,
  Uint32List out,
) {
  final v = _v
    ..setRange(0, 8, cv)
    ..setRange(8, 12, _iv)
    ..[12] = counter
    ..[13] = counter >> 32
    ..[14] = length
    ..[15] = flags;
  for (var r = 0; r < 7 * 16; r += 16) {
    _g(v, 0, 4, 8, 12, m[_schedule[r]], m[_schedule[r + 1]]);
    _g(v, 1, 5, 9, 13, m[_schedule[r + 2]], m[_schedule[r + 3]]);
    _g(v, 2, 6, 10, 14, m[_schedule[r + 4]], m[_schedule[r + 5]]);
    _g(v, 3, 7, 11, 15, m[_schedule[r + 6]], m[_schedule[r + 7]]);
    _g(v, 0, 5, 10, 15, m[_schedule[r + 8]], m[_schedule[r + 9]]);
    _g(v, 1, 6, 11, 12, m[_schedule[r + 10]], m[_schedule[r + 11]]);
    _g(v, 2, 7, 8, 13, m[_schedule[r + 12]], m[_schedule[r + 13]]);
    _g(v, 3, 4, 9, 14, m[_schedule[r + 14]], m[_schedule[r + 15]]);
  }
  if (out.length == 16) {
    for (var i = 0; i < 8; i++) {
      out[i + 8] = v[i + 8] ^ cv[i];
    }
  }
  for (var i = 0; i < 8; i++) {
    out[i] = v[i] ^ v[i + 8];
  }
}

/// BLAKE3's quarter round G on the words [a], [b], [c] and [d] of [v].
@pragma('vm:prefer-inline')
void _g(Uint32List v, int a, int b, int c, int d, int x, int y) {
  v[a] = v[a] + v[b] + x;
  v[d] = _rotate(v[d] ^ v[a], 16);
  v[c] = v[c] + v[d];
  v[b] = _rotate(v[b] ^ v[c], 12);
  v[a] = v[a] + v[b] + y;
  v[d] = _rotate(v[d] ^ v[a], 8);
  v[c] = v[c] + v[d];
  v[b] = _rotate(v[b] ^ v[c], 7);
}

/// [x] rotated right by [n] bits, of 32; a Uint32List keeps the low ones.
@pragma('vm:prefer-inline')
int _rotate(int x, int n) => x >> n | x << (32 - n);
