import 'package:flutter_test/flutter_test.dart';
import 'package:photolib/features/folders/rename.dart';

void main() {
  final files = [
    (name: 'IMG_0001.JPG', taken: DateTime(2024, 5, 3, 14, 5, 9)),
    (name: 'IMG_0002.jpg', taken: DateTime(2024, 12, 31, 23, 59)),
    (name: 'notes', taken: DateTime(2023)),
  ];
  List<String?> names(RenamePattern pattern, {Set<String> others = const {}}) =>
      [for (final r in planRename(files, pattern, others: others)) r.name];

  test('the pattern names each file, keeping its extension', () {
    expect(names(const RenamePattern(template: 'Trip {name}')), [
      'Trip IMG_0001.JPG',
      'Trip IMG_0002.jpg',
      'Trip notes',
    ]);
    expect(names(const RenamePattern(template: '{name}-edit')), [
      'IMG_0001-edit.JPG',
      'IMG_0002-edit.jpg',
      'notes-edit',
    ]);
    expect(names(const RenamePattern(template: 'Rome {nnn}')), [
      'Rome 001.JPG',
      'Rome 002.jpg',
      'Rome 003',
    ]);
    expect(names(const RenamePattern(template: '{n}')), [
      '1.JPG',
      '2.jpg',
      '3',
    ]);
    expect(
      names(const RenamePattern(template: '{yyyy}-{MM}-{dd} {HH}.{mm}.{ss}')),
      [
        '2024-05-03 14.05.09.JPG',
        '2024-12-31 23.59.00.jpg',
        '2023-01-01 00.00.00',
      ],
    );
    expect(names(const RenamePattern(find: 'IMG_', replace: 'Rome_')), [
      'Rome_0001.JPG',
      'Rome_0002.jpg',
      null,
    ], reason: 'a name that stays is not renamed');
  });

  test('a name over the limit, invalid, taken or given twice is refused '
      'with its reason, never cut short', () {
    final long = 'x' * 252;
    final plan = planRename(files, RenamePattern(template: long));
    expect(
      [for (final r in plan) r.problem],
      [RenameProblem.tooLong, RenameProblem.tooLong, null],
    );
    expect(plan[2].name, long, reason: '252 bytes fit');
    expect(plan[0].name, '$long.JPG', reason: 'shown whole');
    // 127 two-byte characters and a letter are 255 bytes; 86 of three are 258.
    expect(
      planRename([
        files[2],
      ], RenamePattern(template: 'é' * 127 + 'a')).single.problem,
      null,
    );
    expect(
      planRename([files[2]], RenamePattern(template: '日' * 86)).single.problem,
      RenameProblem.tooLong,
    );
    for (final bad in ['a/b', '', '.', '..', 'a\u0000']) {
      expect(
        planRename([files[2]], RenamePattern(template: bad)).single.problem,
        RenameProblem.invalid,
        reason: bad,
      );
    }
    expect(
      [
        for (final r in planRename(
          files,
          const RenamePattern(template: 'same'),
        ))
          r.problem,
      ],
      [null, RenameProblem.duplicate, null],
      reason: 'same.JPG and same.jpg are one name where case does not count',
    );
    expect(
      planRename(
        files,
        const RenamePattern(template: 'a'),
        others: {'A.JPG'},
      ).first.problem,
      RenameProblem.exists,
      reason: 'another file of the folder has the name, in any case',
    );
    expect(
      isRenamable(planRename(files, RenamePattern(template: long))),
      isFalse,
    );
    expect(
      isRenamable(planRename(files, const RenamePattern(template: 'x{n}'))),
      isTrue,
    );
  });
}
