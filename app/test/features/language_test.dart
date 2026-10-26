import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show LocaleStringAttribute;

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:photolib/features/library/timeline/pipeline.dart';
import 'package:photolib/features/library/timeline/providers.dart';
import 'package:photolib/l10n/app_localizations.dart';
import 'package:photolib/l10n/formats.dart';
import 'package:photolib_data/photolib_data.dart';

import '../support/pump_app.dart';

/// [key]'s message in the translation into [locale].
String arb(String locale, String key) =>
    (jsonDecode(File('lib/l10n/app_$locale.arb').readAsStringSync())
            as Map<String, Object?>)[key]!
        as String;

void main() {
  TextDirection direction(WidgetTester tester) =>
      Directionality.of(tester.element(find.byType(NavigationBar)));

  testWidgets('Settings lists the device language and every launch language '
      'in its own name; a choice re-renders every screen at once, Arabic and '
      'Hebrew right to left', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpApp(tester);
    await tester.tapAndSettle(find.byTooltip('Settings'));
    await tester.tapAndSettle(find.text('Language'));
    final options = find.byType(RadioListTile<Locale?>);
    expect(
      [
        for (final tile in tester.widgetList<RadioListTile<Locale?>>(options))
          ((tile.title! as Text).data, tile.value?.toLanguageTag()),
      ],
      [
        ('Device language', null),
        ('English', 'en'),
        ('Español', 'es'),
        ('Français', 'fr'),
        ('Deutsch', 'de'),
        ('Italiano', 'it'),
        ('Português (Brasil)', 'pt'),
        ('Русский', 'ru'),
        ('Українська', 'uk'),
        ('Polski', 'pl'),
        ('Nederlands', 'nl'),
        ('Türkçe', 'tr'),
        ('العربية', 'ar'),
        ('עברית', 'he'),
        ('हिन्दी', 'hi'),
        ('日本語', 'ja'),
        ('한국어', 'ko'),
        ('简体中文', 'zh'),
        ('繁體中文', 'zh-Hant'),
        ('Bahasa Indonesia', 'id'),
        ('Tiếng Việt', 'vi'),
        ('Svenska', 'sv'),
      ],
    );
    expect(
      tester.widget<RadioGroup<Locale?>>(find.byType(RadioGroup<Locale?>)),
      isA<RadioGroup<Locale?>>().having((g) => g.groupValue, 'chosen', null),
    );
    expect(
      tester.getSemantics(find.text('Deutsch')).attributedLabel.attributes,
      [
        isA<LocaleStringAttribute>()
            .having((a) => a.locale, 'spoken in', const Locale('de'))
            .having((a) => a.range, 'over', const TextRange(start: 0, end: 7)),
      ],
      reason: 'a screen reader says each name in its language',
    );
    var current = 'en';
    for (final (i, (locale, name)) in [
      ('de', 'Deutsch'),
      ('ar', 'العربية'),
      ('he', 'עברית'),
      ('en', arb('he', 'languageDevice')),
    ].indexed) {
      if (i > 0) {
        await tester.tapAndSettle(
          find.byTooltip(arb(current, 'settingsTitle')),
        );
        await tester.tapAndSettle(find.text(arb(current, 'settingsLanguage')));
      }
      await tester.ensureVisible(find.text(name));
      await tester.tapAndSettle(find.text(name));
      current = locale;
      final rtl = locale == 'ar' || locale == 'he';
      expect(options, findsNothing, reason: 'the choice closes the list');
      expect(find.text(arb(locale, 'settingsTitle')), findsOneWidget);
      expect(
        find.text(arb(locale, 'tabLibrary'), skipOffstage: false),
        findsOneWidget,
        reason: 'the screen under Settings',
      );
      expect(
        tester.getCenter(find.byType(BackButton)).dx > 400 / 2,
        rtl,
        reason: '$locale mirrors the layout, or not',
      );
      await tester.tapAndSettle(find.byType(BackButton));
      expect(find.text(arb(locale, 'tabLibrary')), findsOneWidget);
      expect(direction(tester), rtl ? TextDirection.rtl : TextDirection.ltr);
    }
    semantics.dispose();
  });

  for (final (stored, shown) in [('de', 'de'), ('eo', 'fr'), ('en-XA', 'fr')]) {
    testWidgets('a device in French with "$stored" stored shows '
        '${shown == 'fr' ? 'French: the build ships no $stored' : stored}', (
      tester,
    ) async {
      await pumpApp(
        tester,
        locales: const [Locale('fr')],
        settings: MemoryStore(jsonEncode({'language': stored})),
      );
      expect(find.text(arb(shown, 'tabLibrary')), findsOneWidget);
    });
  }

  testWidgets('dates, numbers and file sizes follow the language chosen', (
    tester,
  ) async {
    final db = Replica(NativeDatabase.memory());
    addTearDown(db.close);
    await db
        .into(db.localAsset)
        .insert(
          LocalAssetCompanion.insert(
            id: Uint8List(16),
            source: 'folder',
            volume: const Value('/p'),
            sourceId: '1',
            path: const Value('1.jpg'),
            size: 1,
            mtime: 0,
            takenLocal: const Value('2024-05-03T12:00:00'),
          ),
        );
    await pumpApp(
      tester,
      replica: (_) => db,
      settings: MemoryStore(jsonEncode({'language': 'de'})),
      overrides: [
        thumbnailPipelineProvider.overrideWith(
          (ref) async => ThumbnailPipeline(),
        ),
      ],
    );
    expect(find.text('3. Mai 2024'), findsOneWidget);
    final formats = Formats(
      AppLocalizations.of(tester.element(find.byType(NavigationBar))),
    );
    expect(formats.number(1234567.5), '1.234.567,5');
    expect(formats.fileSize(1500000), '1,5 MB');
    expect(formats.firstDayOfWeek, DateTime.monday);
    // Drift closes its queries on the test's clock, before the database.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
  });
}
