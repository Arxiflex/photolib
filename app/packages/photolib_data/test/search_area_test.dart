import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:photolib_data/photolib_data.dart';
import 'package:test/test.dart';

void main() {
  late Replica db;
  setUp(() => db = Replica(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<void> add(int n, double? lat, double? lon, {String name = ''}) => db
      .into(db.localAsset)
      .insert(
        LocalAssetCompanion.insert(
          id: Uint8List(16)..[15] = n,
          source: 'folder',
          sourceId: '$n',
          size: 1,
          mtime: 0,
          path: Value('Trip/IMG_$n$name.jpg'),
          lat: Value(lat),
          lon: Value(lon),
        ),
      );

  Future<List<int>> found(LocalQuery query) async => [
    for (final a in (await searchPage(db, query, limit: 100)).items) a.id[15],
  ]..sort();

  test('an area keeps what is located inside it, edges included', () async {
    await add(1, 48.85, 2.35); // Paris
    await add(2, 38.72, -9.14); // Lisbon
    await add(3, null, null);
    await add(4, 48, 2); // on the corner
    const paris = Area(west: 2, south: 48, east: 3, north: 49);
    expect(await found(const LocalQuery(area: paris)), [1, 4]);
    expect(await found(const LocalQuery()), [1, 2, 3, 4]);
  });

  test('an area across the antimeridian takes both sides', () async {
    await add(1, 0, 179.5);
    await add(2, 0, -179.5);
    await add(3, 0, 0);
    const across = Area(west: 170, south: -10, east: -170, north: 10);
    expect(await found(const LocalQuery(area: across)), [1, 2]);
  });

  test('an area adds to the other filters and is a filter itself', () async {
    await add(1, 1, 1, name: '_beach');
    await add(2, 1, 1);
    await add(3, 50, 50, name: '_beach');
    const area = Area(west: 0, south: 0, east: 2, north: 2);
    final query = const LocalQuery(text: 'beach').copyWith(area: (value: area));
    expect(await found(query), [1]);
    expect(query.isEmpty, isFalse);
    expect(const LocalQuery(area: area).isEmpty, isFalse);
    expect(query.copyWith(area: (value: null)).area, isNull);
  });
}
