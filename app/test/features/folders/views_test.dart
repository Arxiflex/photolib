import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photolib/features/folders/sorting.dart';
import 'package:photolib/features/folders/views.dart';

import '../../support/pump_app.dart';

void main() {
  late MemoryStore store;

  ProviderContainer run() {
    final container = ProviderContainer(
      overrides: [folderViewsStoreProvider.overrideWithValue(store)],
    );
    addTearDown(container.dispose);
    return container;
  }

  setUp(() => store = MemoryStore());

  test('folders keep the order they are dragged into, pinned ones first, '
      'new ones after them in the order given', () {
    final notifier = run().read(folderViewsProvider.notifier);
    const keys = ['a', 'b', 'c', 'd'];
    expect(notifier.arrange('folders', keys), keys);
    // c dragged to the top.
    notifier.reorder('folders', keys, 2, 0);
    expect(notifier.arrange('folders', keys), ['c', 'a', 'b', 'd']);
    notifier.togglePin('d');
    expect(notifier.arrange('folders', keys), ['d', 'c', 'a', 'b']);
    // Dragged above a pinned folder, an unpinned one heads the rest.
    notifier.reorder('folders', ['d', 'c', 'a', 'b'], 3, 0);
    expect(notifier.arrange('folders', keys), ['d', 'b', 'c', 'a']);
    // A folder that a new file brings in, and one that went.
    expect(notifier.arrange('folders', ['0', 'a', 'b', 'c', 'd']), [
      'd',
      'b',
      'c',
      'a',
      '0',
    ]);
    expect(notifier.arrange('folders', ['a', 'b', 'd']), ['d', 'b', 'a']);
    expect(notifier.arrange('albums', ['b', 'a']), [
      'b',
      'a',
    ], reason: 'each list has its own order');
  });

  test('order, pins, views and recent targets survive a restart', () async {
    final notifier = run().read(folderViewsProvider.notifier);
    await notifier.loaded;
    notifier
      ..reorder('folders', ['a', 'b'], 1, 0)
      ..togglePin('a')
      ..setView('a', const ItemView(sort: ItemSort.name, list: true))
      ..addRecent('/x')
      ..addRecent('/y')
      ..addRecent('/x');
    final again = run().read(folderViewsProvider.notifier);
    await again.loaded;
    expect(again.arrange('folders', ['a', 'b']), ['a', 'b']);
    expect(again.state.pinned, {'a'});
    expect(again.viewOf('a').sort, ItemSort.name);
    expect(again.viewOf('a').list, isTrue);
    expect(again.viewOf('b').sort, ItemSort.taken, reason: 'the default');
    expect(again.state.recent, ['/x', '/y']);
  });

  test('recent targets keep the last ten', () {
    final notifier = run().read(folderViewsProvider.notifier);
    for (var i = 0; i < 12; i++) {
      notifier.addRecent('/$i');
    }
    expect(notifier.state.recent, [for (var i = 11; i > 1; i--) '/$i']);
  });
}
