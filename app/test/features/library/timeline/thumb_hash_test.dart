import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:photolib/features/library/timeline/thumb_hash.dart';
import 'package:photolib_kernel/photolib_kernel.dart';

void main() {
  final kernel = Kernel();
  final vectors = jsonDecode(
    File('../testdata/thumbhash.json').readAsStringSync(),
  );
  final cases = (vectors['cases'] as List).cast<Map<String, dynamic>>();

  test('the vectors are there', () => expect(cases, hasLength(7)));

  for (final c in cases) {
    final hash = base64.decode(c['hash'] as String);
    test('${c['name']}: the kernel encodes as the reference does', () {
      final rgba = base64.decode(c['rgba'] as String);
      expect(
        encodeThumbHash(kernel.call, c['w'] as int, c['h'] as int, rgba),
        hash,
      );
    });

    test('${c['name']}: decodes as the reference does', () {
      final thumbHash = ThumbHash.tryParse(hash)!;
      expect(thumbHash.aspect, c['aspect']);
      // The reference renders 32 px on the long side, sampling pixel centres.
      final aspect = thumbHash.aspect;
      final w = (aspect > 1 ? 32 : 32 * aspect).round();
      final h = (aspect > 1 ? 32 / aspect : 32).round();
      final decoded = c['decoded'] as Map<String, dynamic>;
      expect((w, h), (decoded['w'], decoded['h']));
      final want = base64.decode(decoded['rgba'] as String);
      // Within one of the reference: libm's cosines may differ in the last bit.
      var worst = 0;
      for (var i = 0; i < want.length; i += 4) {
        final (r, g, b, a) = thumbHash.at(
          (i ~/ 4 % w + 0.5) / w,
          (i ~/ 4 ~/ w + 0.5) / h,
        );
        for (final (j, v) in [r, g, b, a].indexed) {
          worst = max(worst, ((255 * v).toInt() - want[i + j]).abs());
        }
      }
      expect(worst, lessThanOrEqualTo(1));
    });
  }

  test('a truncated or random hash is refused, never thrown', () {
    final random = Random(56);
    final valid = base64.decode(cases.first['hash'] as String);
    for (var n = 0; n < valid.length; n++) {
      expect(ThumbHash.tryParse(valid.sublist(0, n)), isNull, reason: '$n');
    }
    for (var i = 0; i < 2000; i++) {
      final bytes = Uint8List.fromList([
        for (var n = random.nextInt(40); n > 0; n--) random.nextInt(256),
      ]);
      final (r, g, b, a) =
          ThumbHash.tryParse(bytes)?.at(random.nextDouble(), 0.5) ??
          (0.0, 0.0, 0.0, 0.0);
      for (final v in [r, g, b, a]) {
        expect(v, inInclusiveRange(0, 1));
      }
    }
  });
}
