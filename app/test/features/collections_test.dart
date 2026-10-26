import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photolib/features/collections/collections.dart';

import '../support/pump_app.dart';

void main() {
  const albums = CollectionKind.albums;
  const folders = CollectionKind.folders;
  const favourites = CollectionKind.favourites;
  const people = CollectionKind.people;
  const places = CollectionKind.places;
  const tags = CollectionKind.tags;

  late MemoryStore store;
  late ProviderContainer container;
  late CollectionsNotifier notifier;

  List<CollectionKind> visible() =>
      container.read(collectionsProvider).visible.map((e) => e.kind).toList();
  List<CollectionKind> hidden() =>
      container.read(collectionsProvider).hidden.map((e) => e.kind).toList();

  ProviderContainer run() {
    final container = ProviderContainer(
      overrides: [collectionsStoreProvider.overrideWithValue(store)],
    );
    addTearDown(container.dispose);
    return container;
  }

  setUp(() {
    store = MemoryStore();
    container = run();
    notifier = container.read(collectionsProvider.notifier);
  });

  test('starts with every collection visible and none pinned', () {
    expect(visible(), [albums, folders, favourites, people, places, tags]);
    expect(hidden(), isEmpty);
    expect(
      container.read(collectionsProvider).visible.any((e) => e.pinned),
      false,
    );
  });

  group('pin', () {
    test('lifts a collection above the unpinned ones', () {
      notifier.togglePin(tags);
      expect(visible(), [tags, albums, folders, favourites, people, places]);
    });

    test('keeps pinned collections in their own order', () {
      notifier
        ..togglePin(places)
        ..togglePin(albums);
      expect(visible(), [albums, places, folders, favourites, people, tags]);
    });

    test('unpin puts the collection back among the rest', () {
      notifier
        ..togglePin(tags)
        ..togglePin(tags);
      expect(visible(), [albums, folders, favourites, people, places, tags]);
    });
  });

  group('hide', () {
    test('moves a collection out of the visible list, not out of the app', () {
      notifier.toggleHidden(people);
      expect(visible(), [albums, folders, favourites, places, tags]);
      expect(hidden(), [people]);
    });

    test('show brings it back where it was', () {
      notifier
        ..toggleHidden(people)
        ..toggleHidden(people);
      expect(visible(), [albums, folders, favourites, people, places, tags]);
      expect(hidden(), isEmpty);
    });

    test('a hidden collection can be pinned and shown later', () {
      notifier
        ..toggleHidden(tags)
        ..togglePin(tags)
        ..toggleHidden(tags);
      expect(visible(), [tags, albums, folders, favourites, people, places]);
    });
  });

  group('move', () {
    test('swaps a collection with its neighbour', () {
      notifier.move(albums, 1);
      expect(visible(), [folders, albums, favourites, people, places, tags]);
      notifier.move(tags, -1);
      expect(visible(), [folders, albums, favourites, people, tags, places]);
    });

    test('does nothing at either end', () {
      notifier
        ..move(albums, -1)
        ..move(tags, 1);
      expect(visible(), [albums, folders, favourites, people, places, tags]);
    });

    test('stays within the pinned or the unpinned group', () {
      notifier.togglePin(people);
      notifier.move(albums, -1);
      expect(visible(), [people, albums, folders, favourites, places, tags]);
      notifier.move(people, 1);
      expect(visible(), [people, albums, folders, favourites, places, tags]);
    });

    test('steps over hidden collections', () {
      notifier.toggleHidden(folders);
      notifier.move(albums, 1);
      expect(visible(), [favourites, albums, people, places, tags]);
      notifier.toggleHidden(folders);
      expect(visible().toSet(), CollectionKind.values.toSet());
    });
  });

  group('kept', () {
    test('in their store, and the next run reads them back', () async {
      notifier
        ..togglePin(tags)
        ..toggleHidden(people)
        ..move(albums, 1);
      container = run();
      await container.read(collectionsProvider.notifier).loaded;
      expect(visible(), [tags, folders, albums, favourites, places]);
      expect(hidden(), [people]);
    });

    test('a kind added since shows last, one no longer known goes', () async {
      store.value =
          '[{"kind":"tags","pinned":true},{"kind":"memories"},'
          '{"kind":"albums","pinned":false,"hidden":true}]';
      container = run();
      await container.read(collectionsProvider.notifier).loaded;
      expect(visible(), [tags, folders, favourites, people, places]);
      expect(hidden(), [albums]);
    });
  });
}
