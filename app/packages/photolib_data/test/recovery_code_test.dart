import 'dart:typed_data';

import 'package:photolib_data/photolib_data.dart';
import 'package:test/test.dart';

void main() {
  // BIP-39's own vectors of 256-bit entropy.
  final vectors = {
    '00' * 32: '${'abandon ' * 23}art',
    '7f' * 32:
        'legal winner thank year wave sausage worth useful legal winner thank '
        'year wave sausage worth useful legal winner thank year wave sausage '
        'worth title',
    '80' * 32:
        'letter advice cage absurd amount doctor acoustic avoid letter advice '
        'cage absurd amount doctor acoustic avoid letter advice cage absurd '
        'amount doctor acoustic bless',
    'ff' * 32: '${'zoo ' * 23}vote',
    '68a79eaca2324873eacc50cb9c6eca8cc68ea5d936f98787c60c7ebc74e6ce7c':
        'hamster diagram private dutch cause delay private meat slide toddler '
        'razor book happy fancy gospel tennis maple dilemma loan word shrug '
        'inflict delay length',
  };
  Uint8List bytes(String hex) => Uint8List.fromList([
    for (var i = 0; i < hex.length; i += 2)
      int.parse(hex.substring(i, i + 2), radix: 16),
  ]);

  test('a recovery code is its entropy in 24 words of BIP-39, and back', () {
    for (final MapEntry(key: hex, value: words) in vectors.entries) {
      expect(recoveryWords(bytes(hex)), words);
      expect(recoveryEntropy(words), bytes(hex));
    }
  });

  test('any case and spacing is the code; anything else is none', () {
    final words = vectors['7f' * 32]!;
    expect(recoveryEntropy(' ${words.toUpperCase()}\n'), bytes('7f' * 32));
    expect(recoveryEntropy(words.replaceFirst('title', 'zoo')), isNull);
    expect(recoveryEntropy(words.replaceFirst('legal', 'legally')), isNull);
    expect(recoveryEntropy(words.substring(6)), isNull);
    expect(recoveryEntropy(''), isNull);
  });
}
