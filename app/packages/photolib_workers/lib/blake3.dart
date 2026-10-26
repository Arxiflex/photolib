/// BLAKE3 (the reference implementation's algorithm), the hash photolibd
/// checks uploads with (ADR-0061), in plain Dart for workers on every target.
library;

import 'dart:typed_data';

const _iv = [
  0x6A09E667,
  0xBB67AE85,
  0x3C6EF372,
  0xA54FF53A,
  0x510E527F,
  0x9B05688C,
  0x1F83D9AB,
  0x5BE0CD19,
];
const _permutation = [2, 6, 3, 10, 7, 0, 4, 13, 1, 11, 12, 5, 9, 14, 15, 8];
const _chunkStart = 1;
const _chunkEnd = 2;
const _parent = 4;
const _root = 8;
const _blockLength = 64;
const _chunkLength = 1024;

/// A streaming BLAKE3 hash with a 32-byte output.
class Blake3 {
  final _stack = <Uint32List>[];
  var _chunk = _Chunk(Uint32List.fromList(_iv), 0);

  /// Hashes [bytes] after what came before.
  void add(List<int> bytes) {
    var at = 0;
    while (at < bytes.length) {
      if (_chunk.length == _chunkLength) {
        final total = _chunk.counter + 1;
        _push(_chunk.output().chainingValue(), total);
        _chunk = _Chunk(Uint32List.fromList(_iv), total);
      }
      at += _chunk.add(bytes, at);
    }
  }

  /// The hash of everything added, in lowercase hex.
  String get hex {
    var output = _chunk.output();
    for (var i = _stack.length - 1; i >= 0; i--) {
      output = _parentOutput(_stack[i], output.chainingValue());
    }
    final words = output.compressed(_root);
    return [
      for (var i = 0; i < 8; i++)
        for (var b = 0; b < 4; b++)
          (words[i] >> (8 * b) & 0xFF).toRadixString(16).padLeft(2, '0'),
    ].join();
  }

  /// Merges the subtrees a chunk completes: as many as trailing zero bits of
  /// the [total] of chunks so far.
  void _push(Uint32List cv, int total) {
    var merged = cv;
    for (var t = total; t & 1 == 0; t >>= 1) {
      merged = _parentOutput(_stack.removeLast(), merged).chainingValue();
    }
    _stack.add(merged);
  }
}

_Output _parentOutput(Uint32List left, Uint32List right) => _Output(
  Uint32List.fromList(_iv),
  Uint32List(16)
    ..setAll(0, left)
    ..setAll(8, right),
  0,
  _blockLength,
  _parent,
);

class _Chunk {
  _Chunk(this._cv, this.counter);

  final Uint32List _cv;
  final int counter;
  final _block = Uint8List(_blockLength);
  late final _words = Uint32List.view(_block.buffer); // little-endian hosts
  final _state = Uint32List(16);
  var _blockFill = 0;
  var _blocks = 0;

  int get length => _blocks * _blockLength + _blockFill;

  int get _start => _blocks == 0 ? _chunkStart : 0;

  /// Takes what fits of [bytes] from [at] into this chunk; returns how much.
  int add(List<int> bytes, int at) {
    var taken = 0;
    while (at + taken < bytes.length && length < _chunkLength) {
      if (_blockFill == _blockLength) {
        _compress(_cv, _words, counter, _blockLength, _start, _state);
        _cv.setRange(0, 8, _state);
        _blocks++;
        _blockFill = 0;
        _block.fillRange(0, _blockLength, 0);
      }
      final n = (_blockLength - _blockFill).clamp(0, bytes.length - at - taken);
      _block.setRange(_blockFill, _blockFill + n, bytes, at + taken);
      _blockFill += n;
      taken += n;
    }
    return taken;
  }

  _Output output() => _Output(
    _cv,
    Uint32List.fromList(_words),
    counter,
    _blockFill,
    _start | _chunkEnd,
  );
}

class _Output {
  _Output(this._cv, this._block, this._counter, this._length, this._flags);

  final Uint32List _cv;
  final Uint32List _block;
  final int _counter;
  final int _length;
  final int _flags;

  Uint32List chainingValue() => Uint32List.sublistView(compressed(0), 0, 8);

  Uint32List compressed(int flags) {
    final out = Uint32List(16);
    _compress(_cv, _block, _counter, _length, _flags | flags, out);
    return out;
  }
}

/// The message word each step of each of the seven rounds reads.
final Uint8List _schedule = () {
  final schedule = Uint8List(7 * 16);
  var order = List.generate(16, (i) => i);
  for (var round = 0; round < 7; round++) {
    schedule.setAll(round * 16, order);
    order = [for (final i in _permutation) order[i]];
  }
  return schedule;
}();

int _rotr(int x, int n) => (x >> n | x << (32 - n)) & 0xFFFFFFFF;

void _g(Uint32List s, int a, int b, int c, int d, int x, int y) {
  s[a] = s[a] + s[b] + x;
  s[d] = _rotr(s[d] ^ s[a], 16);
  s[c] = s[c] + s[d];
  s[b] = _rotr(s[b] ^ s[c], 12);
  s[a] = s[a] + s[b] + y;
  s[d] = _rotr(s[d] ^ s[a], 8);
  s[c] = s[c] + s[d];
  s[b] = _rotr(s[b] ^ s[c], 7);
}

/// Compresses [m] into [s].
void _compress(
  Uint32List cv,
  Uint32List m,
  int counter,
  int length,
  int flags,
  Uint32List s,
) {
  s
    ..setAll(0, cv)
    ..setRange(8, 12, _iv);
  s[12] = counter;
  s[13] = counter ~/ 0x100000000;
  s[14] = length;
  s[15] = flags;
  for (var r = 0; r < 7 * 16; r += 16) {
    final k = _schedule;
    _g(s, 0, 4, 8, 12, m[k[r]], m[k[r + 1]]);
    _g(s, 1, 5, 9, 13, m[k[r + 2]], m[k[r + 3]]);
    _g(s, 2, 6, 10, 14, m[k[r + 4]], m[k[r + 5]]);
    _g(s, 3, 7, 11, 15, m[k[r + 6]], m[k[r + 7]]);
    _g(s, 0, 5, 10, 15, m[k[r + 8]], m[k[r + 9]]);
    _g(s, 1, 6, 11, 12, m[k[r + 10]], m[k[r + 11]]);
    _g(s, 2, 7, 8, 13, m[k[r + 12]], m[k[r + 13]]);
    _g(s, 3, 4, 9, 14, m[k[r + 14]], m[k[r + 15]]);
  }
  for (var i = 0; i < 8; i++) {
    s[i] ^= s[i + 8];
    s[i + 8] ^= cv[i];
  }
}
