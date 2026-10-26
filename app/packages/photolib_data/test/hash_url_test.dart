// What an upload hashes in a browser (`dart test -p chrome -p firefox
// -c dart2js -c dart2wasm test/hash_url_test.dart`, the `web` part of
// tools/check.sh): the BLAKE3 of a file's `blob:` URL, read in the pieces the browser gives it.
@TestOn('browser')
library;

import 'dart:js_interop';
import 'dart:typed_data';

import 'package:photolib_data/src/hash_url.dart';
import 'package:photolib_workers/blake3.dart';
import 'package:test/test.dart';
import 'package:web/web.dart' as web;

String urlOf(Uint8List bytes) =>
    web.URL.createObjectURL(web.Blob([bytes.toJS].toJS));

Uint8List bytesOf(int length) =>
    Uint8List.fromList([for (var i = 0; i < length; i++) (i * 31 + 7) & 0xff]);

void main() {
  test('the hash of nothing is the BLAKE3 of the empty input', () async {
    expect(
      await hashUrl(urlOf(Uint8List(0))),
      'af1349b9f5f9a1a6a0404dea36dcc9499bcb25c9adc112b7cc9a93cae41f3262',
    );
  });

  test('a file hashes as its bytes do at once, over every chunk boundary of '
      'the tree, and the progress only grows to 1', () async {
    for (final length in [
      1,
      63,
      64,
      65,
      1023,
      1024,
      1025,
      2048,
      70000,
      5000000,
    ]) {
      final bytes = bytesOf(length);
      final seen = <double>[];
      final hash = await hashUrl(urlOf(bytes), progress: seen.add);
      expect(hash, (Blake3()..add(bytes)).hex, reason: '$length bytes');
      expect(seen.last, 1, reason: '$length bytes');
      expect(
        [for (var i = 1; i < seen.length; i++) seen[i] >= seen[i - 1]],
        everyElement(isTrue),
        reason: '$length bytes',
      );
    }
  });

  test('a URL of nothing fails rather than hashing nothing', () async {
    final url = urlOf(bytesOf(10));
    web.URL.revokeObjectURL(url);
    await expectLater(hashUrl(url), throwsA(anything));
  });
}
