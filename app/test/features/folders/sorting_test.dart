import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:photolib/features/folders/sorting.dart';
import 'package:photolib_data/photolib_data.dart';

LocalAssetData _item(
  int n,
  String name, {
  int size = 0,
  int mtime = 0,
  int? taken,
}) => LocalAssetData(
  id: Uint8List(16)..[15] = n,
  source: 'folder',
  volume: '/p',
  sourceId: '$n',
  size: size,
  mtime: mtime,
  path: 'a/$name',
  state: 'present',
  favorite: 0,
  trashed: 0,
  edited: 0,
  takenUtc: taken,
  folder: 0,
  hidden: 0,
  archived: 0,
  tile: 0,
);

void main() {
  test('names compare with their numbers as numbers, in any case', () {
    final names = ['img10.jpg', 'IMG2.jpg', '66', '8', 'img2.jpg', 'a', 'B'];
    expect(names..sort(naturalCompare), [
      '8',
      '66',
      'a',
      'B',
      'IMG2.jpg',
      'img2.jpg',
      'img10.jpg',
    ]);
    expect(naturalCompare('x007', 'x7'), isNot(0), reason: 'never equal');
    expect(
      naturalCompare('a${'9' * 30}', 'a1${'0' * 30}'),
      isNegative,
      reason: 'numbers past 64 bits too',
    );
  });

  final items = [
    _item(1, 'b10.jpg', size: 30, mtime: 1, taken: 300),
    _item(2, 'b9.png', size: 10, mtime: 3, taken: 100),
    _item(3, 'a.heic', size: 20, mtime: 2),
    _item(4, 'c.jpg', size: 20, mtime: 2, taken: 200),
  ];
  List<String> sorted(ItemSort sort, {bool descending = false, int seed = 0}) =>
      [
        for (final a in sortItems(
          items,
          ItemView(sort: sort, descending: descending, seed: seed),
        ))
          a.path!.substring(2),
      ];

  test('every sort orders ascending and descending, ties by name', () {
    expect(sorted(ItemSort.name), ['a.heic', 'b9.png', 'b10.jpg', 'c.jpg']);
    expect(sorted(ItemSort.name, descending: true), [
      'c.jpg',
      'b10.jpg',
      'b9.png',
      'a.heic',
    ]);
    // An item without a capture time is taken when its file was modified.
    expect(sorted(ItemSort.taken), ['a.heic', 'b9.png', 'c.jpg', 'b10.jpg']);
    expect(sorted(ItemSort.modified), ['b10.jpg', 'a.heic', 'c.jpg', 'b9.png']);
    expect(sorted(ItemSort.modified, descending: true), [
      'b9.png',
      'a.heic',
      'c.jpg',
      'b10.jpg',
    ]);
    expect(sorted(ItemSort.size), ['b9.png', 'a.heic', 'c.jpg', 'b10.jpg']);
    expect(sorted(ItemSort.extension), [
      'a.heic',
      'b10.jpg',
      'c.jpg',
      'b9.png',
    ]);
  });

  test('a random order stays the same for its seed and changes with it', () {
    final once = sorted(ItemSort.random, seed: 1);
    expect(sorted(ItemSort.random, seed: 1), once);
    expect(once.toSet(), sorted(ItemSort.name).toSet());
    expect({
      for (var seed = 0; seed < 10; seed++)
        sorted(ItemSort.random, seed: seed).join(),
    }, hasLength(greaterThan(1)));
  });

  test('the custom order is the one given', () {
    expect(sorted(ItemSort.custom), ['b10.jpg', 'b9.png', 'a.heic', 'c.jpg']);
  });

  test('a view round-trips through its stored form', () {
    for (final view in [
      const ItemView(),
      const ItemView(
        sort: ItemSort.size,
        descending: false,
        list: true,
        seed: 7,
      ),
    ]) {
      final back = ItemView.decode(view.encode());
      expect(
        (back.sort, back.descending, back.list, back.seed),
        (view.sort, view.descending, view.list, view.seed),
      );
    }
    expect(ItemView.decode('nonsense').sort, const ItemView().sort);
  });
}
