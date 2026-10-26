// What both vector runners and the benchmark share, and run as kernel/tests/vectors.rs does: a case runs on a fresh
// keyring, its setup calls first; a stream pushes pieces that may come from the file's blobs, and may pin the SHA-256
// of its responses.
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

Uint8List bytes(Object? base64) => base64Decode(base64 as String);

List<Map<String, dynamic>> setup(Map<String, dynamic> c) =>
    [...?c['setup'] as List?].cast<Map<String, dynamic>>();

/// A piece pushed into a stream: base64, `{"pattern": n}` (byte i = i mod 251) or ranges of one of the file's blobs.
Uint8List piece(Object? piece, Map<String, dynamic> file) {
  if (piece is! Map) return bytes(piece);
  if (piece['pattern'] case final int n) {
    return Uint8List.fromList([for (var i = 0; i < n; i++) i % 251]);
  }
  final blob = bytes(file['blobs'][piece['blob']]);
  return Uint8List.fromList([
    for (final [int from, int to] in (piece['ranges'] as List).cast<List>())
      ...blob.sublist(from, to),
  ]);
}

/// A keyring of either binding.
typedef Keys = ({
  Uint8List Function(int method, Uint8List request) call,
  Pushes Function(int method, Uint8List request) open,
  void Function() close,
});

/// A stream of either binding.
typedef Pushes = ({
  Uint8List Function(Uint8List input) push,
  Uint8List Function() finish,
});

/// The responses of a case: of its setup calls, then of its call, or of each piece its stream pushes and of finishing
/// (or their SHA-256).
List<Uint8List> run(
  Keys keyring,
  Map<String, dynamic> c,
  Map<String, dynamic> file,
) {
  try {
    final responses = [
      for (final step in setup(c))
        keyring.call(step['method'] as int, bytes(step['request'])),
    ];
    final (method, request) = (c['method'] as int, bytes(c['request']));
    final pieces = c['stream'] as List?;
    if (pieces == null) return [...responses, keyring.call(method, request)];
    final stream = keyring.open(method, request);
    final steps = [
      for (final p in pieces) stream.push(piece(p, file)),
      stream.finish(),
    ];
    if (!c.containsKey('responses_sha256')) return [...responses, ...steps];
    final hash = sha256.convert(steps.expand((r) => r).toList()).bytes;
    return [...responses, Uint8List.fromList(hash)];
  } finally {
    keyring.close();
  }
}

List<Uint8List> expected(Map<String, dynamic> c) => [
  for (final step in setup(c)) bytes(step['response']),
  if (c['responses_sha256'] case final String hash)
    Uint8List.fromList([
      for (var i = 0; i < hash.length; i += 2)
        int.parse(hash.substring(i, i + 2), radix: 16),
    ])
  else if (c['responses'] case final List responses)
    ...responses.map(bytes)
  else
    bytes(c['response']),
];
