import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:photolib_data/photolib_data.dart';
import 'package:test/test.dart';

void main() {
  late Replica db;
  late List<String> applied;
  setUp(() {
    db = Replica(NativeDatabase.memory());
    applied = [];
  });
  tearDown(() => db.close());

  Future<int> merge(String contents, {String journal = 'share'}) =>
      mergeJournal(db, journal, contents, (entry) async => applied.add(entry));

  test('applies each entry an extension appended once, in order', () async {
    expect(await merge('a\nb\n'), 2);
    expect(await merge('a\nb\n'), 0);
    expect(await merge('a\nb\nc\n'), 1);
    expect(applied, ['a', 'b', 'c']);
  });

  test('ignores a snapshot older than the last merge', () async {
    await merge('a\nb\nc\n');
    expect(await merge('a\n'), 0);
    await merge('a\nb\nc\nd\n');
    expect(applied, ['a', 'b', 'c', 'd']);
  });

  test('leaves a line still being written for the next merge', () async {
    await merge('a\npar');
    await merge('a\npartial\n');
    expect(applied, ['a', 'partial']);
  });

  test('keeps each journal\'s place apart', () async {
    await merge('a\n');
    await merge('x\ny\n', journal: 'upload');
    await merge('a\nb\n');
    expect(applied, ['a', 'x', 'y', 'b']);
  });

  test(
    'applies nothing of a merge that fails, so the next one starts over',
    () async {
      final rows = db.select(db.syncCursor);
      Future<void> apply(String entry) async {
        await db
            .into(db.syncCursor)
            .insert(
              SyncCursorCompanion.insert(
                stream: entry,
                cursor: Uint8List(0),
                updatedAt: 0,
              ),
            );
        if (entry == 'b') throw StateError('cannot apply $entry');
      }

      await expectLater(
        mergeJournal(db, 'share', 'a\nb\n', apply),
        throwsStateError,
      );
      expect(await rows.get(), isEmpty);
      expect(await mergeJournal(db, 'share', 'a\n', apply), 1);
      expect([for (final c in await rows.get()) c.stream], ['a']);
    },
  );
}
