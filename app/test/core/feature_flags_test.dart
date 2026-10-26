import 'package:flutter_test/flutter_test.dart';
import 'package:photolib/core/feature_flags.dart';

void main() {
  test('diagnostics is off until it is named', () {
    expect(FeatureFlags.parse('').isOn(Flag.diagnostics), isFalse);
  });

  test('a name turns a flag on and a minus turns it off', () {
    expect(FeatureFlags.parse('diagnostics').isOn(Flag.diagnostics), isTrue);
    expect(FeatureFlags.parse('-diagnostics').isOn(Flag.diagnostics), isFalse);
  });

  test('the last mention wins', () {
    expect(
      FeatureFlags.parse('-diagnostics,diagnostics').isOn(Flag.diagnostics),
      isTrue,
    );
  });

  test('blanks, spaces and unknown names are ignored', () {
    final flags = FeatureFlags.parse(' diagnostics , ,nope,-also-nope');
    expect(flags.isOn(Flag.diagnostics), isTrue);
  });
}
