import 'dart:math';

import 'package:photolib_data/photolib_data.dart';
import 'package:test/test.dart';

void main() {
  test(
    'a key fits between any two, at either end and after the last digit',
    () {
      expect(keyBetween(null, null), 'V');
      expect(keyBetween('V', null), 'k');
      expect(keyBetween(null, 'V'), 'F');
      expect(keyBetween('a', 'b'), 'aV');
      expect(keyBetween('az', null), 'n');
      expect(keyBetween('z', null), 'zV');
      expect(keyBetween(null, '1'), '0V');
      expect(keyBetween('a1', 'a2'), 'a1V');
      expect(() => keyBetween('b', 'a'), throwsArgumentError);
      expect(() => keyBetween('a', 'a'), throwsArgumentError);
    },
  );

  test('keys made at random positions stay strictly ordered, bytewise, with '
      'room before each', () {
    final random = Random(7);
    final keys = <String>[];
    for (var n = 0; n < 2000; n++) {
      final at = random.nextInt(keys.length + 1);
      final key = keyBetween(
        at == 0 ? null : keys[at - 1],
        at == keys.length ? null : keys[at],
      );
      expect(key, matches(RegExp(r'^[0-9A-Za-z]*[1-9A-Za-z]$')));
      keys.insert(at, key);
    }
    for (var i = 1; i < keys.length; i++) {
      expect(keys[i - 1].compareTo(keys[i]), lessThan(0), reason: '$i');
    }
    expect(keys.map((k) => k.length).reduce(max), lessThan(64));
  });
}
