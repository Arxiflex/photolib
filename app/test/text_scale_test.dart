import 'dart:io';

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'gallery_test.dart' show pumpGallery;
import 'support/pages.dart';

// Text scaled to 200 % is never clipped (docs/17-i18n-and-accessibility.md §5),
// measured with the app's Roboto rather than the test font's 1 em wide boxes.

/// Visible text cut short by its own box, or off the screen outside anything
/// that scrolls.
List<String> _clipped(WidgetTester tester) {
  final screen = Offset.zero & tester.view.physicalSize;
  bool scrolls(RenderObject? box) =>
      box != null && (box is RenderAbstractViewport || scrolls(box.parent));
  bool onScreen(RenderBox box) {
    final rect = MatrixUtils.transformRect(
      box.getTransformTo(null),
      Offset.zero & box.size,
    );
    return screen.expandToInclude(rect) == screen;
  }

  return [
    for (final text in tester.renderObjectList<RenderParagraph>(
      find.byType(RichText),
    ))
      if (text.didExceedMaxLines ||
          text.textSize.width > text.size.width + 0.5 ||
          text.textSize.height > text.size.height + 0.5 ||
          !(scrolls(text) || onScreen(text)))
        text.text.toPlainText(),
  ];
}

void main() {
  setUpAll(() async {
    final roboto = FontLoader('Roboto');
    for (final weight in ['Regular', 'Medium']) {
      final bytes = File('assets/fonts/Roboto-$weight.ttf').readAsBytesSync();
      roboto.addFont(Future.value(ByteData.sublistView(bytes)));
    }
    await roboto.load();
  });

  for (final locale in pseudoLocales) {
    for (final width in const [400.0, 700.0, 1280.0]) {
      testWidgets('the component gallery in $locale, ${width.toInt()} px '
          'wide, shows all its text at 200 % text size', (tester) async {
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await pumpGallery(tester, locale: locale, size: Size(width, 2000));
        expect(_clipped(tester), isEmpty);
      });
    }

    for (final page in pages) {
      for (final size in const [
        Size(400, 800),
        Size(700, 800),
        Size(1280, 800),
      ]) {
        testWidgets('$page in $locale, ${size.width.toInt()} px wide, shows '
            'all its text at 200 % text size', (tester) async {
          tester.platformDispatcher.textScaleFactorTestValue = 2;
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          await openPage(tester, locale, page, size: size);
          expect(_clipped(tester), isEmpty);
        });
      }
    }
  }
}
