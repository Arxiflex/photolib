import 'package:flutter_test/flutter_test.dart';
import 'package:photolib/features/library/timeline/pages.dart';

void main() {
  test(
    'fetches the page of a position once, then tells its listeners',
    () async {
      final fetched = <(int, int)>[];
      final pages = TimelinePages((first, count) async {
        fetched.add((first, count));
        return [for (var i = first; i < first + count && i < 300; i++) 'a$i'];
      }, size: 128);
      var told = 0;
      pages.addListener(() => told++);
      expect(pages[130], isNull);
      expect(pages[200], isNull);
      await pumpEventQueue();
      expect(fetched, [(128, 128)]);
      expect(told, 1);
      expect(pages[130], 'a130');
      expect(pages[299], isNull);
      await pumpEventQueue();
      expect(pages[299], 'a299');
      expect(pages[300], isNull, reason: 'past the end');
    },
  );

  test('keeps the most recently used pages', () async {
    final fetched = <int>[];
    final pages = TimelinePages(
      (first, count) async {
        fetched.add(first);
        return List.filled(count, first);
      },
      size: 10,
      keep: 2,
    );
    for (final p in [0, 10, 0, 20, 0, 10]) {
      pages[p];
      await pumpEventQueue();
    }
    expect(fetched, [0, 10, 20, 10], reason: '10 was the oldest at 20');
  });
}
