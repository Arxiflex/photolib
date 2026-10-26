import 'package:flutter_test/flutter_test.dart';
import 'package:photolib/features/library/timeline/selection.dart';

void main() {
  test('ranges merge when they touch or overlap, in order', () {
    final s = Selection.none.add(10, 20).add(0, 5).add(20, 25).add(3, 8);
    expect(s.ranges, [(0, 8), (10, 25)]);
    expect(s.count, 23);
    expect(
      [
        for (final a in [0, 7, 8, 9, 10, 24, 25]) s.contains(a),
      ],
      [true, true, false, false, true, true, false],
    );
  });

  test('removing splits a range; toggling flips one position', () {
    final s = Selection.none.add(0, 10).remove(3, 5).remove(9, 30);
    expect(s.ranges, [(0, 3), (5, 9)]);
    expect(s.toggle(4).ranges, [(0, 3), (4, 9)]);
    expect(s.toggle(0).ranges, [(1, 3), (5, 9)]);
    expect(s.toggle(0).toggle(0), s);
    expect(Selection.none.add(2, 2).isEmpty, isTrue);
  });

  test('whether a whole span is selected, as a header shows its day', () {
    final s = Selection.none.add(0, 3).add(4, 8);
    expect(s.containsAll(0, 3), isTrue);
    expect(s.containsAll(4, 8), isTrue);
    expect(s.containsAll(2, 5), isFalse);
    expect(s.containsAll(7, 9), isFalse);
  });

  test('the nth selected position, for the review of the selection, and '
      'each in order', () {
    final s = Selection.none.add(3, 5).add(100, 103);
    expect([for (var i = 0; i < s.count; i++) s[i]], [3, 4, 100, 101, 102]);
    expect(s.positions, [3, 4, 100, 101, 102]);
  });

  test('a million positions, minus a few, stay a few ranges', () {
    var s = Selection.none.add(0, 1000000);
    for (final a in [999, 5000, 123456]) {
      s = s.toggle(a);
    }
    expect(s.ranges, hasLength(4));
    expect(s.count, 1000000 - 3);
    expect(s[999], 1000);
  });
}
