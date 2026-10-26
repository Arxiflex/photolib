import 'dart:io';
import 'dart:math';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
import 'package:photolib/features/library/timeline/pipeline.dart';
import 'package:photolib/features/viewer/deep_zoom.dart';
import 'package:photolib/features/viewer/info_facts.dart';

import '../../support/info_facts.dart';
import '../../support/pump_app.dart';
import '../../support/viewer.dart';

void main() {
  final panel = find.byKey(const ValueKey('info'));
  final photo = find.byType(DeepZoom).hitTestable();

  Future<Grey> pump(
    WidgetTester tester,
    FakeFacts facts, {
    double width = 1000,
    double height = 900,
    String? timeSource,
  }) async {
    final pipeline = Grey(width: 400, height: 300);
    await pumpViewer(
      tester,
      pipeline: pipeline,
      size: Size(width, height),
      ids: true,
      rowOf: (item) => row(item).copyWith(
        width: const Value(4000),
        height: const Value(3000),
        make: const Value('Canon'),
        model: const Value('EOS R5'),
        lat: const Value(37.35),
        lon: const Value(23.47),
        timeSource: Value(timeSource),
        tzOffsetMin: const Value(180),
      ),
      overrides: [infoFactsProvider.overrideWith((ref) async => facts)],
    );
    await tester.pressKey(LogicalKeyboardKey.keyI, character: 'i');
    await tester.pumpAndSettle();
    return pipeline;
  }

  testWidgets('from 760 dp a 340 dp panel pushes the photo; below, a sheet '
      'with peek, half and full detents leaves the photo as it was', (
    tester,
  ) async {
    await pump(tester, FakeFacts(), width: 760);
    expect(tester.getSize(panel).width, 340);
    expect(tester.getSize(photo).width, 420);
    await tester.pumpWidget(const SizedBox());
    await pumpViewer(tester, size: const Size(759, 900));
    final before = tester.getRect(photo);
    await tester.pressKey(LogicalKeyboardKey.keyI, character: 'i');
    await tester.pumpAndSettle();
    final sheet = tester.widget<DraggableScrollableSheet>(panel);
    expect(sheet.snapSizes, [0.25, 0.5, 0.9]);
    expect(sheet.initialChildSize, 0.25);
    expect(tester.getRect(photo), before);
  });

  testWidgets('its sections come in order, with no Details heading: a '
      'description saved as typed, people, the date read in the file name, '
      'the file, camera, place, storage, edit history, albums, tags and all '
      'metadata', (tester) async {
    final facts = FakeFacts(
      faces: true,
      people: [const InfoFace(Rect.fromLTWH(0.4, 0.3, 0.1, 0.1), name: 'Ana')],
      text: '',
      history: [
        InfoVersion('Original', DateTime(2026, 10, 20), original: true),
        InfoVersion('Crop', DateTime(2026, 10, 23, 12, 49), current: true),
      ],
      tags: ['Travel/Greece/Sailing'],
    );
    await pump(
      tester,
      facts,
      height: 1600,
      timeSource: 'filename:IMG_20240503_120000',
    );
    expect(find.text('Details'), findsNothing);
    final taken = DateFormat.yMMMd('en')
        .add_jm()
        .format(DateTime(2024, 5, 3, 12));
    final rows = [
      'Add a description',
      'Ana',
      '$taken UTC+3',
      'from file name',
      '12 MP · 4,000 × 3,000 · 1 B',
      'Canon EOS R5',
      '37.35000, 23.47000',
      'On this device · Backed up',
      'Edit history',
      'Albums',
      'Not in any album',
      'Tags',
      'Greece › Sailing',
      'View all metadata',
    ];
    expect([
      for (final text in rows)
        if (find.text(text).evaluate().isEmpty) text,
    ], isEmpty);
    final tops = [
      for (final text in rows) tester.getTopLeft(find.text(text).first).dy,
    ];
    expect(tops, orderedEquals([...tops]..sort()), reason: '$rows');
    final last = DateFormat.yMMMd('en')
        .add_jm()
        .format(DateTime(2026, 10, 23, 12, 49));
    expect(find.text('2 versions · last $last'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Hydra harbour');
    expect(facts.calls, ['describe Hydra harbour']);
  });

  testWidgets('the camera row has the lens and the exposure line', (
    tester,
  ) async {
    await pump(
      tester,
      FakeFacts(
        lens: (
          lens: 'XF 23mm F1.4 R LM WR',
          aperture: 1.8,
          exposure: 1 / 120,
          iso: 100,
          focal: 26,
        ),
      ),
    );
    expect(
      find.text('XF 23mm F1.4 R LM WR\nƒ/1.8 · 1/120 s · ISO 100 · 26 mm'),
      findsOneWidget,
    );
  });

  testWidgets('sections with nothing to show are absent, but Albums and '
      'Tags', (tester) async {
    await pump(tester, FakeFacts());
    for (final absent in ['Add a description', 'Edit history', 'Add name']) {
      expect(find.text(absent), findsNothing, reason: absent);
    }
    expect(find.text('Not in any album'), findsOneWidget);
    expect(find.text('Add tag'), findsOneWidget);
  });

  testWidgets('people show round crops with names, Add name for an unnamed '
      'face; hovering one outlines it on the photo, a toggle keeps all, a tap '
      "opens the person's photos", (tester) async {
    final facts = FakeFacts(
      faces: true,
      people: [
        const InfoFace(Rect.fromLTWH(0.2, 0.2, 0.2, 0.2), name: 'Ana'),
        const InfoFace(Rect.fromLTWH(0.6, 0.2, 0.2, 0.2)),
      ],
    );
    await pump(tester, facts);
    expect(find.text('Add name'), findsOneWidget);
    final outline = find.byWidgetPredicate(
      (w) => w is Positioned && w.key is ValueKey<InfoFace>,
    );
    expect(outline, findsNothing);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: tester.getCenter(find.text('Ana')));
    await tester.pump();
    expect(outline, findsOneWidget);
    // 0.2 of the photo, 4:3 in the stage.
    final stage = tester.getRect(photo);
    final fitted = Rect.fromCenter(
      center: stage.center,
      width: min(stage.width, stage.height * 4 / 3),
      height: min(stage.height, stage.width * 3 / 4),
    );
    expect(
      tester.getRect(outline).topLeft,
      offsetMoreOrLessEquals(
        fitted.topLeft + Offset(fitted.width * 0.2, fitted.height * 0.2),
      ),
    );
    // Its name right under it, as in the prototype.
    final name = tester.getRect(
      find.descendant(of: outline, matching: find.text('Ana')),
    );
    expect(name.top, moreOrLessEquals(tester.getRect(outline).bottom));
    expect(name.center.dx, moreOrLessEquals(tester.getCenter(outline).dx));
    expect(name.height, lessThan(40));
    await mouse.moveTo(const Offset(5, 5));
    await tester.pump();
    expect(outline, findsNothing);
    await tester.tap(find.byTooltip('Show faces on the photo'));
    await tester.pump();
    expect(outline, findsNWidgets(2));
    await tester.tap(find.descendant(of: panel, matching: find.text('Ana')));
    expect(facts.calls, ['person Ana']);
  });

  testWidgets('albums show their folders, count and sharing; an ✕ takes the '
      'item out of that album alone with a 5 s undo, if allowed; Auto albums '
      'have none, and a tag album appears with its tag', (tester) async {
    const sailing = InfoAlbum(
      'g',
      'Sailing Greece 2026',
      path: ['Trips', 'Greece'],
      count: 412,
    );
    const mila = InfoAlbum(
      'm',
      'Mila',
      count: 88,
      shared: true,
      removable: false,
    );
    const sunsets = InfoAlbum('s', 'Sunsets', count: 230, auto: true);
    const greece = InfoAlbum(
      't',
      'Greece',
      count: 1180,
      auto: true,
      tag: 'Travel/Greece',
    );
    final facts = FakeFacts(
      albums: [sailing, mila, sunsets],
      tagAlbumList: [greece],
      all: ['Travel/Greece/Hydra'],
    );
    await pump(tester, facts);
    expect(find.text('Trips › Greece'), findsOneWidget);
    expect(find.text('412 items'), findsOneWidget);
    expect(find.text('88 items · shared'), findsOneWidget);
    expect(find.text('Auto'), findsOneWidget);
    expect(find.byTooltip('Remove from Sunsets'), findsNothing);
    expect(
      tester
          .widget<IconButton>(
            find.ancestor(
              of: find.byTooltip('Remove from Mila'),
              matching: find.byType(IconButton),
            ),
          )
          .onPressed,
      isNull,
      reason: 'a shared album needs the permission',
    );
    await tester.tap(find.text('Sailing Greece 2026'));
    await tester.tap(find.byTooltip('Remove from Sailing Greece 2026'));
    await tester.pumpAndSettle();
    expect(find.text('Sailing Greece 2026'), findsNothing);
    expect(find.text('Removed from Sailing Greece 2026'), findsOneWidget);
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(find.text('Sailing Greece 2026'), findsOneWidget);
    expect(facts.calls, [
      'album Sailing Greece 2026',
      'leave Sailing Greece 2026',
      'join Sailing Greece 2026',
    ]);
    expect(find.text('Greece'), findsNothing);
    await tester.tap(find.text('Add tag'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('tag-field')), 'hydra');
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text('Greece'), findsOneWidget, reason: 'its tag album');
  });

  testWidgets('tags are chips of parent and tag with the path as tooltip; a '
      'tap opens one, its ✕ takes it off; Add tag takes a path, suggests '
      'tags and their parents, picked with the arrows and Enter, and offers '
      'anything else as a new tag', (tester) async {
    final facts = FakeFacts(
      tags: ['Travel/Greece/Sailing', 'Food'],
      all: ['Travel/Greece/Sailing', 'Travel/Greece/Hydra', 'Food'],
    );
    await pump(tester, facts);
    expect(find.byTooltip('Travel › Greece › Sailing'), findsOneWidget);
    await tester.tap(find.text('Greece › Sailing'));
    await tester.tap(find.byTooltip('Remove Food'));
    await tester.pumpAndSettle();
    expect(find.text('Food'), findsNothing);
    await tester.tap(find.text('Add tag'));
    await tester.pumpAndSettle();
    final field = find.byKey(const ValueKey('tag-field'));
    await tester.enterText(field, 'greece');
    await tester.pump();
    final offered = [
      for (final tile in tester.widgetList<ListTile>(
        find.descendant(
          of: find.ancestor(of: field, matching: find.byType(Column)).first,
          matching: find.byType(ListTile),
        ),
      ))
        (tile.title! as Text).data,
    ];
    expect(offered, [
      'Travel › Greece',
      'Travel › Greece › Hydra',
      'Travel › Greece › Sailing',
      'New tag: greece',
    ]);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add tag'));
    await tester.pumpAndSettle();
    await tester.enterText(field, ' Travel/ Italy /Rome');
    await tester.pump();
    expect(find.text('New tag: Travel/Italy/Rome'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(facts.calls, [
      'open Travel/Greece/Sailing',
      'untag Food',
      'tag Travel/Greece/Hydra',
      'tag Travel/Italy/Rome',
    ]);
  });

  test('a tag path drops empty levels; a parent finds what is under it', () {
    expect(tagPath(' a//b / c '), 'a/b/c');
    const all = ['Travel/Greece/Hydra', 'Food/Greek'];
    expect(tagSuggestions(all, 'gree'), [
      'Food/Greek',
      'Travel/Greece',
      'Travel/Greece/Hydra',
    ]);
    expect(tagSuggestions(all, 'Travel/G'), [
      'Travel/Greece',
      'Travel/Greece/Hydra',
    ]);
    expect(tagSuggestions(all, ' / '), isEmpty);
    const greece = InfoAlbum('t', 'Greece', tag: 'Travel/Greece');
    expect(matchingTagAlbums([greece], ['Travel/Greece/Hydra']), [greece]);
    expect(matchingTagAlbums([greece], ['Travel/Greeces']), isEmpty);
  });

  testWidgets('the edit history opens in the panel, newest first, the current '
      'marked, older ones reverted, any saved as a copy, the original '
      'compared in the photo; ⋮ opens it too', (tester) async {
    final original = ThumbnailItem('o', Uri.file('/p/original.jpg'));
    final facts = FakeFacts(
      history: [
        InfoVersion(
          'Original',
          DateTime(2026, 10, 20),
          device: 'Camera',
          original: true,
          item: original,
        ),
        InfoVersion(
          'Crop',
          DateTime(2026, 10, 23, 12, 49),
          device: 'MacBook',
          change: 'Cropped 4:3',
          current: true,
        ),
      ],
    );
    final pipeline = await pump(tester, facts);
    await tester.tap(find.text('Edit history'));
    await tester.pumpAndSettle();
    final cards = [
      for (final title in tester.widgetList<ListTile>(
        find.descendant(of: find.byType(Card), matching: find.byType(ListTile)),
      ))
        (title.title! as Text).data,
    ];
    expect(cards, ['Crop · Current', 'Original']);
    expect(find.text('Revert'), findsOneWidget);
    await tester.tap(find.text('Revert'));
    await tester.tap(find.text('Save as copy').first);
    await tester.tap(find.text('Compare with original'));
    await tester.pumpAndSettle();
    expect(pipeline.asked, contains(original.uri));
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('View all metadata'), findsOneWidget);
    expect(facts.calls, ['revert Original', 'copy Crop']);
    await tester.pressKey(LogicalKeyboardKey.keyI, character: 'i');
    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit history'));
    await tester.pumpAndSettle();
    expect(find.text('Crop · Current'), findsOneWidget);
  });

  testWidgets('the history names the versions nobody named, numbered from the '
      'oldest edit, says what each changed and offers no copy or comparison '
      'it cannot make', (tester) async {
    final facts = FakeFacts(
      history: [
        InfoVersion('', DateTime(2026, 10, 20), original: true),
        InfoVersion(
          '',
          DateTime(2026, 10, 21),
          changes: const ['crop', 'turn'],
        ),
        InfoVersion(
          '',
          DateTime(2026, 10, 22),
          changes: const ['adjust', 'unheard-of'],
          current: true,
        ),
      ],
    );
    await pump(tester, facts);
    await tester.tap(find.text('Edit history'));
    await tester.pumpAndSettle();
    final cards = [
      for (final tile in tester.widgetList<ListTile>(
        find.descendant(of: find.byType(Card), matching: find.byType(ListTile)),
      ))
        ((tile.title! as Text).data, (tile.subtitle! as Text).data!),
    ];
    expect(
      [for (final (title, _) in cards) title],
      ['Edit 2 · Current', 'Edit 1', 'Original'],
    );
    expect(cards[0].$2, endsWith('\nAdjusted colours, Edited'));
    expect(cards[1].$2, endsWith('\nCropped, Rotated'));
    expect(cards[2].$2, isNot(contains('\n')), reason: 'it changed nothing');
    expect(
      find.text('Compare with original'),
      findsNothing,
      reason: 'the original has no picture here',
    );
  });

  testWidgets('no map tile is asked for before the user agrees', (
    tester,
  ) async {
    final asked = <Uri>[];
    await HttpOverrides.runZoned(() async {
      await pump(tester, FakeFacts());
      expect(find.text('Show map'), findsOneWidget);
    }, createHttpClient: (_) => _Recording(asked));
    expect(asked, isEmpty);
  });
}

class _Recording implements HttpClient {
  new(this.asked);

  final List<Uri> asked;

  @override
  Future<HttpClientRequest> getUrl(Uri url) {
    asked.add(url);
    throw UnimplementedError();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
