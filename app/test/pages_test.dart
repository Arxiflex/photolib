import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/pages.dart';

// Every page in the pseudo-locales against its golden and the Material
// accessibility guidelines. The test font draws solid boxes, so the goldens
// match on any platform; refresh them with `--update-goldens`.
void main() {
  for (final locale in pseudoLocales) {
    for (final page in pages) {
      group('$page in $locale', () {
        testWidgets('matches its golden', (tester) async {
          await openPage(tester, locale, page);
          await expectLater(
            find.byType(MaterialApp),
            matchesGoldenFile('goldens/${page}_$locale.png'),
          );
        });

        testWidgets('meets the accessibility guidelines', (tester) async {
          final semantics = tester.ensureSemantics();
          await openPage(tester, locale, page);
          await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
          await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
          await expectLater(tester, meetsGuideline(textContrastGuideline));
          semantics.dispose();
        });
      });
    }
  }
}
