import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:photolib_data/photolib_data.dart';
import 'package:test/test.dart';

void main() {
  late Replica db;
  var n = 0;
  setUp(() {
    n = 0;
    db = Replica(NativeDatabase.memory());
  });
  tearDown(() => db.close());

  Future<void> photo(String taken, {int hidden = 0, int archived = 0}) => db
      .into(db.localAsset)
      .insert(
        LocalAssetCompanion.insert(
          id: Uint8List(16)..[15] = ++n,
          source: 'photokit',
          sourceId: 'asset-$n',
          size: n,
          mtime: 0,
          takenLocal: Value(taken),
          takenUtc: Value(DateTime.parse('${taken}Z').millisecondsSinceEpoch),
          hidden: Value(hidden),
          archived: Value(archived),
        ),
      );

  test('on this day: the newest item of each earlier year taken on the '
      "day's date, newest year first", () async {
    await photo('2024-10-20T09:00:00');
    await photo('2024-10-20T18:00:00');
    await photo('2019-10-20T12:00:00');
    await photo('2024-10-21T12:00:00');
    await photo('2026-10-20T08:00:00');
    for (var year = 2000; year < 2010; year++) {
      await photo('$year-10-20T12:00:00');
    }

    final items = await onThisDay(db, DateTime(2026, 10, 20, 23));

    expect(
      [for (final item in items) item.sourceId],
      ['asset-2', 'asset-3', 'asset-15', 'asset-14', 'asset-13', 'asset-12'],
    );
  });

  test('hidden and archived items are no memories', () async {
    await photo('2024-10-20T09:00:00', hidden: 1);
    await photo('2023-10-20T09:00:00', archived: 1);
    await photo('2022-10-20T09:00:00');
    expect(
      [
        for (final item in await onThisDay(db, DateTime(2026, 10, 20)))
          item.sourceId,
      ],
      ['asset-3'],
    );
  });

  test('a day with nothing taken in earlier years has nothing', () async {
    await photo('2026-10-20T08:00:00');
    expect(await onThisDay(db, DateTime(2026, 10, 20)), isEmpty);
  });
}
